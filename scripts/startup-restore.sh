#!/usr/bin/env bash
# Restore a freshly started tmux server when tmux-continuum's auto-restore
# did not. Started in the background by tmux-assistant-resurrect.tmux while the
# config loads, only when the server has just started.
#
# continuum's auto-restore is unreliable: it reads @continuum-restore when it
# is loaded (before this plugin's default when listed first), and its "another
# server is running" check counts every tmux process, including the short-lived
# `tmux set-option` continuum itself starts right after the check, so it skips
# at random. This script never races it: it waits until the config has loaded
# and no continuum or resurrect restore is running, and restores only if the
# post-restore hook has not marked this server as restored
# (@assistant-resurrect-restored, set by restore-assistant-sessions.sh).
#
# The guards continuum is meant to apply are kept, done reliably: auto-restore
# must be on, ~/tmux_no_auto_restore must not exist, and no other tmux server
# may be answering on a socket next to this one.

set -euo pipefail

restored() {
	[ -n "$(tmux show-option -gqv @assistant-resurrect-restored 2>/dev/null)" ]
}

restore_running() {
	# Snapshot first: grepping a live pipe would match grep's own argv.
	local procs
	procs=$(ps -u "$(id -u)" -o args= 2>/dev/null || true)
	case "$procs" in
	*continuum_restore.sh* | *"$restore_script"*) return 0 ;;
	esac
	return 1
}

# A server on another socket in the same directory means this one is not the
# only environment; restoring here as well would start every agent twice.
another_server_running() {
	local own sock
	own="${TMUX%%,*}"
	[ -n "$own" ] || return 1
	for sock in "${own%/*}"/*; do
		[ -S "$sock" ] && [ "$sock" != "$own" ] || continue
		tmux -S "$sock" list-sessions >/dev/null 2>&1 && return 0
	done
	return 1
}

# Wait for the config to finish loading: tmux creates the first session only
# after it, and continuum starts its own attempt while it loads.
for _ in $(seq 1 150); do
	tmux list-sessions >/dev/null 2>&1 && break
	sleep 0.2
done
sleep 2

restore_script=$(tmux show-option -gqv @resurrect-restore-script-path)
[ -n "$restore_script" ] && [ -x "$restore_script" ] || exit 0

# Let continuum's attempt (and a manual prefix + Ctrl-r) finish first.
for _ in $(seq 1 300); do
	restore_running || break
	sleep 0.2
done

restored && exit 0
[ "$(tmux show-option -gqv @continuum-restore)" = on ] || exit 0
[ ! -e "$HOME/tmux_no_auto_restore" ] || exit 0
another_server_running && exit 0

"$restore_script"
