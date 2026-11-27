#!/usr/bin/env bash
# Build UDesk.app for macOS and pack it into UDesk-<version>-<arch>.dmg.
#
#   docs/udesk/build-mac.sh [arm64|x86_64]        (default: the host architecture)
#
# Run from anywhere; needs the tools listed in docs/UDESK-MAC.md on PATH, VCPKG_ROOT set and the
# bridge files generated. Environment:
#   UDESK_SECRETS         path of udesk-secrets.json (default ~/udesk-secrets.json). Without the
#                         file the build still works but Google sign-in fails.
#   UDESK_SIGN_IDENTITY   "Developer ID Application: ..." to sign with. Default "-" (ad-hoc).
#   UDESK_NOTARY_PROFILE  notarytool keychain profile. When set with a real identity the dmg is
#                         notarized and stapled.
set -euo pipefail

cd "$(dirname "$0")/../.."
arch="${1:-$(uname -m)}"
secrets="${UDESK_SECRETS:-$HOME/udesk-secrets.json}"
identity="${UDESK_SIGN_IDENTITY:--}"
version="$(sed -n 's/^const String kUDeskVersion = "\(.*\)";$/\1/p' flutter/lib/consts.dart)"
[[ -n "$version" ]] || { echo "kUDeskVersion not found in flutter/lib/consts.dart" >&2; exit 1; }

case "$arch" in
  arm64)
    target=aarch64-apple-darwin
    # ScreenCaptureKit needs macOS 12.3, same as the upstream arm64 job.
    min_macos=12.3
    features=hwcodec,flutter,unix-file-copy-paste,screencapturekit
    ;;
  x86_64)
    target=x86_64-apple-darwin
    min_macos=10.14
    features=hwcodec,flutter,unix-file-copy-paste
    ;;
  *) echo "unknown arch: $arch" >&2; exit 1 ;;
esac

grep -q 'ffi.Bool' flutter/lib/generated_bridge.dart || {
  echo "flutter/lib/generated_bridge.dart is missing or wrong, run flutter_rust_bridge_codegen first" >&2
  exit 1
}

MACOSX_DEPLOYMENT_TARGET=$min_macos cargo build --locked --target "$target" \
  --features "$features" --release
# The Xcode project links ../../target/release/liblibrustdesk.dylib.
mkdir -p target/release
cp "target/$target/release/liblibrustdesk.dylib" target/release/liblibrustdesk.dylib

define=()
if [[ -f "$secrets" ]]; then
  define=(--dart-define-from-file="$secrets")
else
  echo "WARNING: $secrets not found, Google sign-in will not work in this build" >&2
fi
# macOS refuses to let Xcode rewrite a bundle that was already signed and notarized.
rm -rf flutter/build/macos/Build/Products/Release/UDesk.app
(
  cd flutter
  FLUTTER_XCODE_ARCHS=$arch FLUTTER_XCODE_ONLY_ACTIVE_ARCH=YES \
    FLUTTER_XCODE_MACOSX_DEPLOYMENT_TARGET=$min_macos \
    flutter build macos --release ${define[@]+"${define[@]}"}
)

app=flutter/build/macos/Build/Products/Release/UDesk.app
cp -f "target/$target/release/service" "$app/Contents/MacOS/"
for f in MacOS/UDesk MacOS/service Frameworks/liblibrustdesk.dylib; do
  lipo "$app/Contents/$f" -verify_arch "$arch"
done

bash .github/scripts/sign-macos-app.sh "$app" "$identity" flutter/macos/Runner/Release.entitlements

dmg="UDesk-$version-$arch.dmg"
rm -f "$dmg"
dmg_args=(--volname "UDesk $version" --icon "UDesk.app" 200 190 --hide-extension "UDesk.app"
  --window-size 800 400 --app-drop-link 600 185 "$dmg" "$app")
# The window layout is set by scripting Finder, which needs the Automation permission. Without
# it the dmg is still made, with the default layout.
if ! create-dmg "${dmg_args[@]}"; then
  rm -f rw.*."$dmg" "$dmg"
  create-dmg --skip-jenkins "${dmg_args[@]}"
fi

if [[ "$identity" != "-" ]]; then
  codesign --force --timestamp -s "$identity" "$dmg"
  if [[ -n "${UDESK_NOTARY_PROFILE:-}" ]]; then
    xcrun notarytool submit "$dmg" --keychain-profile "$UDESK_NOTARY_PROFILE" --wait
    xcrun stapler staple "$dmg"
  else
    echo "WARNING: UDESK_NOTARY_PROFILE not set, $dmg is signed but not notarized" >&2
  fi
fi

echo "$dmg  sha256=$(shasum -a 256 "$dmg" | cut -d' ' -f1)  size=$(stat -f%z "$dmg")"
