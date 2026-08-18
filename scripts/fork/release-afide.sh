#!/usr/bin/env bash
set -euo pipefail

# Build, sign, notarize, and publish "cmux AFIDE" — this fork, released as its own app.
#
# Derived from scripts/build-sign-upload.sh. Kept separate rather than parameterising the
# original because that script tracks upstream and every fork-specific value here (bundle id,
# team id, cask token, zap paths) would become a merge conflict in a file we do not own.
# When upstream changes its release steps, this file has to be updated by hand — that is the
# cost of not touching theirs.
#
# Usage: ./scripts/fork/release-afide.sh <tag> [--allow-overwrite]
# Requires: source ~/.secrets/cmux-afide.env

APP_DISPLAY_NAME="cmux AFIDE"
BUNDLE_ID="com.cmuxterm.app.afide"
CASK_TOKEN="cmux-afide"
DMG_NAME="cmux-afide-macos.dmg"
GITHUB_REPO="takashi11171117/cmux"
TAP_DIR="${CMUX_AFIDE_TAP_DIR:-homebrew-cmux-afide}"
ENTITLEMENTS_TEMPLATE="scripts/fork/afide.entitlements.tmpl"
GHOSTTYKIT_CRASH_REPORT_SUBDIR="cmux-afide/crash"

usage() {
  cat <<'EOF'
Usage: ./scripts/fork/release-afide.sh <tag> [--allow-overwrite]

Options:
  --allow-overwrite   Permit replacing existing release assets for the same tag.

Environment (from ~/.secrets/cmux-afide.env):
  APPLE_ID                      Apple ID used for notarisation
  APPLE_TEAM_ID                 Team ID of the Developer ID certificate
  APPLE_APP_SPECIFIC_PASSWORD   App-specific password for notarytool
  AFIDE_SIGN_HASH               SHA-1 of the "Developer ID Application" identity
  SPARKLE_PRIVATE_KEY           Sparkle EdDSA private key (from sparkle_generate_keys.sh)
EOF
}

ALLOW_OVERWRITE="false"
POSITIONAL=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    --allow-overwrite) ALLOW_OVERWRITE="true"; shift ;;
    -h|--help) usage; exit 0 ;;
    -*) echo "Unknown option: $1" >&2; usage >&2; exit 1 ;;
    *) POSITIONAL+=("$1"); shift ;;
  esac
done
set -- "${POSITIONAL[@]:-}"

