# Nova

A native macOS video player for frame-accurate review: SMPTE timecode in the title bar, JKL shuttle, single-frame stepping, exact frame copies, and an expandable full-width timeline. AppKit and Swift, macOS 13 or later.

## Playback engines

- **AVFoundation** plays everything macOS decodes natively, with hardware decoding and the system controls.
- **libmpv** (from the [MPVKit](https://github.com/mpvkit/MPVKit) Swift package) takes every other container and codec: MKV, WebM, AVI, WMV, FLV, DNxHD, VP9, AV1, Theora and so on. Nova links its own full-decoder build of ffmpeg from `ThirdParty/ffmpeg` ahead of the package's whitelisted copy; rebuild it with `Scripts/build-ffmpeg.sh`.

View code talks only to the `PlaybackEngine` protocol in `Nova/Engine`, so either engine can change without touching the UI.

## Building

Open `Nova.xcodeproj` in Xcode 26 and run. Xcode resolves the MPVKit package on first build. `Scripts/make-dmg.sh` produces a universal Release disk image in `build/`.

## Testing

`Scripts/harness/make-test-clips.sh <dir>` generates frame-numbered clips in every container (needs ffmpeg), and `Scripts/harness/build-and-run.sh <clips…>` opens a real window and verifies stepping, seeking, reverse shuttle, captures, on-screen frames, timecode copy and paste, the timeline, and the menus. Run it on an idle machine.

## Licences

Nova's own code is the author's. It links MPVKit (LGPL build of mpv), ffmpeg n8.1.2 built as LGPL v3, and dav1d (BSD-2).
