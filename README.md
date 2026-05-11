# Dictator

Dictator is a small macOS menu bar utility for local GigaAM-based dictation.

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

## GigaAM runtime for local testing

The app does not bundle the ASR runtime yet. Install one supported backend first, then press `Download` in Settings:

```bash
uv tool install git+https://github.com/aystream/gigaam-mlx.git
```

This is the fastest current path for Apple Silicon. Intel packaging still needs a separate backend validation.

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
- The selected ASR model is `GigaAM v3 e2e RNNT`.
- Runtime detection currently supports installed `gigaam-mlx`, `gigastt`, or the official Python `gigaam` package.
- The Download button runs a real model/runtime prewarm and only then marks the model as ready.
- The app is ad-hoc signed for local testing, not notarized for public distribution.