if [[ $# -ne 1 || -z "${1:-}" ]]; then
  usage >&2
  exit 1
fi
TAG="$1"
VERSION="${TAG#v}"
if [[ ! "$VERSION" =~ ^[0-9]+(\.[0-9]+)*$ ]]; then
  echo "ERROR: tag must look like v1.2.3 (got: $TAG)" >&2
  exit 1
fi

# --- Pre-flight ---
SECRETS_FILE="$HOME/.secrets/cmux-afide.env"
if [[ ! -f "$SECRETS_FILE" ]]; then
  echo "MISSING: $SECRETS_FILE" >&2
  echo "Create it with APPLE_ID, APPLE_TEAM_ID, APPLE_APP_SPECIFIC_PASSWORD," >&2
  echo "AFIDE_SIGN_HASH and SPARKLE_PRIVATE_KEY, then chmod 600 it." >&2
  exit 1
fi
# The Sparkle key generator rewrites this file and resets it to 0644, so re-assert 0600
# rather than trusting whatever the last tool to touch it left behind. It holds the private
# key that signs every update; world-readable is not acceptable.
SECRETS_MODE="$(stat -f "%Lp" "$SECRETS_FILE")"
if [[ "$SECRETS_MODE" != "600" ]]; then
  echo "Tightening $SECRETS_FILE from $SECRETS_MODE to 600"
  chmod 600 "$SECRETS_FILE"
fi

# shellcheck source=/dev/null
source "$SECRETS_FILE"
export SPARKLE_PRIVATE_KEY

for var in APPLE_ID APPLE_TEAM_ID APPLE_APP_SPECIFIC_PASSWORD AFIDE_SIGN_HASH SPARKLE_PRIVATE_KEY; do
  if [[ -z "${!var:-}" ]]; then
    echo "MISSING: \$$var (set it in $SECRETS_FILE)" >&2
    exit 1
  fi
done

# rustup installs into ~/.cargo/bin, which a non-login shell does not have on PATH. The
# Nucleo FFI build phase treats a missing cargo as optional and skips, but signing then fails
# on the absent dylib — 20 minutes into the run, after the whole Release build.
export PATH="$HOME/.cargo/bin:$PATH"

for tool in zig xcodebuild create-dmg xcrun codesign ditto gh cargo; do
  command -v "$tool" >/dev/null || { echo "MISSING: $tool" >&2; exit 1; }
done

# Both slices are required: the app is built universal, so a missing target aborts the FFI
# build for that architecture only, which again surfaces as a missing dylib at signing time.
for rust_target in aarch64-apple-darwin x86_64-apple-darwin; do
  if ! rustc --print target-libdir --target "$rust_target" >/dev/null 2>&1; then
    echo "MISSING: Rust target $rust_target (run: rustup target add $rust_target)" >&2
    exit 1
  fi
done

# The identity must be a Developer ID Application certificate. Apple Development certificates
# are accepted by codesign but rejected by notarytool, which would only surface minutes into
# the run, after a full Release build.
if ! security find-identity -v -p codesigning | grep -q "$AFIDE_SIGN_HASH"; then
  echo "MISSING: no codesigning identity with hash $AFIDE_SIGN_HASH in the keychain" >&2
  exit 1
fi
IDENTITY_NAME="$(security find-identity -v -p codesigning | grep "$AFIDE_SIGN_HASH" | sed 's/.*"\(.*\)"/\1/')"
if [[ "$IDENTITY_NAME" != "Developer ID Application:"* ]]; then
  echo "ERROR: \$AFIDE_SIGN_HASH points at \"$IDENTITY_NAME\"." >&2
  echo "Notarisation requires a \"Developer ID Application\" certificate. Create one at" >&2
  echo "https://developer.apple.com/account/resources/certificates (Account Holder only)." >&2
  exit 1
fi
echo "Pre-flight checks passed (signing as $IDENTITY_NAME)"

BUILT_APP_PATH="build/Build/Products/Release/cmux.app"
APP_PATH="build/Build/Products/Release/${APP_DISPLAY_NAME}.app"
APPCAST_URL="https://github.com/${GITHUB_REPO}/releases/latest/download/appcast.xml"

# --- Entitlements (team id is only known at release time) ---
ENTITLEMENTS="$(mktemp -t afide-entitlements).plist"
trap 'rm -f "$ENTITLEMENTS"' EXIT
sed -e "s/__TEAM_ID__/${APPLE_TEAM_ID}/" -e "s/__BUNDLE_ID__/${BUNDLE_ID}/" \
  "$ENTITLEMENTS_TEMPLATE" > "$ENTITLEMENTS"

# No `keychain-access-groups`, and so no embedded.provisionprofile to back it. Upstream ships
# a profile from a CI secret; without one, that entitlement makes launchd refuse to start the
# app entirely — "Launch failed", errno 163, with a valid signature and passing notarisation.
# The fork does not share a keychain group, so the entitlement buys nothing.
if grep -q "keychain-access-groups" "$ENTITLEMENTS"; then
  echo "ERROR: keychain-access-groups requires an embedded provisioning profile" >&2
  exit 1
fi
echo "Entitlements prepared for team $APPLE_TEAM_ID"

# --- Build GhosttyKit ---
# CMUX_AFIDE_SKIP_BUILD=1 reuses whatever is already in build/. Only for iterating on the
# signing and publishing half: a full Release build is ~30 minutes, and re-running it to test
# a one-line change in a later step wastes most of an hour.
if [[ "${CMUX_AFIDE_SKIP_BUILD:-0}" == "1" ]]; then
  echo "Reusing existing build (CMUX_AFIDE_SKIP_BUILD=1)"
else
# GhosttyKit is a ReleaseFast zig build of a submodule that changes far less often than this
# fork's own sources — it took 29 of the 35 minutes of the last full release, to produce a
# byte-identical framework. Rebuild it only when the submodule commit differs from the one
# the existing framework was built at, or when asked.
GHOSTTYKIT_STAMP=".ghosttykit-release-stamp"
GHOSTTY_COMMIT="$(git -C ghostty rev-parse HEAD 2>/dev/null || echo unknown)"
if [[ "${CMUX_AFIDE_FORCE_GHOSTTYKIT:-0}" != "1" ]] \
  && [[ -d GhosttyKit.xcframework ]] \
  && [[ "$(cat "$GHOSTTYKIT_STAMP" 2>/dev/null)" == "$GHOSTTY_COMMIT" ]]; then
  echo "Reusing GhosttyKit (ghostty at ${GHOSTTY_COMMIT:0:12})"
else
  echo "Building GhosttyKit..."
  rm -rf GhosttyKit.xcframework ghostty/macos/GhosttyKit.xcframework
  (
    cd ghostty
    zig build -Dcrash-report-subdir="$GHOSTTYKIT_CRASH_REPORT_SUBDIR" -Dsentry=false \
      -Demit-xcframework=true -Demit-macos-app=false -Dxcframework-target=universal -Doptimize=ReleaseFast
  )
  cp -R ghostty/macos/GhosttyKit.xcframework GhosttyKit.xcframework
  printf '%s' "$GHOSTTY_COMMIT" > "$GHOSTTYKIT_STAMP"
fi

# --- Build app (Release, unsigned) ---
#
# PRODUCT_NAME is deliberately NOT passed here. On the command line it applies to every
# target, so the resource bundles and swiftmodules get renamed too and the build fails with
# "Multiple commands produce .../cmux AFIDE.bundle". The app is renamed after the build
# instead, the same way scripts/reload.sh does it.
# Not wiping build/: xcodebuild's own dependency tracking is what makes a source-only change
# cost minutes instead of half an hour. Pass CMUX_AFIDE_CLEAN_BUILD=1 when a clean room
# actually matters — a toolchain change, or a suspected stale-artifact problem.
echo "Building $APP_DISPLAY_NAME..."
if [[ "${CMUX_AFIDE_CLEAN_BUILD:-0}" == "1" ]]; then
  echo "  clean build (CMUX_AFIDE_CLEAN_BUILD=1)"
  rm -rf build/
fi
xcodebuild -scheme cmux -configuration Release -derivedDataPath build \
  CODE_SIGNING_ALLOWED=NO \
  PRODUCT_BUNDLE_IDENTIFIER="$BUNDLE_ID" \
  CMUX_SIDEBAR_EXTENSION_POINT_ID="${BUNDLE_ID}.cmux.sidebar" \
  INFOPLIST_KEY_CFBundleName="$APP_DISPLAY_NAME" \
  build 2>&1 | tail -5

if [[ ! -d "$BUILT_APP_PATH" ]]; then
  echo "ERROR: expected app at $BUILT_APP_PATH" >&2
  exit 1
fi

fi

# --- Rename the bundle and stamp its identity ---
#
# Outside the build branch on purpose: with CMUX_AFIDE_SKIP_BUILD=1 the identity still has to
# be stamped, or a resumed release ships whatever the previous run left behind — which is how
# a build carrying upstream's version number got published.
if [[ ! -d "$BUILT_APP_PATH" ]]; then
  echo "ERROR: no build at $BUILT_APP_PATH (run without CMUX_AFIDE_SKIP_BUILD first)" >&2
  exit 1
fi
rm -rf "$APP_PATH"
cp -R "$BUILT_APP_PATH" "$APP_PATH"
APP_PLIST_EARLY="$APP_PATH/Contents/Info.plist"
# Version comes from the tag. Without this the bundle keeps upstream cmux's version, every
# release claims the same one, and Sparkle never sees an update: the appcast advertises a
# version the installed app already reports, so it stays silent forever.
for pair in "CFBundleName:$APP_DISPLAY_NAME" "CFBundleDisplayName:$APP_DISPLAY_NAME" "CFBundleIdentifier:$BUNDLE_ID" "CFBundleShortVersionString:$VERSION" "CFBundleVersion:$VERSION"; do
  key="${pair%%:*}"
  value="${pair#*:}"
  /usr/libexec/PlistBuddy -c "Set :$key $value" "$APP_PLIST_EARLY" 2>/dev/null \
    || /usr/libexec/PlistBuddy -c "Add :$key string $value" "$APP_PLIST_EARLY"
done
STAMPED_VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$APP_PLIST_EARLY")
if [[ "$STAMPED_VERSION" != "$VERSION" ]]; then
  echo "ERROR: bundle reports $STAMPED_VERSION, expected $VERSION" >&2
  exit 1
fi
echo "Stamped $APP_DISPLAY_NAME ($BUNDLE_ID, $VERSION)"

HELPER_PATH="$APP_PATH/Contents/Resources/bin/ghostty"
if [[ ! -x "$HELPER_PATH" ]]; then
  echo "Ghostty theme picker helper not found at $HELPER_PATH" >&2
  exit 1
fi

# --- Inject Sparkle keys and this fork's feed ---
echo "Injecting Sparkle keys..."
SPARKLE_PUBLIC_KEY_DERIVED=$(swift scripts/derive_sparkle_public_key.swift "$SPARKLE_PRIVATE_KEY")
APP_PLIST="$APP_PATH/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Delete :SUPublicEDKey" "$APP_PLIST" 2>/dev/null || true
/usr/libexec/PlistBuddy -c "Delete :SUFeedURL" "$APP_PLIST" 2>/dev/null || true
/usr/libexec/PlistBuddy -c "Add :SUPublicEDKey string $SPARKLE_PUBLIC_KEY_DERIVED" "$APP_PLIST"
/usr/libexec/PlistBuddy -c "Add :SUFeedURL string $APPCAST_URL" "$APP_PLIST"
echo "Sparkle feed set to $APPCAST_URL"

./scripts/remove-sparkle-sandbox-xpc-services.sh "$APP_PATH"

# --- Codesign ---
echo "Codesigning..."
# This fork drops `com.apple.developer.web-browser.public-key-credential`, which cmux itself
# requires. It is an Apple-granted entitlement, and claiming one the account was never granted
# is worse than shipping without it; the fork does not use passkeys in its browser surface.
CMUX_SKIP_WEB_BROWSER_ENTITLEMENT_CHECK=1 \
  ./scripts/sign-cmux-bundle.sh "$APP_PATH" "$ENTITLEMENTS" "$AFIDE_SIGN_HASH"
echo "Codesign verified"

# Submits, then polls by submission id. `notarytool --wait` holds one long connection, and
# when Apple drops it the command exits non-zero even though the submission is queued and
# progressing — re-running then resubmits from scratch. Polling survives that: the id is
# printed before any waiting happens, so a dropped connection costs one poll, not a rerun.
notarize() {
  local path="$1"
  local submit_output submission_id status
  submit_output=$(xcrun notarytool submit "$path" \
    --apple-id "$APPLE_ID" --team-id "$APPLE_TEAM_ID" \
    --password "$APPLE_APP_SPECIFIC_PASSWORD" 2>&1) || true
  submission_id=$(printf '%s' "$submit_output" \
    | grep -oE '[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}' | head -1)
  if [[ -z "$submission_id" ]]; then
    echo "$submit_output" >&2
    echo "ERROR: notarization submit did not return a submission id" >&2
    return 1
  fi
  echo "  submission: $submission_id"

  # ~60 minutes. Apple normally answers within 15; a longer stall is a service problem, and
  # the id is reported so the wait can be resumed by hand rather than resubmitting.
  for _ in $(seq 1 120); do
    status=$(xcrun notarytool info "$submission_id" \
      --apple-id "$APPLE_ID" --team-id "$APPLE_TEAM_ID" \
      --password "$APPLE_APP_SPECIFIC_PASSWORD" 2>/dev/null \
      | grep 'status:' | sed 's/.*status: //')
    case "$status" in
      Accepted) echo "  accepted"; return 0 ;;
      Invalid|Rejected)
        echo "ERROR: notarization $status for $path" >&2
        xcrun notarytool log "$submission_id" \
          --apple-id "$APPLE_ID" --team-id "$APPLE_TEAM_ID" \
          --password "$APPLE_APP_SPECIFIC_PASSWORD" 2>/dev/null | head -40 >&2
        return 1 ;;
    esac
    sleep 30
  done

  echo "ERROR: notarization still pending after 60 minutes" >&2
  echo "Resume with: xcrun notarytool info $submission_id --apple-id ... --team-id ... --password ..." >&2
  return 1
}

