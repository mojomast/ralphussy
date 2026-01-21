#!/usr/bin/env bash

# Optional shell helpers for ralph2.
#
# Usage (bash):
#   source /home/mojo/projects/opencode2/ralph-refactor/ralph-bashrc.sh
#
# This file is intentionally opt-in; it does not modify your shell unless you
# source it.

if [ -n "${RALPH_BASHRC_LOADED-}" ]; then
  return 0
fi
RALPH_BASHRC_LOADED=1

ralph_attach() {
  command ralph2 --attach "$@"
}

ralph_stop() {
  command ralph2 --stop "$@"
}

ralph_runs() {
  command ralph2 --runs "$@"
}

ralph_status() {
  command ralph2 --status "$@"
}

# Prompt segment helper.
#
# Prints a short indicator when a background run is active, e.g. "[ralph:20260121_123456]".
# It checks ~/.ralph/runs/current and verifies the pid is still alive.
ralph_prompt_segment() {
  local runs_dir="${RALPH_DIR:-$HOME/.ralph}/runs"
  local current_file="$runs_dir/current"
  [ -f "$current_file" ] || return 0

  local run_id=""
  run_id=$(cat "$current_file" 2>/dev/null || true)
  [ -n "$run_id" ] || return 0

  local pid_file="$runs_dir/run_${run_id}.pid"
  [ -f "$pid_file" ] || return 0

  local pid=""
  pid=$(cat "$pid_file" 2>/dev/null || true)
  [ -n "$pid" ] || return 0

  if kill -0 "$pid" 2>/dev/null; then
    printf '[ralph:%s]' "$run_id"
  fi
}
