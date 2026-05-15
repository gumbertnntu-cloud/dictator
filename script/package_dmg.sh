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
2. Откройте Dictator.app.
3. В Settings нажмите Prepare Dictator.
4. Дождитесь, пока приложение само установит runtime и прогреет модель.
5. Разрешите Microphone и Accessibility.

Важно:
- Эта beta-сборка проверена на Apple Silicon.
- Intel Mac пока не подтвержден.
- Для первой подготовки нужны интернет и свободное место под Python runtime, зависимости и model cache.
- Приложение ad-hoc signed и пока не notarized. Если macOS блокирует запуск:
  откройте через Control-click -> Open.
- Распознавание локальное. Текст диктовки в логи не пишется.
README

/usr/bin/hdiutil create \
  -volname "$APP_NAME" \
  -srcfolder "$STAGING_DIR" \
  -ov \
  -format UDZO \
  "$DMG_PATH" >/dev/null

rm -rf "$STAGING_DIR"

echo "$DMG_PATH"
