#!/bin/sh
# Install the GUI-session job runner (tools/gui-run) for the current user. Run it over
# SSH while that user is logged in to a GUI session (Fast User Switching is fine).
# launchd loads it automatically at every later GUI login.
set -e
cd "$(dirname "$0")"
mkdir -p "$HOME/.gui-run/queue" "$HOME/.gui-run/out" "$HOME/Library/LaunchAgents"
# the plist is a template: point it at this checkout and this user's queue
sed -e "s|@RUNNER@|$(pwd)/gui-runner.sh|" -e "s|@QUEUE@|$HOME/.gui-run/queue|" \
  local.ppc.gui-runner.plist > "$HOME/Library/LaunchAgents/local.ppc.gui-runner.plist"
chmod +x gui-run gui-runner.sh
# An SSH shell can't load into the Aqua session itself, but `open` reaches it:
# Terminal runs this .command inside the GUI session, loads the agent and exits.
C="$HOME/.gui-run/load-agent.command"
cat > "$C" <<EOC
#!/bin/sh
launchctl unload "$HOME/Library/LaunchAgents/local.ppc.gui-runner.plist" 2>/dev/null
launchctl load -S Aqua "$HOME/Library/LaunchAgents/local.ppc.gui-runner.plist"
launchctl list | grep gui-runner > "$HOME/.gui-run/load-agent.result"
osascript -e 'tell application "Terminal" to quit' &
EOC
chmod +x "$C"; rm -f "$HOME/.gui-run/load-agent.result"
open "$C"
i=0; while [ ! -s "$HOME/.gui-run/load-agent.result" ] && [ $i -lt 20 ]; do sleep 1; i=$((i+1)); done
if [ -s "$HOME/.gui-run/load-agent.result" ]; then echo "loaded: $(cat "$HOME/.gui-run/load-agent.result")"; else echo "agent did not load" >&2; exit 1; fi
