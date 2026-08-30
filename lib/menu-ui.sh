#!/usr/bin/env bash

menu_banner() {
  [[ -t 1 ]] && clear 2>/dev/null || true
  local dom ip xver cert_exp nusers ram_txt upt_txt st_dot st_txt
  local cols pad_div pad_sub barL barR

  dom="$(jq -r '.site.domain // "-"' "$USERS_FILE" 2>/dev/null)"
  ip="$(hostname -I 2>/dev/null | awk '{print $1}')"; [[ -n "$ip" ]] || ip='-'
  xver="$(xray version 2>/dev/null | head -1 | awk '{print $2}' || true)"; [[ -n "$xver" ]] || xver='?'
  cert_exp="$(openssl x509 -enddate -noout -in "$(jq -r '.site.cert_file // empty' "$USERS_FILE" 2>/dev/null)" 2>/dev/null | sed 's/notAfter=//' || true)"
  [[ -n "$cert_exp" ]] && cert_exp="$(date -d "$cert_exp" +%Y-%m-%d 2>/dev/null || true)" || cert_exp='-'
  nusers="$(jq '[.users[] | select(.name != "admin")] | length' "$USERS_FILE" 2>/dev/null)"

  if systemctl is-active --quiet xray.service 2>/dev/null; then
    st_dot="${UI_G}●${UI_R}"; st_txt="${UI_G}Active${UI_R} (xray v${xver})"
  else
    st_dot="${UI_Rd}●${UI_R}"; st_txt="${UI_Rd}Inactive${UI_R}"
  fi

  local up_s up_h up_m
  up_s=$(awk '{print int($1)}' /proc/uptime 2>/dev/null); up_s=${up_s:-0}
  up_h=$((up_s/3600)); up_m=$(((up_s%3600)/60))
  if (( up_h >= 1 )); then upt_txt="${up_h}h ${up_m}m"; else upt_txt="${up_m}m"; fi
  ram_txt="$(free -m 2>/dev/null | awk '/Mem:/{printf "%d/%d MB",$3,$2}')"; [[ -n "$ram_txt" ]] || ram_txt='-'

  # Aksen adaptif: lebar garis menyesuaikan kolom terminal.
  cols=$(tput cols 2>/dev/null || echo 80); ! [[ "$cols" =~ ^[0-9]+$ ]] && cols=80
  (( cols < 50 )) && cols=50; (( cols > 140 )) && cols=140
  barL=$(printf '═%.0s' $(seq 1 $(( (cols - 20) / 2 ))))
  barR=$(printf '═%.0s' $(seq 1 $(( cols - 20 - ${#barL} ))))
  printf '\n  %s%s  %sXRAY MANAGER%s  %s%s%s\n' "$UI_C" "$barL" "$UI_G$UI_K" "$UI_R" "$UI_C" "$barR" "$UI_R"
  pad_sub=$(( (cols - 23) / 2 )); (( pad_sub < 0 )) && pad_sub=0
  printf '%*s%sSecure Proxy Autoscript%s\n' "$pad_sub" '' "$UI_D" "$UI_R"
  pad_div=$(( cols - 4 )); (( pad_div < 0 )) && pad_div=0
  printf '  %s%s%s\n\n' "$UI_C" "$(printf '─%.0s' $(seq 1 "$pad_div"))" "$UI_R"
  printf '  %-9s %s\n' 'Server :' "$dom  ($ip)"
  printf '  %-9s %s%s %s\n' 'Status :' "$st_dot" "$UI_R" "$st_txt"
  printf '  %-9s %-16s %-8s %s\n' 'Users :' "$nusers" 'Cert :' "s.d. $cert_exp"
  printf '  %-9s %-16s %-8s %s\n\n' 'System :' "$ram_txt" 'Uptime :' "$upt_txt"
}
# Warna tema (dipakai banner, tabel, dan daftar menu).
readonly UI_C=$'\033[1;36m' UI_G=$'\033[1;32m' UI_Rd=$'\033[1;31m' UI_D=$'\033[90m' UI_K=$'\033[1m' UI_R=$'\033[0m'

# ── Helper UI kecil: pesan & judul konsisten, adaptif lebar terminal. ──
ui_ok()  { printf '  %s✓%s %s\n' "$UI_G" "$UI_R" "$1"; }
# ui_err/ui_note ke stderr agar tak bocor ke stdout saat dipanggil dalam $(...) (lihat pick_user).
ui_err() { printf '  %s✗ %s%s\n' "$UI_Rd" "$1" "$UI_R" >&2; }
ui_note(){ printf '  %s%s%s\n' "$UI_D" "$1" "$UI_R" >&2; }
ui_info(){ printf '  %s%s%s\n' "$UI_C" "$1" "$UI_R"; }
# Pause menunggu Enter. Instruksi dicetak via printf (bukan read -p) agar selalu tampil
# meski stdin bukan terminal (pipe/otomasi): read -p menyembunyikan prompt saat stdin!=tty.
ui_pause(){ printf '  %s[Tekan Enter untuk kembali ke menu] %s' "$UI_D" "$UI_R" >&2; read -r _ || true; }
# true bila input = perintah batal/kembali.
ui_cancel(){ [[ "${1,,}" == '00' ]] && return 0; return 1; }
# Judul section: "── TITLE ─────” selebar terminal.
ui_panel(){
  local t=${1:-} n; n=$(_ui_dashcount "$t" 40 120)
  printf '  %s── %s%s%s %s%s%s\n' "$UI_C" "$UI_G$UI_K" "$t" "$UI_R" "$UI_C" "$(printf '─%.0s' $(seq 1 "$n"))" "$UI_R"
}
menu_update_users() {
  local candidate=${1:-} original
  original=$(mktemp "${USERS_FILE}.bak.XXXXXX"); register_tmp "$original"; chmod 0600 "$original"
  users_lock; cp "$USERS_FILE" "$original"; mv -f "$candidate" "$USERS_FILE"
  if ! "$XRAY_CONFIG" build; then mv -f "$original" "$USERS_FILE"; users_unlock; die "Build konfigurasi gagal."; fi
  rm -f "$original"; chmod 0600 "$USERS_FILE"; reload_xray; users_unlock
}
