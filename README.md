# YouTube Clipper

A small native SwiftUI app for macOS. Paste a YouTube link, optionally choose a start and end time, and create an MP4 clip. Copy the **video file** to the clipboard for pasting into other apps, or reveal it in Finder.

## Install

Requires macOS 14 or newer, Apple's Command Line Tools (`xcode-select --install`), and `yt-dlp`, `ffmpeg`, and `ffprobe` on your Mac. FFprobe is included with FFmpeg.

With Homebrew:

```sh
brew install yt-dlp ffmpeg
git clone https://github.com/nagy135/yt-clipper-gui.git
cd yt-clipper-gui
./install.sh
open '/Applications/YouTube Clipper.app'
```

The installer builds a release bundle with its icon, ad-hoc signs it locally, and copies it to `/Applications/YouTube Clipper.app`. Quit the app before reinstalling. You can supply another destination, for example `./install.sh "$HOME/Applications"`, if `/Applications` is not writable.

Tools installed through Homebrew, Nix, `~/.local/bin`, or the inherited `PATH` are detected automatically, including when opening from Finder. The app does not install or update dependencies itself.

## Use

1. Paste a YouTube link (watch, short link, and Shorts URLs work).
2. Leave **From** blank to start at the beginning. Leave **To** blank to continue to the end. Both may be blank to keep the full video.
3. Enter times as seconds, `MM:SS`, or `HH:MM:SS`; fractional seconds are supported.
4. Click **Create clip** (⌘Return).
5. Choose **Copy to clipboard** or **Show in Finder** when it finishes.

Clips stay in `~/Downloads/YouTube Clips` with unique names. Copy uses a macOS file URL, so compatible apps receive the actual file rather than a path string. Destination apps determine whether they accept pasted videos.

Like the original `yt-clipper` script, the app downloads the source video before trimming; long videos can take time and temporary disk space. It prefers video up to 1080p, then produces H.264/AAC MP4 with accurate trimming. Temporary downloads and incomplete clips are removed on completion, failure, or cancellation. The original shell script is not required or modified. This app handles public videos accessible to `yt-dlp`; it does not import browser cookies or offer a login flow.

## Development

```sh
swift build
swift test
./scripts/build-app.sh
```

Tests cover time/URL validation, cancellation, failures, and all four optional-time combinations using a generated local video and real FFmpeg. They require `yt-dlp` and FFmpeg on the test machine, but do not access the network by default. An optional live download test uses a short public YouTube video:

```sh
YT_CLIPPER_LIVE_TEST=1 swift test --filter liveYouTubeDownload
```

`Resources/AppIcon.icns` is included. Its AppKit drawing source is `scripts/make-icon.swift`. To regenerate:

```sh
swift scripts/make-icon.swift /tmp/yt-clipper.iconset
iconutil -c icns /tmp/yt-clipper.iconset -o Resources/AppIcon.icns
```
