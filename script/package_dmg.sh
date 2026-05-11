#!/usr/bin/env bash
set -euo pipefail

APP_NAME="Dictator"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_DIR="$ROOT_DIR/dist"
STAGING_DIR="$DIST_DIR/dmg-staging"
APP_BUNDLE="$DIST_DIR/$APP_NAME.app"
DMG_PATH="$DIST_DIR/$APP_NAME.dmg"

cd "$ROOT_DIR"

"$ROOT_DIR/script/package_app.sh" >/dev/null

rm -rf "$STAGING_DIR" "$DMG_PATH"
mkdir -p "$STAGING_DIR"

cp -R "$APP_BUNDLE" "$STAGING_DIR/"
ln -s /Applications "$STAGING_DIR/Applications"

cat >"$STAGING_DIR/README_FIRST.txt" <<'README'
Dictator beta для macOS

Как установить:
1. Перетащите Dictator.app в Applications.
2. Запустите Install GigaAM Runtime.command один раз.
3. Откройте Dictator.app.
4. В Settings нажмите Download, если модель еще не Ready.
5. Разрешите Microphone и Accessibility.

Важно:
- Эта beta-сборка проверена на Apple Silicon.
- Intel Mac пока не подтвержден.
- Приложение ad-hoc signed и пока не notarized. Если macOS блокирует запуск:
  откройте через Control-click -> Open.
- Распознавание локальное. Текст диктовки в логи не пишется.

Что ставит runtime installer:
- Homebrew-пакеты ffmpeg и uv, если Homebrew уже установлен.
- gigaam-mlx через uv tool.
- GigaAM v3 e2e RNNT model cache при первом прогреве.

Если Homebrew не установлен:
https://brew.sh
README

cat >"$STAGING_DIR/Install GigaAM Runtime.command" <<'INSTALLER'
#!/usr/bin/env zsh
set -euo pipefail

echo "Dictator GigaAM runtime installer"
echo ""

if [[ "$(uname -m)" != "arm64" ]]; then
  echo "This beta runtime installer is currently for Apple Silicon Macs only."
  echo "Intel Mac support is tracked separately."
  echo ""
  read -r "?Press Enter to close..."
  exit 1
fi

if ! command -v brew >/dev/null 2>&1; then
  echo "Homebrew is required for this beta installer."
  echo "Install it from https://brew.sh, then run this installer again."
  echo ""
  read -r "?Press Enter to close..."
  exit 1
fi

echo "Installing ffmpeg and uv if needed..."
brew list ffmpeg >/dev/null 2>&1 || brew install ffmpeg
brew list uv >/dev/null 2>&1 || brew install uv

echo ""
echo "Installing GigaAM MLX runtime..."
uv tool install git+https://github.com/aystream/gigaam-mlx.git --force

export PATH="$HOME/.local/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"

echo ""
echo "Prewarming GigaAM model. This can take several minutes on first run."
work_dir="$(mktemp -d /tmp/dictator-gigaam-prewarm.XXXXXX)"
trap 'rm -rf "$work_dir"' EXIT
ffmpeg -hide_banner -loglevel error -f lavfi -i anullsrc=r=16000:cl=mono -t 0.4 -c:a pcm_s16le "$work_dir/warmup.wav"
gigaam-mlx "$work_dir/warmup.wav" --model-type rnnt --format txt --quiet --output-dir "$work_dir" || true

echo ""
echo "Done. Open Dictator.app and grant Microphone + Accessibility permissions."
echo ""
read -r "?Press Enter to close..."
INSTALLER
chmod +x "$STAGING_DIR/Install GigaAM Runtime.command"

/usr/bin/hdiutil create \
  -volname "$APP_NAME" \
  -srcfolder "$STAGING_DIR" \
  -ov \
  -format UDZO \
  "$DMG_PATH" >/dev/null

rm -rf "$STAGING_DIR"

echo "$DMG_PATH"
