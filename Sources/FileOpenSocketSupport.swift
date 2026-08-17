import Bonsplit
import Foundation

extension TerminalController {
    func v2ResolveReadableFilePath(_ rawPath: String) -> (path: String?, error: V2CallResult?) {
        let expandedPath = NSString(string: rawPath).expandingTildeInPath
        let filePath = NSString(string: expandedPath).standardizingPath

        guard filePath.hasPrefix("/") else {
            return (
                nil,
                .err(
                    code: "invalid_params",
                    message: "Path must be absolute: \(filePath)",
                    data: ["path": filePath]
                )
            )
        }

        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: filePath, isDirectory: &isDir) else {
            return (
                nil,
                .err(code: "not_found", message: "File not found: \(filePath)", data: ["path": filePath])
            )
        }
        guard !isDir.boolValue else {
            return (
                nil,
                .err(
                    code: "invalid_params",
                    message: "Path is a directory, not a file: \(filePath)",
                    data: ["path": filePath]
                )
            )
        }
        guard FileManager.default.isReadableFile(atPath: filePath) else {
            return (
                nil,
                .err(
                    code: "permission_denied",
                    message: "File not readable: \(filePath)",
                    data: ["path": filePath]
                )
            )
        }

        return (filePath, nil)
    }

    private func v2FileOpenSurfacePayload(
        workspace: Workspace,
        panel: any Panel
    ) -> [String: Any] {
        let paneUUID = workspace.paneId(forPanelId: panel.id)?.id
        var payload: [String: Any] = [
            "surface_id": panel.id.uuidString,
            "surface_ref": v2Ref(kind: .surface, uuid: panel.id),
            "pane_id": v2OrNull(paneUUID?.uuidString),
            "pane_ref": v2Ref(kind: .pane, uuid: paneUUID),
            "panel_type": panel.panelType.rawValue
        ]
        if let previewPanel = panel as? FilePreviewPanel {
            payload["path"] = previewPanel.filePath
            payload["preview_mode"] = previewPanel.previewMode.socketName
        } else if let markdownPanel = panel as? MarkdownPanel {
            payload["path"] = markdownPanel.filePath
            payload["display_mode"] = markdownPanel.displayMode.rawValue
        }
        return payload
    }

    func v2FileOpen(params: [String: Any]) -> V2CallResult {
        guard let tabManager = v2ResolveTabManager(params: params) else {
            return .err(code: "unavailable", message: "TabManager not available", data: nil)
        }

        let rawPaths = v2StringArray(params, "paths") ?? v2StringArray(params, "path") ?? []
        guard !rawPaths.isEmpty else {
            return .err(code: "invalid_params", message: "Missing 'path' or 'paths' parameter", data: nil)
        }

        var filePaths: [String] = []
        for rawPath in rawPaths {
            let resolved = v2ResolveReadableFilePath(rawPath)
            if let error = resolved.error {
                return error
            }
            if let path = resolved.path {
                filePaths.append(path)
            }
        }

        let shouldFocus = v2FocusAllowed(requested: v2Bool(params, "focus") ?? true)
        var result: V2CallResult = .err(code: "internal_error", message: "Failed to open file", data: nil)
        v2MainSync {
            guard let ws = v2ResolveWorkspace(params: params, tabManager: tabManager) else {
                result = .err(code: "not_found", message: "Workspace not found", data: nil)
                return
            }

            if shouldFocus {
                v2MaybeFocusWindow(for: tabManager)
                v2MaybeSelectWorkspace(tabManager, workspace: ws)
            }

            let requestedPaneUUID = v2UUID(params, "pane_id")
            let requestedSurfaceUUID = v2UUID(params, "surface_id")
            let hasExplicitPaneDestination = requestedPaneUUID != nil || requestedSurfaceUUID != nil
            let paneId: PaneID?
            if let paneUUID = requestedPaneUUID {
                paneId = ws.bonsplitController.allPaneIds.first(where: { $0.id == paneUUID })
                if paneId == nil {
                    result = .err(code: "not_found", message: "Pane not found", data: ["pane_id": paneUUID.uuidString])
                    return
                }
            } else if let surfaceId = requestedSurfaceUUID {
                guard ws.panels[surfaceId] != nil else {
                    result = .err(
                        code: "not_found",
                        message: "Source surface not found",
                        data: ["surface_id": surfaceId.uuidString]
                    )
                    return
                }
                paneId = ws.paneId(forPanelId: surfaceId)
            } else {
                paneId = ws.bonsplitController.focusedPaneId ?? ws.bonsplitController.allPaneIds.first
            }

            guard let paneId else {
                result = .err(code: "not_found", message: "Pane not found", data: nil)
                return
            }

            // Without an explicit destination, open beside the caller rather than on top of
            // it. `cmux open` is typically run from the terminal the user is watching, and
            // adding a tab to that same pane hides the very session that asked for the file.
            // The file explorer and terminal Cmd-click already route through
            // `openOrFocusFilePreviewSplit`, which reuses a right-hand pane or splits one
            // into being; sharing that path is what keeps the three entry points agreeing.
            // A single file with no explicit destination goes to the dedicated code-review
            // column. That column is a sibling of the terminal area rather than a pane inside
            // it, so reading a file never moves or shrinks the session that asked for it, and
            // opening a second file adds a tab there instead of splitting again.
            if !hasExplicitPaneDestination,
               filePaths.count == 1,
               let column = AppDelegate.shared?.openFileInCodeReviewColumn(filePath: filePaths[0]) {
                // Reported through the same payload builder as every other open path. The
                // column has its own workspace, so a real pane and surface exist; answering
                // with nulls would make "the response names the surface it opened" false for
                // exactly the case that is now the default.
                //
                // `workspace_id` is the column's workspace, not the one the request arrived
                // through — that is where the file actually is. It is not owned by the tab
                // manager, so it does not appear in `cmux workspace list`; `opened_in` is
                // what tells a client this is the column rather than a tab.
                let windowId = v2ResolveWindowId(tabManager: tabManager)
                let surfacePayload = v2FileOpenSurfacePayload(
                    workspace: column.workspace,
                    panel: column.panel
                )
                var response: [String: Any] = [
                    "window_id": v2OrNull(windowId?.uuidString),
                    "window_ref": v2Ref(kind: .window, uuid: windowId),
                    "workspace_id": column.workspace.id.uuidString,
                    "workspace_ref": v2Ref(kind: .workspace, uuid: column.workspace.id),
                    "pane_id": surfacePayload["pane_id"] ?? NSNull(),
                    "pane_ref": surfacePayload["pane_ref"] ?? NSNull(),
                    "surface_id": surfacePayload["surface_id"] ?? NSNull(),
                    "surface_ref": surfacePayload["surface_ref"] ?? NSNull(),
                    "panel_type": surfacePayload["panel_type"] ?? NSNull(),
                    "path": surfacePayload["path"] ?? filePaths[0],
                    "paths": filePaths,
                    "surfaces": [surfacePayload],
                    "opened_in": "code_review_column"
                ]
                if let previewMode = surfacePayload["preview_mode"] {
                    response["preview_mode"] = previewMode
                }
                result = .ok(response)
                return
            }

            let openedPanels: [any Panel]
            if !hasExplicitPaneDestination,
               filePaths.count == 1,
               let sourcePanelId = ws.focusedPanelId,
               let opened = ws.openFileBesideSource(from: sourcePanelId, filePath: filePaths[0]) {
                openedPanels = [opened]
            } else {
                openedPanels = ws.openFileSurfaces(
                    inPane: paneId,
                    filePaths: filePaths,
                    focus: shouldFocus,
                    reuseExisting: filePaths.count == 1 && !hasExplicitPaneDestination
                )
            }
            guard !openedPanels.isEmpty else {
                result = .err(code: "internal_error", message: "Failed to open file", data: nil)
                return
            }

            let windowId = v2ResolveWindowId(tabManager: tabManager)
            let surfacePayloads = openedPanels.map {
                v2FileOpenSurfacePayload(workspace: ws, panel: $0)
            }
            let primary = surfacePayloads.last ?? [:]
            let paneUUID = ws.paneId(forPanelId: openedPanels.last?.id ?? openedPanels[0].id)?.id
            var response: [String: Any] = [
                "window_id": v2OrNull(windowId?.uuidString),
                "window_ref": v2Ref(kind: .window, uuid: windowId),
                "workspace_id": ws.id.uuidString,
                "workspace_ref": v2Ref(kind: .workspace, uuid: ws.id),
                "pane_id": v2OrNull(paneUUID?.uuidString),
                "pane_ref": v2Ref(kind: .pane, uuid: paneUUID),
                "surface_id": primary["surface_id"] ?? NSNull(),
                "surface_ref": primary["surface_ref"] ?? NSNull(),
                "panel_type": primary["panel_type"] ?? NSNull(),
                "path": primary["path"] ?? NSNull(),
                "paths": filePaths,
                "surfaces": surfacePayloads
            ]
            if let previewMode = primary["preview_mode"] {
                response["preview_mode"] = previewMode
            }
            if let displayMode = primary["display_mode"] {
                response["display_mode"] = displayMode
            }
            result = .ok(response)
        }
        return result
    }
}
