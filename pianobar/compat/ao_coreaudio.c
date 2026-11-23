/* libao subset on CoreAudio (see ao/ao.h).
 *
 * Live output: the Default Output AudioUnit, opened through the Component Manager
 * (AudioComponent* is 10.6+). Its built-in converter takes our interleaved,
 * native-endian signed PCM at the stream's rate. A small ring buffer sits between
 * ao_play (decoder thread, blocks when full) and the render callback (CoreAudio's
 * thread, plays silence on underrun).
 *
 * Part of PowerBar. MIT licence, like pianobar. */
#include <AudioUnit/AudioUnit.h>
#include <CoreServices/CoreServices.h>
#include <pthread.h>
#include <fcntl.h>
#include <unistd.h>
#include <errno.h>
#include <stdlib.h>
#include <string.h>
#include <sys/time.h>

#include "ao/ao.h"

enum { DRIVER_COREAUDIO = 1, DRIVER_RAW = 2 };

/* Queue about this much audio. Small, so pause and skip take effect quickly,
 * but enough to ride out a busy G3. */
#define BUFFER_MS 250

struct ao_device {
	int driver;
	int fd;                     /* raw */
	AudioUnit unit;             /* coreaudio */
	int started;
	pthread_mutex_t lock;
	pthread_cond_t cond;
	char *buf;
	size_t size, head, used;    /* ring buffer: read at head, used bytes queued */
	size_t frameBytes;
};

void ao_initialize (void) {}
void ao_shutdown (void) {}
int ao_default_driver_id (void) { return DRIVER_COREAUDIO; }

int ao_driver_id (const char *name) {
	if (name == NULL) return -1;
	if (strcmp (name, "coreaudio") == 0 || strcmp (name, "macosx") == 0) return DRIVER_COREAUDIO;
	if (strcmp (name, "raw") == 0) return DRIVER_RAW;
	return -1;
}

static OSStatus render (void *ref, AudioUnitRenderActionFlags *flags,
		const AudioTimeStamp *ts, UInt32 bus, UInt32 frames, AudioBufferList *io) {
	ao_device * const d = ref;
	char *out = io->mBuffers[0].mData;
	size_t want = io->mBuffers[0].mDataByteSize, got = 0;
	(void) ts; (void) bus; (void) frames;

	pthread_mutex_lock (&d->lock);
	while (got < want && d->used > 0) {
		size_t n = d->size - d->head;
		if (n > d->used) n = d->used;
		if (n > want - got) n = want - got;
		memcpy (out + got, d->buf + d->head, n);
		d->head = (d->head + n) % d->size;
		d->used -= n;
		got += n;
	}
	pthread_cond_broadcast (&d->cond);
	pthread_mutex_unlock (&d->lock);

	if (got < want) {
		memset (out + got, 0, want - got);
		if (got == 0) *flags |= kAudioUnitRenderAction_OutputIsSilence;
	}
	return noErr;
}

static ao_device *newDevice (int driver, const ao_sample_format *fmt) {
	if (fmt == NULL || (fmt->bits != 16 && fmt->bits != 32) || fmt->channels < 1 || fmt->rate < 1) {
		return NULL;
	}
	ao_device *d = calloc (1, sizeof (*d));
	if (d == NULL) return NULL;
	d->driver = driver;
	d->fd = -1;
	d->frameBytes = (size_t) fmt->channels * (size_t) (fmt->bits / 8);
	pthread_mutex_init (&d->lock, NULL);
	pthread_cond_init (&d->cond, NULL);
	return d;
}

static void freeDevice (ao_device *d) {
	pthread_cond_destroy (&d->cond);
	pthread_mutex_destroy (&d->lock);
	free (d->buf);
	free (d);
}

