# Shared helpers for AetherOS user-facing launchers. Sourced by /bin/sh scripts.
# shellcheck shell=sh

aether_notify() {
  title=$1; body=${2:-}
  if command -v notify-send >/dev/null 2>&1; then
    notify-send -a AetherOS "$title" "$body" 2>/dev/null || true
  else
    printf '%s: %s\n' "$title" "$body" >&2
  fi
}

# aether_confirm TITLE MESSAGE [--yes]
# Returns 0 only on explicit approval. Never silently executes a downloaded
# executable just because it was double-clicked.
aether_confirm() {
  _title=$1; _msg=$2; _assume=${3:-}
  [ "$_assume" = "--yes" ] && return 0
  [ "${AETHER_TRUST:-0}" = "1" ] && return 0

  if command -v zenity >/dev/null 2>&1; then
    zenity --question --title="$_title" --width=420 --text="$_msg" 2>/dev/null
    return $?
  fi
  if command -v fuzzel >/dev/null 2>&1; then
    _choice=$(printf 'Cancel\nRun\n' | fuzzel --dmenu --prompt "  $_title  " --lines 2 --width 40) || return 1
    [ "$_choice" = "Run" ]
    return $?
  fi
  if [ -t 0 ]; then
    printf '%s\n%s\nRun? [y/N] ' "$_title" "$_msg"
    read -r _answer
    case "$_answer" in y|Y|yes|YES) return 0 ;; *) return 1 ;; esac
  fi
  return 1
}
