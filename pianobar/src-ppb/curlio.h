/* curlio: feed ffmpeg's demuxer from libcurl instead of ffmpeg's own http/tls code,
 * so the audio stream goes through the same TLS stack (OpenSSL 3 + our CA bundle,
 * certificate verification on) as pianobar's API calls.
 *
 * Part of PowerBar. MIT licence, like pianobar. */
#ifndef PPB_CURLIO_H
#define PPB_CURLIO_H

#include <libavformat/avio.h>

/* Open url and wait for the response headers. timeout is in seconds (connect and
 * stall timeout). interrupt(opaque) is polled while waiting: nonzero aborts.
 * Returns an AVIOContext to put in AVFormatContext.pb (with
 * AVFMT_FLAG_CUSTOM_IO), or NULL with *err set to an AVERROR code. */
AVIOContext *BarCurlIoOpen (const char *url, unsigned int timeout,
		int (*interrupt) (void *), void *opaque, int *err);

/* Free the context (avformat_close_input doesn't free a custom pb). NULL is fine. */
void BarCurlIoClose (AVIOContext **pb);

#endif
