#!/usr/bin/env bash

require_root() {
  [[ $EUID -eq 0 ]] || die "Jalankan sebagai root: sudo bash $0"
}

require_systemd() {
  command -v systemctl >/dev/null || die "systemd diperlukan."
}

require_debian() {
  . /etc/os-release
  [[ "$ID" == "ubuntu" || "$ID" == "debian" || "${ID_LIKE:-}" == *debian* ]] || die "Script ini untuk Ubuntu/Debian."
}

validate_domain() {
  local domain=$1
  [[ "$domain" =~ ^[A-Za-z0-9]([A-Za-z0-9-]{0,61}[A-Za-z0-9])?(\.[A-Za-z0-9]([A-Za-z0-9-]{0,61}[A-Za-z0-9])?)+$ ]] || die "Format domain tidak valid (butuh FQDN, mis. vpn.example.com)."
}

# Range IPv4 publik Cloudflare (subset yang umum dipakai untuk proxied record).
_cf_ranges='^(104\.(16|17|18|19|2[0-7])\.|172\.(6[4-9]|7[0-2])\.|131\.0\.72\.|190\.93\.2[45][0-9]\.|198\.41\.(12[89]|19[02]|2[0-3][0-9])\.|108\.162\.19[24]\.|162\.158\.)'

validate_dns() {
  local domain=$1 ip_pub dns_ip
  ip_pub="$(curl -fsS -m 10 https://api.ipify.org 2>/dev/null || curl -fsS -m 10 https://ipv4.icanhazip.com 2>/dev/null || true)"
  dns_ip="$(getent ahostsv4 "$domain" 2>/dev/null | awk 'NR==1{print $1}')"
  [[ -n "$dns_ip" ]] || die "Domain '$domain' tidak terselesaikan via DNS. Pastikan A/AAAA record mengarah ke IP server ini."
  if [[ -n "$ip_pub" && "$dns_ip" != "$ip_pub" ]]; then
    warn "A record '$domain' = $dns_ip, tetapi IP publik server = $ip_pub."
    if printf '%s\n' "$dns_ip" | grep -qE "$_cf_ranges"; then
      die "DNS '$domain' -> $dns_ip terdeteksi milik Cloudflare. Xray butuh A record DNS-only (grey-cloud) langsung ke IP server ($ip_pub)."
    fi
    die "DNS '$domain' tidak mengarah ke IP server ini ($dns_ip != $ip_pub). Jika domain di-balik CDN/proxy, set ke DNS-only. Perbaiki A record lalu jalankan ulang."
  fi
  log "DNS '$domain' -> $dns_ip (searah IP server)."
}
