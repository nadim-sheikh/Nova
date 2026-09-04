# Nova

A native macOS video player for frame-accurate review: SMPTE timecode in the title bar, JKL shuttle, single-frame stepping, exact frame copies, and an expandable full-width timeline. AppKit and Swift, macOS 13 or later.

## Download

Grab the latest disk image from the [Releases page](https://github.com/nadim-sheikh/Nova/releases/latest), open it, and drag Nova to Applications. It is a universal build for Apple silicon and Intel Macs running macOS 13 or later.

The app is signed ad hoc rather than with an Apple Developer ID, so the first launch is refused by Gatekeeper. Either open System Settings > Privacy & Security and click "Open Anyway" next to Nova, or run this once:

```
xattr -dr com.apple.quarantine /Applications/Nova.app
```

## Playback engines

- **AVFoundation** plays everything macOS decodes natively, with hardware decoding and the system controls.
- **libmpv** (from the [MPVKit](https://github.com/mpvkit/MPVKit) Swift package) takes every other container and codec: MKV, WebM, AVI, WMV, FLV, DNxHD, VP9, AV1, Theora and so on. Nova links its own full-decoder build of ffmpeg from `ThirdParty/ffmpeg` ahead of the package's whitelisted copy; rebuild it with `Scripts/build-ffmpeg.sh`.

View code talks only to the `PlaybackEngine` protocol in `Nova/Engine`, so either engine can change without touching the UI.

## Building

Open `Nova.xcodeproj` in Xcode 26 and run. Xcode resolves the MPVKit package on first build. `Scripts/make-dmg.sh` produces a universal Release disk image in `build/`.

## Testing

`Scripts/harness/make-test-clips.sh <dir>` generates frame-numbered clips in every container (needs ffmpeg), and `Scripts/harness/build-and-run.sh <clips…>` opens a real window and verifies stepping, seeking, reverse shuttle, captures, on-screen frames, timecode copy and paste, the timeline, and the menus. Run it on an idle machine.

## Licence

Nova is open source under the [MIT License](LICENSE).

It links third-party libraries under their own licences: [mpv](https://mpv.io) via the LGPL build of [MPVKit](https://github.com/mpvkit/MPVKit) (LGPL 2.1 or later), [FFmpeg](https://ffmpeg.org) 8.1.2 built as LGPL 3 with no GPL components (`Scripts/build-ffmpeg.sh`), and [dav1d](https://code.videolan.org/videolan/dav1d) (BSD 2-Clause). Because those libraries are linked statically, the LGPL's relinking requirement is met by this repository: the full build is reproducible from source.
