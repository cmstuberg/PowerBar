/* ao/ao.h: the part of the libao API that pianobar uses, implemented on CoreAudio's
 * default output unit (compat/ao_coreaudio.c). Works on Mac OS X 10.4 and later.
 *
 * Why: libao loads its output drivers as plugins from a fixed directory at runtime,
 * which doesn't suit a self-contained .app, and pianobar only needs "play 16-bit
 * PCM on the default device" (plus raw output to a pipe for audio_pipe).
 *
 * Part of PowerBar. MIT licence, like pianobar. */
#ifndef PPB_AO_COMPAT_H
#define PPB_AO_COMPAT_H

#include <stdint.h>

#define AO_FMT_LITTLE 1
#define AO_FMT_BIG    2
#define AO_FMT_NATIVE 4

typedef struct ao_sample_format {
	int bits;         /* bits per sample (16 or 32) */
	int rate;         /* samples per second */
	int channels;     /* interleaved channels */
	int byte_format;  /* AO_FMT_* */
	char *matrix;     /* ignored */
} ao_sample_format;

typedef struct ao_option ao_option;   /* options are not supported; pass NULL */
typedef struct ao_device ao_device;
typedef uint32_t uint_32;

void ao_initialize (void);
void ao_shutdown (void);
int ao_default_driver_id (void);
/* "coreaudio" (also "macosx") and "raw"; -1 for anything else */
int ao_driver_id (const char *short_name);
ao_device *ao_open_live (int driver_id, ao_sample_format *format, ao_option *options);
ao_device *ao_open_file (int driver_id, const char *filename, int overwrite,
		ao_sample_format *format, ao_option *options);
/* Blocks until the samples are queued. Returns nonzero on success. */
int ao_play (ao_device *device, char *output_samples, uint_32 num_bytes);
/* Plays out what's queued, then releases the device. Returns 1. */
int ao_close (ao_device *device);

#endif
