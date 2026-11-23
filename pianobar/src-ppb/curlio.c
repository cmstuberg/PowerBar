/* curlio: an AVIOContext backed by a libcurl multi handle (see curlio.h).
 *
 * The transfer runs ahead of the decoder into a buffer (up to HIGH_WATER, then
 * curl is paused until the decoder catches up). Songs are a few MB, so in practice
 * the whole song is fetched early, which rides out Wi-Fi dropouts, and Pandora's
 * signed URLs can't expire mid-song. Seeking (the MP4 demuxer may, and pianobar
 * does after a network error) restarts the transfer with a Range request. A
 * dropped connection is resumed the same way, a few times, before the read fails
 * with ECONNRESET, which makes pianobar reopen the stream at the last position.
 *
 * Part of PowerBar. MIT licence, like pianobar. */
#include <errno.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include <curl/curl.h>
#include <libavformat/avformat.h>
#include <libavutil/mem.h>

#include "ppctls.h"
#include "curlio.h"

#define HIGH_WATER (8 * 1024 * 1024)  /* pause curl above this much unread data */
#define LOW_WATER  (1 * 1024 * 1024)  /* resume it below this */
#define AVIO_BUF   32768
#define MAX_RESUME 3                  /* reconnects per stream before giving up */

typedef struct {
	CURLM *multi;
	CURL *easy;
	char *url;
	unsigned int timeout;
	int (*interrupt) (void *);
	void *opaque;

	char *buf;
	size_t cap, off, len;   /* unread data is buf[off, len) */
	int paused;
	int done;               /* transfer finished (result says how) */
	CURLcode result;
	int64_t start;          /* offset the current transfer started at */
	int64_t pos;            /* stream offset of buf[off] */
	int64_t size;           /* total size, or -1 */
	int resumes;
} curlio_t;

static size_t writeCb (char *ptr, size_t size, size_t nmemb, void *data) {
	curlio_t * const io = data;
	const size_t n = size * nmemb;
	if (io->len - io->off >= HIGH_WATER) {
		io->paused = 1;
		return CURL_WRITEFUNC_PAUSE;
	}
	if (io->off > 0 && io->len + n > io->cap) {
		memmove (io->buf, io->buf + io->off, io->len - io->off);
		io->len -= io->off;
		io->off = 0;
	}
	if (io->len + n > io->cap) {
		size_t cap = io->cap ? io->cap : 65536;
		while (cap < io->len + n) cap *= 2;
		char *b = realloc (io->buf, cap);
		if (b == NULL) return 0;   /* aborts the transfer (CURLE_WRITE_ERROR) */
		io->buf = b;
		io->cap = cap;
	}
	memcpy (io->buf + io->len, ptr, n);
	io->len += n;
	return n;
}

static void stopTransfer (curlio_t * const io) {
	if (io->easy != NULL) {
		curl_multi_remove_handle (io->multi, io->easy);
		curl_easy_cleanup (io->easy);
		io->easy = NULL;
	}
	io->off = io->len = 0;
	io->paused = 0;
}

static int startTransfer (curlio_t * const io, int64_t offset) {
	stopTransfer (io);
	io->done = 0;
	io->result = CURLE_OK;
	io->start = io->pos = offset;
	if ((io->easy = curl_easy_init ()) == NULL) return AVERROR (ENOMEM);
	if (ppctls_curl_setup (io->easy) != CURLE_OK) return AVERROR (EINVAL);
	curl_easy_setopt (io->easy, CURLOPT_URL, io->url);
	curl_easy_setopt (io->easy, CURLOPT_WRITEFUNCTION, writeCb);
	curl_easy_setopt (io->easy, CURLOPT_WRITEDATA, io);
	curl_easy_setopt (io->easy, CURLOPT_FAILONERROR, 1L);
	curl_easy_setopt (io->easy, CURLOPT_CONNECTTIMEOUT, (long) io->timeout);
	/* a stalled transfer (under 1 byte/s for timeout seconds) is an error */
	curl_easy_setopt (io->easy, CURLOPT_LOW_SPEED_LIMIT, 1L);
	curl_easy_setopt (io->easy, CURLOPT_LOW_SPEED_TIME, (long) io->timeout);
	if (offset > 0) {
		curl_easy_setopt (io->easy, CURLOPT_RESUME_FROM_LARGE, (curl_off_t) offset);
	}
	if (curl_multi_add_handle (io->multi, io->easy) != CURLM_OK) return AVERROR (EINVAL);
	return 0;
}

static int transient (CURLcode c) {
	return c == CURLE_PARTIAL_FILE || c == CURLE_RECV_ERROR || c == CURLE_SEND_ERROR ||
			c == CURLE_OPERATION_TIMEDOUT || c == CURLE_GOT_NOTHING ||
			c == CURLE_COULDNT_CONNECT || c == CURLE_COULDNT_RESOLVE_HOST ||
			c == CURLE_SSL_CONNECT_ERROR;
}

/* Run the transfer until there is unread data or it finished. Returns 0, or an
 * AVERROR when interrupted. */
