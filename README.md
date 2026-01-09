# Workout Timer (Flutter)

A modern workout interval timer built with Flutter/Dart. Supports WORK/REST intervals across multiple sets, an optional 3-second prep countdown, audio cues, progress visuals, and persistent settings.

## Download (Android)
- Download the latest APK from the **GitHub Releases** section and install it on your Android device.

> If Android blocks installation, enable **Install unknown apps** for your browser/files app.

## Features
- WORK / REST interval timer with set tracking
- Optional fixed **3-second PREP** countdown before each WORK phase (toggle)
- Audio cues:
  - Set start (WORK begins)
  - Rest start (WORK → REST)
  - Done sound when workout completes
  - Countdown beep for 3-2-1 (when PREP enabled)
- Scroll pickers:
  - Work seconds (1–300)
  - Rest seconds (1–300)
  - Sets constrained so total session ≤ 3 hours
- Settings lock while active (prevents changing config mid-workout)
- Settings persistence using SharedPreferences
- Clean UI with circular progress + phase styling


