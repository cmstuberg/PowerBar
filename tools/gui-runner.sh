#!/bin/sh
# Runs inside the user's Aqua (GUI) session, started by launchd whenever a job
# lands in ~/.gui-run/queue (see local.ppc.gui-runner.plist). Each job is a
# small shell script written by gui-run; output and exit status go to ~/.gui-run/out.
Q="$HOME/.gui-run/queue"; O="$HOME/.gui-run/out"
mkdir -p "$O"
for job in "$Q"/*; do
  [ -f "$job" ] || continue
  id=$(basename "$job")
  mv "$job" "$O/$id.sh" || continue
  /bin/sh "$O/$id.sh" > "$O/$id.log" 2>&1
  echo $? > "$O/$id.exit.tmp" && mv "$O/$id.exit.tmp" "$O/$id.exit"
done
