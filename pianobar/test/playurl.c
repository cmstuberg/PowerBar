/* playurl: run pianobar's own player thread (player.c) on one URL, outside of a
 * Pandora session. This tests the whole audio path: curlio (libcurl + our TLS
 * stack) -> ffmpeg demux/decode/filter -> the libao shim (CoreAudio, or a pipe).
 *
 *   playurl URL [seconds]
 *
 * Uses $XDG_CONFIG_HOME/pianobar/config like pianobar does, so audio_pipe = FIFO
 * sends raw PCM to a pipe instead of the speakers. With [seconds], stops early
 * (and skips the "played to the end" check). Prints duration/played and exits 0 when
 * the player finished cleanly. */
#include "config.h"

#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
#include <pthread.h>

#include "player.h"
#include "settings.h"
#include "ppctls.h"

/* main.c (not linked here) owns this one */
sig_atomic_t *interrupted = NULL;

int main (int argc, char **argv) {
	if (argc < 2) {
		fprintf (stderr, "usage: %s URL [seconds]\n", argv[0]);
		return 2;
	}
	const int limit = argc > 2 ? atoi (argv[2]) : 0;

	ppctls_global_init ();
	BarSettings_t settings;
	BarSettingsInit (&settings);
	BarSettingsRead (&settings);

	player_t player;
	BarPlayerInit (&player, &settings);
	player.url = argv[1];
	player.gain = 0;

	pthread_t t;
	pthread_create (&t, NULL, BarPlayerThread, &player);
	for (int waited = 0; ; waited++) {
		if (BarPlayerGetMode (&player) == PLAYER_FINISHED) break;
		if (limit > 0 && waited >= limit * 10) {
			pthread_mutex_lock (&player.lock);
			player.doQuit = true;
			pthread_cond_broadcast (&player.cond);
			pthread_mutex_unlock (&player.lock);
			pthread_mutex_lock (&player.aoplayLock);
			pthread_cond_broadcast (&player.aoplayCond);
			pthread_mutex_unlock (&player.aoplayLock);
			break;
		}
		usleep (100000);
	}
	void *ret;
	pthread_join (t, &ret);

	const unsigned int dur = player.songDuration, played = player.songPlayed;
	printf ("%s [%s]: result %lu, duration %us, played %us\n", argv[1], PPC_SLICE,
			(unsigned long) (uintptr_t) ret, dur, played);
	BarPlayerDestroy (&player);
	BarSettingsDestroy (&settings);

	if ((uintptr_t) ret != PLAYER_RET_OK || dur == 0) return 1;
	if (limit == 0 && played + 1 < dur) return 1;
	return 0;
}