# --- Notarize app ---
echo "Notarizing app..."
ditto -c -k --sequesterRsrc --keepParent "$APP_PATH" afide-notary.zip
notarize afide-notary.zip || exit 1
xcrun stapler staple "$APP_PATH"
xcrun stapler validate "$APP_PATH"
rm -f afide-notary.zip
echo "App notarized"

# --- Create and notarize DMG ---
echo "Creating DMG..."
./scripts/verify-app-bundle-licenses.sh "$APP_PATH"
rm -f "$DMG_NAME"
create-dmg --codesign "$AFIDE_SIGN_HASH" "$DMG_NAME" "$APP_PATH"
echo "Notarizing DMG..."
notarize "$DMG_NAME" || exit 1
xcrun stapler staple "$DMG_NAME"
xcrun stapler validate "$DMG_NAME"
echo "DMG notarized"

# --- Launch the signed app once ---
#
# Signing, notarisation and Gatekeeper all pass on a bundle that cannot start: a privileged
# entitlement without a provisioning profile to back it makes launchd refuse the spawn, and
# every verification command still reports success. v0.1.0 shipped that way. The only check
# that catches it is starting the thing.
echo "Launch check..."
LAUNCH_COPY="$(mktemp -d)/$(basename "$APP_PATH")"
cp -R "$APP_PATH" "$LAUNCH_COPY"
open "$LAUNCH_COPY"
launched=false
for _ in $(seq 1 15); do
  if pgrep -f "$LAUNCH_COPY" >/dev/null 2>&1; then launched=true; break; fi
  sleep 2
