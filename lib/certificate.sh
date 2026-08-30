#!/usr/bin/env bash

validate_or_obtain_certificate() {
  local domain=$1 cert_file=$2 key_file=$3 cert_dir
  cert_dir="$(dirname "$cert_file")"
  if [[ -s "$cert_file" && -s "$key_file" ]]; then
    openssl x509 -checkend 0 -noout -in "$cert_file" >/dev/null 2>&1 \
      || die "Sertifikat untuk $domain tidak valid atau sudah kedaluwarsa: $cert_file"
    [[ -r "$cert_file" && -r "$key_file" ]] \
      || die "Sertifikat atau private key tidak dapat dibaca: $cert_dir"
    warn "Sertifikat untuk $domain sudah ada dan masih valid; dipakai apa adanya."
  else
    log "Menerbitkan sertifikat Let's Encrypt (standalone)..."
    certbot certonly --standalone --non-interactive --agree-tos \
      --register-unsafely-without-email -d "$domain" \
      || die "Penerbitan sertifikat gagal. Pastikan DNS domain mengarah ke server dan port 80 terbuka."
  fi
  [[ -s "$cert_file" && -s "$key_file" ]] || die "Sertifikat tidak ditemukan di $cert_dir"
}

# Beri user xray akses baca sertifikat via grup (tanpa CAP_DAC_READ_SEARCH).
# live/*.pem adalah symlink ke archive/; chgrp/chmod mengikuti symlink ke target.
grant_xray_cert_access() {
  local domain=$1 live archive
  live="/etc/letsencrypt/live/$domain"; archive="/etc/letsencrypt/archive/$domain"
  id -u xray >/dev/null 2>&1 || return 0
  # 0711: cukup untuk traversal ke live/<domain>/; daftar domain tidak terbaca oleh local user lain.
  chmod 0711 /etc/letsencrypt /etc/letsencrypt/live /etc/letsencrypt/archive 2>/dev/null || true
  chgrp -R xray "$live" "$archive" 2>/dev/null || true
  chmod 0750 "$live" "$archive" 2>/dev/null || true
  chmod 0640 "$live/fullchain.pem" "$live/privkey.pem" 2>/dev/null || true
}
