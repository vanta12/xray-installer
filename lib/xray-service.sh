#!/usr/bin/env bash
reload_xray() {
  if ! systemctl reload xray.service 2>/dev/null && ! systemctl restart xray.service 2>/dev/null; then die "Reload/restart Xray gagal."; fi
  systemctl is-active --quiet xray.service || die "Xray tidak aktif setelah reload/restart."
}
validate_xray_runtime() {
  local i=0
  systemctl is-active --quiet xray.service || die "Service Xray tidak aktif."
  while (( i < 20 )); do
    ss -ltnp 2>/dev/null | grep -Eq ':80\s' && ss -ltnp 2>/dev/null | grep -Eq ':443\s' && [[ -S "$H1_SOCK" ]] && [[ -S "$H2C_SOCK" ]] && return 0
    sleep 0.5; i=$((i + 1))
  done
  ss -ltnp 2>/dev/null | grep -Eq ':80\s' || die "Xray tidak mendengarkan pada port 80."
  ss -ltnp 2>/dev/null | grep -Eq ':443\s' || die "Xray tidak mendengarkan pada port 443."
  [[ -S "$H1_SOCK" ]] || die "Socket Nginx h1 tidak ditemukan."
  [[ -S "$H2C_SOCK" ]] || die "Socket Nginx h2c tidak ditemukan."
}