done
pkill -f "$LAUNCH_COPY" >/dev/null 2>&1 || true
rm -rf "$(dirname "$LAUNCH_COPY")"
if [[ "$launched" != "true" ]]; then
  echo "ERROR: the signed app did not launch; refusing to publish" >&2
  echo "Check entitlements: privileged ones need an embedded provisioning profile." >&2
  exit 1
fi
echo "  launched and exited cleanly"

# --- Generate Sparkle appcast ---
echo "Generating appcast..."
DOWNLOAD_URL_PREFIX="https://github.com/${GITHUB_REPO}/releases/download/${TAG}/" \
RELEASE_NOTES_URL="https://github.com/${GITHUB_REPO}/releases/tag/${TAG}" \
  ./scripts/sparkle_generate_appcast.sh "$DMG_NAME" "$TAG" appcast.xml

# An appcast advertising the version the installed app already reports is silently inert:
# Sparkle fetches it, compares, and offers nothing.
# generate_appcast writes these as elements, not attributes.
if ! grep -q "<sparkle:shortVersionString>$VERSION</sparkle:shortVersionString>" appcast.xml; then
  echo "ERROR: appcast does not advertise $VERSION" >&2
  grep -oE '<sparkle:(short)?[Vv]ersion[^>]*>[^<]*<' appcast.xml >&2 || true
  exit 1
