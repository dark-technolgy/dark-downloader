# Dark Downloader 🚀

A cross-platform, high-performance media downloader built with **Flutter** and **Rust**. 

**Dark Downloader** is designed to be 100% free forever. No accounts, no subscriptions, no ads, and no telemetry. It unlocks the ability to download videos, audio, MP3s (with embedded artwork), playlists, and more from all supported platforms out of the box.

---

## ✨ Features

- **Layered Cascade Extraction:** A native Rust engine tries to extract media first. If a platform modifies its player, a bundled `yt-dlp` binary transparently takes over. This ensures downloads rarely break.
- **High-Quality Audio Pipeline:** MP3s are generated using **libmp3lame at VBR quality 0** (highest). Files feature proper Xing/LAME headers for seek accuracy, `id3v2 v3` tags (title, artist, album, source URL), and **embedded front-cover artwork** directly from the video thumbnail.
- **Cross-Platform:** Available on Android, Windows, and Linux.
- **Batch Downloading:** Download entire playlists with a single tap.
- **Smart Paste:** Automatically detects copied URLs and suggests downloading them.

---

## 🛠 Prerequisites & Requirements

To build and run this project locally, ensure you have the following installed:

1. **Flutter SDK** (Channel Stable, >= 3.20.0)
2. **Rust Toolchain** (Latest stable version via rustup)
3. **CMake & Ninja** (For Windows / Linux desktop builds)
4. **Android Studio / Visual Studio** (For mobile/desktop C++ compilation)
5. **Supabase CLI** (Optional: only needed if you are deploying the backend edge functions)

---

## 🚀 How to Run Locally

1. **Clone the repository:**
   ```bash
   git clone https://github.com/your-repo/dark-downloader.git
   cd dark-downloader
   ```

2. **Install Flutter Dependencies:**
   ```bash
   flutter pub get
   ```

3. **Run the App:**
   Make sure you have a connected device or an emulator running.
   ```bash
   flutter run
   ```

---

## 🏗 Architecture & Project Structure

This repository uses a modular architecture combining Flutter for the UI and Rust for the heavy lifting (parsing, downloading, processing).

```text
dark-downloader/
├── lib/               # Flutter & Dart source code (UI, Providers, Logic)
├── rust/              # Rust core engine (Downloader, Video Processor, Extractors)
├── rust_builder/      # flutter_rust_bridge glue code & bindings
├── android/           # Android specific build files
├── windows/           # Windows specific build files (CMake)
├── linux/             # Linux specific build files (CMake)
├── assets/            # Bundled assets (branding, ffmpeg configs, default rules)
├── supabase/          # Supabase Edge Functions & Database migrations
└── scripts/           # Build, packaging, and CI/CD automation scripts
```

### The Rust Bridge
The app utilizes `flutter_rust_bridge` to achieve native performance. Complex tasks such as video processing, encryption, and extraction algorithms are written in Rust and securely executed on a separate thread, keeping the Flutter UI running at a buttery smooth 60/120 FPS.

---

## 📦 Release Builds & CI/CD

We use GitHub Actions (`.github/workflows/main_build.yml`) to automatically build and package releases for Android, Windows, and Linux on every tag push (`v*.*.*`).

### Build for Windows (Installer)
Requires Inno Setup 6. Run the powershell script:
```powershell
pwsh scripts/build_installer.ps1
```
Output: `build\windows\x64\runner\Release\Dark-Downloader-Setup-v<version>.exe`

### Build for Android
```bash
flutter build apk --release
# Or for optimized smaller APKs per architecture:
flutter build apk --release --split-per-abi
```

### Build for Linux
```bash
bash scripts/build_release_for_website.sh
```

---

## 🔐 Security & Privacy
Dark Downloader respects your privacy.
- Passwords and files placed in the **Vault** are encrypted using **AES-256-GCM**.
- API calls to the backend do not expose personally identifiable information.

## 📄 License
This project is open-source and free to use. All third-party libraries (FFmpeg, yt-dlp) retain their original licenses.
