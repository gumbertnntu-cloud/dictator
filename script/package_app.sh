#!/usr/bin/env bash
set -euo pipefail

APP_NAME="Dictator"
BUNDLE_ID="app.dictator.local"
MIN_SYSTEM_VERSION="13.0"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_DIR="$ROOT_DIR/dist"
APP_BUNDLE="$DIST_DIR/$APP_NAME.app"
APP_CONTENTS="$APP_BUNDLE/Contents"
APP_MACOS="$APP_CONTENTS/MacOS"
APP_RESOURCES="$APP_CONTENTS/Resources"
APP_BINARY="$APP_MACOS/$APP_NAME"
INFO_PLIST="$APP_CONTENTS/Info.plist"
ZIP_PATH="$DIST_DIR/$APP_NAME.zip"
ICON_SOURCE="$ROOT_DIR/assets/AppIcon.icns"
ICON_DEST="$APP_RESOURCES/AppIcon.icns"

cd "$ROOT_DIR"

swift build -c release
BUILD_BINARY="$(swift build -c release --show-bin-path)/$APP_NAME"

rm -rf "$APP_BUNDLE" "$ZIP_PATH"
mkdir -p "$APP_MACOS"
mkdir -p "$APP_RESOURCES"
cp "$BUILD_BINARY" "$APP_BINARY"
chmod +x "$APP_BINARY"

if [[ ! -f "$ICON_SOURCE" ]]; then
  "$ROOT_DIR/script/make_icon.sh" >/dev/null
fi
cp "$ICON_SOURCE" "$ICON_DEST"

cat >"$INFO_PLIST" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key>
  <string>$APP_NAME</string>
  <key>CFBundleIconFile</key>
  <string>AppIcon</string>
  <key>CFBundleIdentifier</key>
  <string>$BUNDLE_ID</string>
  <key>CFBundleName</key>
  <string>$APP_NAME</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>LSMinimumSystemVersion</key>
  <string>$MIN_SYSTEM_VERSION</string>
  <key>LSUIElement</key>
  <true/>
  <key>NSHighResolutionCapable</key>
  <true/>
  <key>NSMicrophoneUsageDescription</key>
  <string>Dictator records audio only while you start dictation.</string>
  <key>NSPrincipalClass</key>
  <string>NSApplication</string>
</dict>
</plist>
PLIST

copy_bundled_payload() {
  [[ -n "${DICTATOR_BUNDLED_RUNTIME_DIR:-}" ]] || return 0
  [[ -n "${DICTATOR_BUNDLED_MODEL_DIR:-}" ]] || {
    echo "DICTATOR_BUNDLED_MODEL_DIR is required when DICTATOR_BUNDLED_RUNTIME_DIR is set." >&2
    exit 1
  }

  local payload_root="$APP_RESOURCES/GigaAMPayload"
  local runtime_dest="$payload_root/runtime"
  local model_dest="$payload_root/hf-home"

  rm -rf "$payload_root"
  mkdir -p "$payload_root"
  cp -R "$DICTATOR_BUNDLED_RUNTIME_DIR" "$runtime_dest"
  cp -R "$DICTATOR_BUNDLED_MODEL_DIR" "$model_dest"

  local runtime_source="${DICTATOR_BUNDLED_RUNTIME_SOURCE:-local bundle input}"
  local runtime_version="${DICTATOR_BUNDLED_RUNTIME_VERSION:-unknown}"
  local runtime_license="${DICTATOR_BUNDLED_RUNTIME_LICENSE:-UNSPECIFIED}"
  local model_source="${DICTATOR_BUNDLED_MODEL_SOURCE:-local bundle input}"
  local model_version="${DICTATOR_BUNDLED_MODEL_VERSION:-unknown}"
  local model_license="${DICTATOR_BUNDLED_MODEL_LICENSE:-UNSPECIFIED}"

  python3 - <<'PY' "$payload_root" "$runtime_dest" "$model_dest" "$runtime_version" "$runtime_source" "$runtime_license" "$model_version" "$model_source" "$model_license"
import hashlib
import json
import os
import sys

payload_root, runtime_dir, model_dir, runtime_version, runtime_source, runtime_license, model_version, model_source, model_license = sys.argv[1:]

def fingerprint(path: str) -> str:
    hasher = hashlib.sha256()
    for current_root, dirnames, filenames in os.walk(path):
        dirnames[:] = sorted(d for d in dirnames if not d.startswith("."))
        filenames = sorted(f for f in filenames if not f.startswith("."))
        rel_root = os.path.relpath(current_root, path)
        rel_root = "" if rel_root == "." else rel_root
        hasher.update(rel_root.encode("utf-8"))
        hasher.update(b"/")
        for name in filenames:
            rel_path = os.path.join(rel_root, name) if rel_root else name
            hasher.update(rel_path.encode("utf-8"))
            with open(os.path.join(current_root, name), "rb") as fh:
                while True:
                    chunk = fh.read(1024 * 1024)
                    if not chunk:
                        break
                    hasher.update(chunk)
    return hasher.hexdigest()

def size_bytes(path: str) -> int:
    total = 0
    for current_root, _, filenames in os.walk(path):
        for name in filenames:
            if name.startswith("."):
                continue
            total += os.path.getsize(os.path.join(current_root, name))
    return total

manifest = {
    "schemaVersion": 1,
    "runtime": {
        "relativePath": "runtime",
        "version": runtime_version,
        "source": runtime_source,
        "license": runtime_license,
        "bytes": size_bytes(runtime_dir),
        "fingerprint": fingerprint(runtime_dir),
    },
    "model": {
        "relativePath": "hf-home",
        "version": model_version,
        "source": model_source,
        "license": model_license,
        "bytes": size_bytes(model_dir),
        "fingerprint": fingerprint(model_dir),
    },
}

with open(os.path.join(payload_root, "manifest.json"), "w", encoding="utf-8") as fh:
    json.dump(manifest, fh, indent=2, ensure_ascii=True)
    fh.write("\n")
PY
}

copy_bundled_payload

/usr/bin/codesign --force --deep --sign - "$APP_BUNDLE"
/usr/bin/ditto -c -k --keepParent "$APP_BUNDLE" "$ZIP_PATH"

echo "$ZIP_PATH"
