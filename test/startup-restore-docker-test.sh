#!/usr/bin/env bash
# Does a freshly started tmux server restore the last save, exactly once, and
# do continuum's guards still stop it? Each case runs in its own Debian
# container: continuum's "another server" check sees every tmux process of the
# user, so it cannot be tested next to a running tmux.
#
# Usage: test/startup-restore-docker-test.sh [tmux-resurrect dir] [tmux-continuum dir]
# Defaults to ~/.tmux/plugins/tmux-resurrect and ~/.tmux/plugins/tmux-continuum.

set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RESURRECT="${1:-$HOME/.tmux/plugins/tmux-resurrect}"
CONTINUUM="${2:-$HOME/.tmux/plugins/tmux-continuum}"
IMAGE=session-keeper-startup-restore:test

if ! docker image inspect "$IMAGE" >/dev/null 2>&1; then
	printf 'FROM debian:13-slim\nRUN apt-get update -qq && apt-get install -y -qq tmux procps jq >/dev/null\n' |
		docker build -q -t "$IMAGE" - >/dev/null
fi

# Inside the container: save two windows, kill the server, start tmux fresh.
# $1 = case name.
INNER='
set -u
case=$1
mkdir -p /work/alpha /work/beta
{
	case $case in
	explicit) echo "set -g @continuum-restore on" ;;
	off) echo "set -g @continuum-restore off" ;;
	plugin-first) echo "run-shell /plugin/tmux-assistant-resurrect.tmux" ;;
	esac
	echo "run-shell /plugins/tmux-resurrect/resurrect.tmux"
	echo "run-shell /plugins/tmux-continuum/continuum.tmux"
	[ "$case" = plugin-first ] || echo "run-shell /plugin/tmux-assistant-resurrect.tmux"
} >/root/.tmux.conf
tmux new-session -d -s work -n alpha -c /work/alpha
tmux new-window -t work -n beta -c /work/beta
sleep 2
tmux run-shell "/plugins/tmux-resurrect/scripts/save.sh quiet"
tmux kill-server
sleep 1
[ "$case" = halt ] && touch /root/tmux_no_auto_restore
[ "$case" = other-server ] && tmux -L other -f /dev/null new-session -d -s other
tmux new-session -d -s 0
sleep 20
windows=$(tmux list-windows -t work -F "#{window_name}" 2>/dev/null | tr "\n" " ")
restores=$(grep -c "^\[.*\] reading " /root/.local/share/tmux/resurrect/assistant-restore.log 2>/dev/null)
echo "windows=[${windows% }] restores=${restores:-0}"
'

PASS=0
FAIL=0
check() {
	local case="$1" expected="$2" actual
	actual=$(docker run --rm \
		-v "$REPO_DIR:/plugin:ro" \
		-v "$RESURRECT:/plugins/tmux-resurrect:ro" \
		-v "$CONTINUUM:/plugins/tmux-continuum:ro" \
		"$IMAGE" bash -c "$INNER" _ "$case" | tail -1)
	if [ "$actual" = "$expected" ]; then
		PASS=$((PASS + 1))
		printf '  [pass] %s: %s\n' "$case" "$actual"
	else
		FAIL=$((FAIL + 1))
		printf '  [FAIL] %s: expected %s, got %s\n' "$case" "$expected" "$actual"
	fi
}

echo "== startup restore (each case ~25 s) =="
# continuum's own attempt is a coin flip, so repeat the restoring cases.
for _ in 1 2 3; do
	check default 'windows=[alpha beta] restores=1'
	check explicit 'windows=[alpha beta] restores=1'
	check plugin-first 'windows=[alpha beta] restores=1'
done
check off 'windows=[] restores=0'
check halt 'windows=[] restores=0'
check other-server 'windows=[] restores=0'

echo "startup restore docker tests: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
