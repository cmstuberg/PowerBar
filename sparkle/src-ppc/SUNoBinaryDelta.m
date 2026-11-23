/* Delta updates (SUBinaryDelta*, bspatch) need libxar, which Tiger doesn't have.
 * Upstream weak-links libxar and reports deltas unsupported when it's missing, so
 * on 10.4 stock Sparkle already falls back to the full archive. We leave the delta
 * code out and report the same thing everywhere. (Sparkle 1.5b6, which most
 * Tiger/Leopard apps ship, predates delta updates.) */
int binaryDeltaSupported (void);

int binaryDeltaSupported (void) {
    return 0;
}