fi
if ! grep -q "<sparkle:version>$VERSION</sparkle:version>" appcast.xml; then
  echo "ERROR: appcast sparkle:version is not $VERSION" >&2
  exit 1
fi
if ! grep -q "sparkle:edSignature" appcast.xml; then
  echo "ERROR: appcast is missing sparkle:edSignature" >&2
  exit 1
fi
echo "  appcast advertises $VERSION and is signed"

# --- Create GitHub release and upload ---
if gh release view "$TAG" --repo "$GITHUB_REPO" >/dev/null 2>&1; then
  EXISTING_ASSETS="$(gh release view "$TAG" --repo "$GITHUB_REPO" --json assets --jq '.assets[].name' || true)"
  HAS_CONFLICTING_ASSET="false"
  for asset in "$DMG_NAME" appcast.xml; do
    if printf '%s\n' "$EXISTING_ASSETS" | grep -Fxq "$asset"; then
      HAS_CONFLICTING_ASSET="true"
      break
    fi
  done

  if [[ "$HAS_CONFLICTING_ASSET" == "true" && "$ALLOW_OVERWRITE" != "true" ]]; then
    echo "ERROR: Refusing to overwrite signed release assets for existing tag $TAG." >&2
    echo "Use a new tag, or rerun with --allow-overwrite." >&2
    exit 1
  fi

  if [[ "$ALLOW_OVERWRITE" == "true" ]]; then
    gh release upload "$TAG" "$DMG_NAME" appcast.xml --repo "$GITHUB_REPO" --clobber
  else
    gh release upload "$TAG" "$DMG_NAME" appcast.xml --repo "$GITHUB_REPO"
  fi
