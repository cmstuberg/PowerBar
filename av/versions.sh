# Pinned upstream source. The checksum matches the MacPorts Portfile (multimedia/ffmpeg6).
#
# ffmpeg 6.1 is the last series that builds with a C99 compiler: ffmpeg 7.0 and later
# require C11, which Apple gcc-4.0 (the only compiler that works with the 10.4u SDK)
# does not support.
FFMPEG_VERSION=6.1.6
FFMPEG_SHA256=d4fcb164028dd3beee5d92c0ac72e46aac6973c75ea12dc14de07bf8f407370a
FFMPEG_URL=https://ffmpeg.org/releases/ffmpeg-$FFMPEG_VERSION.tar.xz
