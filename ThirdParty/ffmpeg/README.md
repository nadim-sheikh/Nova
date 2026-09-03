# ffmpeg static libraries

Universal (arm64 + x86_64) static builds of ffmpeg n8.1.2 with **every** decoder, demuxer,
parser and bitstream filter enabled, plus VideoToolbox/AudioToolbox and dav1d (AV1).

Nova links these with `-force_load` (see `OTHER_LDFLAGS` in the Xcode project) so they take
precedence over the whitelisted ffmpeg inside the MPVKit Swift package, which lacks DNxHD, DV,
Theora, CineForm, MXF and many others. libmpv from MPVKit is built against the same ffmpeg
release, so the two are ABI-compatible.

Rebuild with `Scripts/build-ffmpeg.sh` (Xcode only, about ten minutes).

Licence: ffmpeg is LGPL v3 here (`--enable-version3`, no GPL components); dav1d is BSD-2.