else
  gh release create "$TAG" "$DMG_NAME" appcast.xml --repo "$GITHUB_REPO" \
    --title "$TAG" --notes "cmux AFIDE ${TAG}"
fi

gh release view "$TAG" --repo "$GITHUB_REPO"

# --- Update the tap ---
DMG_SHA256=$(shasum -a 256 "$DMG_NAME" | cut -d' ' -f1)
CASK_FILE="${TAP_DIR}/Casks/${CASK_TOKEN}.rb"

if [[ -d "$TAP_DIR" ]]; then
  mkdir -p "${TAP_DIR}/Casks"
  cat > "$CASK_FILE" <<CASKEOF
cask "${CASK_TOKEN}" do
  version "${VERSION}"
  sha256 "${DMG_SHA256}"

  url "https://github.com/${GITHUB_REPO}/releases/download/v#{version}/${DMG_NAME}"
  name "${APP_DISPLAY_NAME}"
  desc "Agent-first IDE fork of cmux, with a dedicated code-review column"
  homepage "https://github.com/${GITHUB_REPO}"

  livecheck do
    url :url
    strategy :github_latest
  end

  auto_updates true
  depends_on macos: ">= :ventura"

  app "${APP_DISPLAY_NAME}.app"
  binary "#{appdir}/${APP_DISPLAY_NAME}.app/Contents/Resources/bin/cmux", target: "cmux-afide"

  zap trash: [
    "~/Library/Application Support/${BUNDLE_ID}",
    "~/Library/Caches/${BUNDLE_ID}",
    "~/Library/HTTPStorages/${BUNDLE_ID}",
    "~/Library/Preferences/${BUNDLE_ID}.plist",
    "~/Library/WebKit/${BUNDLE_ID}",
  ]
end
CASKEOF
  (
    cd "$TAP_DIR"
    git add "Casks/${CASK_TOKEN}.rb"
    if git diff --staged --quiet; then
      echo "Tap already up to date"
    else
      git commit -m "Update ${CASK_TOKEN} to ${VERSION}"
      git push
      echo "Tap updated to ${VERSION}"
    fi
  )
else
  echo "NOTE: $TAP_DIR not found — skipping tap update."
  echo "Clone it next to this repo to have releases update the cask automatically:"
  echo "  git clone https://github.com/${GITHUB_REPO%%/*}/homebrew-cmux-afide $TAP_DIR"
fi

echo
echo "Released ${APP_DISPLAY_NAME} ${TAG}"
echo "  brew install --cask ${GITHUB_REPO%%/*}/${CASK_TOKEN}/${CASK_TOKEN}"
