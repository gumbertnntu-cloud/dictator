# Dictator

Dictator is a small macOS menu bar utility for local Whisper-based dictation.

## Current v1 status

- macOS 13+ SwiftUI menu bar app.
- Settings window for language, model, hotkey, and press mode.
- Hold-to-talk and toggle dictation modes.
- Microphone capture through `AVAudioEngine`.
- Floating status bubble for listening, transcribing, success, fallback, and error.
- Best-effort Accessibility insertion into the focused text field.
- Fallback bubble with `Copy` when direct insertion is unavailable.
- No dictation history and no transcript logging.

## Run locally

```bash
./script/build_and_run.sh
```

## Package one file for sharing

```bash
./script/package_app.sh
```

The distributable archive is written to:

```text
dist/Dictator.zip
```

## Known limitations

- The packaged app currently builds for the local architecture. On the current machine that is Apple Silicon (`arm64`).
- Universal Intel + Apple Silicon packaging still needs a working Xcode `xcbuild` setup or a separate Intel build machine.
- `ModelDownloadService` currently tracks model readiness for the UI. Actual Whisper model resolution is delegated to the installed local `whisper` CLI.
- The app is ad-hoc signed for local testing, not notarized for public distribution.