ao_device *ao_open_live (int driver, ao_sample_format *fmt, ao_option *opts) {
	(void) opts;
	if (driver != DRIVER_COREAUDIO) return NULL;
	ao_device *d = newDevice (driver, fmt);
	if (d == NULL) return NULL;

	size_t frames = (size_t) fmt->rate * BUFFER_MS / 1000;
	d->size = frames * d->frameBytes;
	if ((d->buf = malloc (d->size)) == NULL) goto fail;

	ComponentDescription desc;
	memset (&desc, 0, sizeof (desc));
	desc.componentType = kAudioUnitType_Output;
	desc.componentSubType = kAudioUnitSubType_DefaultOutput;
	desc.componentManufacturer = kAudioUnitManufacturer_Apple;
	Component comp = FindNextComponent (NULL, &desc);
	if (comp == NULL || OpenAComponent (comp, &d->unit) != noErr) goto fail;

	AudioStreamBasicDescription asbd;
	memset (&asbd, 0, sizeof (asbd));
	asbd.mSampleRate = fmt->rate;
	asbd.mFormatID = kAudioFormatLinearPCM;
	asbd.mFormatFlags = kAudioFormatFlagIsSignedInteger | kAudioFormatFlagIsPacked;
	int big = fmt->byte_format == AO_FMT_BIG;
#ifdef __BIG_ENDIAN__
	if (fmt->byte_format == AO_FMT_NATIVE) big = 1;
#endif
	if (big) asbd.mFormatFlags |= kAudioFormatFlagIsBigEndian;
	asbd.mChannelsPerFrame = fmt->channels;
	asbd.mBitsPerChannel = fmt->bits;
	asbd.mFramesPerPacket = 1;
	asbd.mBytesPerFrame = d->frameBytes;
	asbd.mBytesPerPacket = d->frameBytes;
	if (AudioUnitSetProperty (d->unit, kAudioUnitProperty_StreamFormat,
			kAudioUnitScope_Input, 0, &asbd, sizeof (asbd)) != noErr) goto failUnit;

	AURenderCallbackStruct cb = { render, d };
	if (AudioUnitSetProperty (d->unit, kAudioUnitProperty_SetRenderCallback,
			kAudioUnitScope_Input, 0, &cb, sizeof (cb)) != noErr) goto failUnit;
	if (AudioUnitInitialize (d->unit) != noErr) goto failUnit;
	return d;

failUnit:
	CloseComponent (d->unit);
fail:
	freeDevice (d);
	return NULL;
}

ao_device *ao_open_file (int driver, const char *filename, int overwrite,
		ao_sample_format *fmt, ao_option *opts) {
	(void) opts;
	if (driver != DRIVER_RAW || filename == NULL) return NULL;
	ao_device *d = newDevice (driver, fmt);
	if (d == NULL) return NULL;
	int flags = O_WRONLY | O_CREAT | (overwrite ? O_TRUNC : O_EXCL);
	if ((d->fd = open (filename, flags, 0644)) < 0) {
		freeDevice (d);
		return NULL;
	}
	return d;
}

int ao_play (ao_device *d, char *samples, uint_32 n) {
	if (d == NULL) return 0;
	if (d->driver == DRIVER_RAW) {
		while (n > 0) {
			ssize_t w = write (d->fd, samples, n);
			if (w < 0) {
				if (errno == EINTR) continue;
				return 0;
			}
			samples += w;
			n -= (uint_32) w;
		}
		return 1;
	}

	while (n > 0) {
		pthread_mutex_lock (&d->lock);
		while (d->used == d->size) {
			pthread_cond_wait (&d->cond, &d->lock);
		}
		size_t tail = (d->head + d->used) % d->size;
		size_t space = d->size - d->used;
		size_t chunk = d->size - tail;
		if (chunk > space) chunk = space;
		if (chunk > n) chunk = n;
		memcpy (d->buf + tail, samples, chunk);
		d->used += chunk;
		int start = !d->started && d->used == d->size;
		pthread_mutex_unlock (&d->lock);
		samples += chunk;
		n -= (uint_32) chunk;

		/* start once the buffer is full, so playback doesn't open on an underrun */
		if (start) {
			if (AudioOutputUnitStart (d->unit) != noErr) return 0;
			d->started = 1;
		}
	}
	return 1;
}

int ao_close (ao_device *d) {
	if (d == NULL) return 1;
	if (d->driver == DRIVER_RAW) {
		close (d->fd);
		freeDevice (d);
		return 1;
	}

	pthread_mutex_lock (&d->lock);
	if (!d->started && d->used > 0) {
		/* short song (or skipped early): play what we have */
		pthread_mutex_unlock (&d->lock);
		if (AudioOutputUnitStart (d->unit) == noErr) d->started = 1;
		pthread_mutex_lock (&d->lock);
	}
	/* drain, but never wait longer than the buffer could possibly take */
	struct timeval now;
	gettimeofday (&now, NULL);
	struct timespec until = { now.tv_sec + 1 + BUFFER_MS / 1000, now.tv_usec * 1000 };
	while (d->started && d->used > 0) {
		if (pthread_cond_timedwait (&d->cond, &d->lock, &until) == ETIMEDOUT) break;
	}
	pthread_mutex_unlock (&d->lock);

	if (d->started) AudioOutputUnitStop (d->unit);
	AudioUnitUninitialize (d->unit);
	CloseComponent (d->unit);
	freeDevice (d);
	return 1;
}
