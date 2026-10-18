#!/usr/bin/env bash
# tmux-resurrect save-command strategy: print the full command line of the
# pane's *foreground* job.
#
# Resurrect's bundled `ps` and `linux_procfs` strategies take the first child of
# the pane shell, so a shell that also has background jobs (`alacritty &`, then
# `tail -f log`) gets the background job saved as its command. The terminal's
# foreground process group (tpgid) is the job the user actually sees, and its
# leader is that job's first command. An idle shell is its own foreground group,
# for which nothing is printed, matching the bundled strategies.

PANE_PID="$1"
[ -n "$PANE_PID" ] || exit 0

fg_pgid=$(ps -o tpgid= -p "$PANE_PID" 2>/dev/null | tr -d ' ')
case "$fg_pgid" in
'' | -1 | 0 | "$PANE_PID") exit 0 ;;
esac

if [ -r "/proc/$fg_pgid/cmdline" ]; then
	# Same quoting as resurrect's linux_procfs strategy: %q keeps argv
	# boundaries (spaces, quotes) intact when the command is replayed.
	# Trailing empty args are dropped: programs that rewrite their process
	# title (pi, node CLIs) leave cmdline padded with NULs.
	xargs -0 bash -c 'a=("$0" "$@")
		while [ "${#a[@]}" -gt 1 ] && [ -z "${a[${#a[@]}-1]}" ]; do unset "a[${#a[@]}-1]"; done
		printf "%q " "${a[@]}"' <"/proc/$fg_pgid/cmdline"
else
	ps -o args= -p "$fg_pgid" 2>/dev/null
fi
