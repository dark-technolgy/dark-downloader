# Dark Downloader

Cross-platform media downloader built with Flutter + Rust.

## Downloads

Users don't build the app themselves — they grab the latest release from the
website. Each release ships:

| Platform | File                                              | How to run                       |
| -------- | ------------------------------------------------- | -------------------------------- |
| Windows  | `Dark-Downloader-Setup-vX.Y.Z.exe`                | Double-click to install (no certificate, no admin required, creates Desktop + Start Menu shortcuts automatically) |
| Android  | `Dark-Downloader-vX.Y.Z-android-universal.apk`    | Install like a normal APK        |
| Linux    | `Dark-Downloader-vX.Y.Z-linux-x64.tar.gz`         | Extract, run `dark_downloader`   |

The Windows build uses an **Inno Setup installer** (not MSIX), so users never
see the
`This app package's publisher certificate could not be verified (0x800B010A)`
error.

## Local development

```powershell
flutter pub get
flutter run          # dev on the currently connected device
```

## Release builds

Prebuilt FFmpeg binaries are fetched into `bundled_ffmpeg/` on first build.

### Windows — installer (recommended, no cert)

```powershell
pwsh scripts/build_installer.ps1
```

Output: `build\windows\x64\runner\Release\Dark-Downloader-Setup-v<version>.exe`

Requires Inno Setup 6 (`ISCC.exe`). If it's not on your PATH the script tries
to install it silently via `winget install JRSoftware.InnoSetup`.

### Android

```powershell
flutter build apk --release
# or split per ABI (smaller downloads):
flutter build apk --release --split-per-abi
```

### Linux

Run on a Linux host:

```bash
bash scripts/build_release_for_website.sh
```

### All platforms in CI

`.github/workflows/main_build.yml` builds Android, Windows (`Setup.exe`), and
Linux on every `v*.*.*` tag push and publishes to Cloudflare R2.

## Project layout

```
android/          Android Gradle project
windows/          Windows CMake runner
linux/            Linux CMake runner
lib/              Flutter/Dart source
rust/             Rust library (downloader, video processor, extractors)
rust_builder/     flutter_rust_bridge glue
assets/           Bundled assets (branding, ffmpeg configs)
bundled_ffmpeg/   Native FFmpeg binaries (fetched, gitignored)
cloudflare_bridge/ Cloudflare Pages/DNS automation scripts
supabase/         Supabase Edge Functions + migrations
scripts/          Build, packaging, and setup scripts
```
