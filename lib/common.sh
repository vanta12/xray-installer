#!/usr/bin/env bash

TMP_FILES=()
# Trojan password: 16 karakter hex (8 byte / 64-bit) — kompromi ringkas vs aman.
gen_trojan() { openssl rand -hex 8; }
# Panjang garis dekorasi adaptif lebar terminal. Dipakai menu & xray-config CLI (DRY).
# clamp ke [min,max]; kurangi lebar judul + margin; minimal 4.
_ui_dashcount() { local t=${1:-} min=${2:-40} max=${3:-120} cols n
  cols=$(tput cols 2>/dev/null || echo 80); [[ "$cols" =~ ^[0-9]+$ ]] || cols=80
  (( cols < min )) && cols=min; (( cols > max )) && cols=max
  n=$(( cols - ${#t} - 8 )); (( n < 4 )) && n=4
  printf '%s' "$n"; }
log() { printf '\033[1;32m[+]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[!]\033[0m %s\n' "$*" >&2; }
die() { printf '\033[1;31m[ERROR]\033[0m %s\n' "$*" >&2; exit 1; }
register_tmp() { TMP_FILES+=("$1"); }
cleanup_tmp() { local file; for file in "${TMP_FILES[@]:-}"; do [[ -z "$file" ]] || rm -f -- "$file"; done; }
users_lock() { exec 9>"$LOCK_FILE"; flock -x 9; }
users_lock_nb() { exec 9>"$LOCK_FILE"; flock -x -n 9 || { exec 9>&- 2>/dev/null || true; return 1; }; }
users_unlock() { flock -u 9 2>/dev/null || true; exec 9>&- 2>/dev/null || true; }
trap cleanup_tmp EXIT
