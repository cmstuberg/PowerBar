#!/bin/sh
# Compiler wrapper for the g4 OpenSSL slice.
#
# OpenSSL's ppc perlasm emits ".machine ppc970" on OS X so the assembler accepts
# its 64-bit and POWER8 paths, which are only taken after a runtime CPU check
# (crypto/ppccap.c). That tags each asm object G5-only (cpusubtype ppc970), so
# the g4 libcrypto.a, and any G4 app linked against it, would be marked G5-only
# and refuse to run on a G4. lipo also labels an archive by one member, so the
# members have to agree.
#
# For assembler inputs, assemble as usual and then set the object's Mach-O
# cpusubtype to ppc7400 (10). The code runs on a G4 because of those runtime
# checks; only the label changes. C objects are already ppc7400.
src=""; out=""; prev=""
for a in "$@"; do
  case $a in *.s|*.S) src=$a ;; esac
  [ "$prev" = "-o" ] && out=$a
  prev=$a
done
"$REAL_CC" "$@" || exit $?
if [ -n "$src" ] && [ -n "$out" ] && [ -f "$out" ]; then
  /usr/bin/perl -e '
    open(F, "+<", $ARGV[0]) or die "$ARGV[0]: $!";
    binmode F; read(F, my $h, 12) == 12 or die "short read";
    my ($magic, $cpu, $sub) = unpack("NNN", $h);
    die "$ARGV[0]: not a 32-bit big-endian ppc Mach-O\n" unless $magic == 0xfeedface && $cpu == 18;
    if ($sub == 100) { seek(F, 8, 0); print F pack("N", 10); }   # ppc970 -> ppc7400
    close F;' "$out" || exit 1
fi