static int pump (curlio_t * const io) {
	while (io->len == io->off && !io->done) {
		if (io->interrupt != NULL && io->interrupt (io->opaque)) {
			return AVERROR_EXIT;
		}
		int running = 0;
		curl_multi_perform (io->multi, &running);
		CURLMsg *msg;
		int left;
		while ((msg = curl_multi_info_read (io->multi, &left)) != NULL) {
			if (msg->msg == CURLMSG_DONE && msg->easy_handle == io->easy) {
				io->done = 1;
				io->result = msg->data.result;
			}
		}
		if (io->size < 0 && io->easy != NULL) {
			curl_off_t cl = -1;
			long code = 0;
			curl_easy_getinfo (io->easy, CURLINFO_RESPONSE_CODE, &code);
			if (curl_easy_getinfo (io->easy, CURLINFO_CONTENT_LENGTH_DOWNLOAD_T, &cl) == CURLE_OK &&
					cl >= 0 && (code == 200 || code == 206)) {
				io->size = io->start + cl;
			}
		}
		if (io->len == io->off && !io->done) {
			curl_multi_wait (io->multi, NULL, 0, 100, NULL);
		}
	}
	return 0;
}

static int readPacket (void *opaque, uint8_t *dst, int want) {
	curlio_t * const io = opaque;
	for (;;) {
		const size_t avail = io->len - io->off;
		if (avail > 0) {
			const size_t n = avail < (size_t) want ? avail : (size_t) want;
			memcpy (dst, io->buf + io->off, n);
			io->off += n;
			io->pos += n;
			if (io->paused && io->len - io->off < LOW_WATER) {
				io->paused = 0;
				curl_easy_pause (io->easy, CURLPAUSE_CONT);
			}
			return (int) n;
		}
		if (io->done) {
			if (io->result == CURLE_OK) return AVERROR_EOF;
			if (transient (io->result) && io->resumes < MAX_RESUME &&
					(io->size < 0 || io->pos < io->size)) {
				io->resumes++;
				int r = startTransfer (io, io->pos);
				if (r < 0) return r;
				continue;
			}
			return AVERROR (ECONNRESET);
		}
		int r = pump (io);
		if (r < 0) return r;
	}
}

static int64_t seekCb (void *opaque, int64_t offset, int whence) {
	curlio_t * const io = opaque;
	whence &= ~AVSEEK_FORCE;
	if (whence == AVSEEK_SIZE) return io->size >= 0 ? io->size : AVERROR (ENOSYS);

	int64_t target;
	switch (whence) {
		case SEEK_SET: target = offset; break;
		case SEEK_CUR: target = io->pos + offset; break;
		case SEEK_END:
			if (io->size < 0) return AVERROR (ENOSYS);
			target = io->size + offset;
			break;
		default: return AVERROR (EINVAL);
	}
	if (target < 0) return AVERROR (EINVAL);
	if (target == io->pos) return target;

	/* forward, within what's already buffered: skip */
	if (target > io->pos && target - io->pos <= (int64_t) (io->len - io->off)) {
		io->off += (size_t) (target - io->pos);
		io->pos = target;
		return target;
	}
	if (io->size >= 0 && target >= io->size) {
		/* at (or past) the end: nothing left to fetch */
		stopTransfer (io);
		io->pos = target;
		io->done = 1;
		io->result = CURLE_OK;
		return target;
	}
	int r = startTransfer (io, target);
	return r < 0 ? r : target;
}

static void freeIo (curlio_t *io) {
	if (io == NULL) return;
	stopTransfer (io);
	if (io->multi != NULL) curl_multi_cleanup (io->multi);
	free (io->buf);
	free (io->url);
	free (io);
}

AVIOContext *BarCurlIoOpen (const char *url, unsigned int timeout,
		int (*interrupt) (void *), void *opaque, int *err) {
	int r = AVERROR (ENOMEM);
	curlio_t *io = calloc (1, sizeof (*io));
	unsigned char *avbuf = NULL;
	AVIOContext *pb = NULL;
	if (io == NULL) goto fail;
	io->size = -1;
	io->timeout = timeout > 0 ? timeout : 30;
	io->interrupt = interrupt;
	io->opaque = opaque;
	if ((io->url = strdup (url)) == NULL || (io->multi = curl_multi_init ()) == NULL) goto fail;
	if ((r = startTransfer (io, 0)) < 0) goto fail;

	/* wait for the first data, so HTTP errors (expired URL etc.) show up here */
	if ((r = pump (io)) < 0) goto fail;
	if (io->done && io->result != CURLE_OK && io->len == io->off) {
		long code = 0;
		curl_easy_getinfo (io->easy, CURLINFO_RESPONSE_CODE, &code);
		r = code == 403 ? AVERROR_HTTP_FORBIDDEN :
			code == 404 ? AVERROR_HTTP_NOT_FOUND :
			code >= 400 ? AVERROR_HTTP_OTHER_4XX : AVERROR (EIO);
		goto fail;
	}

	r = AVERROR (ENOMEM);
	if ((avbuf = av_malloc (AVIO_BUF)) == NULL) goto fail;
	pb = avio_alloc_context (avbuf, AVIO_BUF, 0, io, readPacket, NULL, seekCb);
	if (pb == NULL) goto fail;
	pb->seekable = io->size >= 0 ? AVIO_SEEKABLE_NORMAL : 0;
	return pb;

fail:
	av_free (avbuf);
	freeIo (io);
	if (err != NULL) *err = r;
	return NULL;
}

void BarCurlIoClose (AVIOContext **pb) {
	if (pb == NULL || *pb == NULL) return;
	freeIo ((*pb)->opaque);
	av_freep (&(*pb)->buffer);
	avio_context_free (pb);
}
