#!/usr/bin/env bash

setup_renewal_hook() {
  install -d /etc/letsencrypt/renewal-hooks/deploy
  cat > /etc/letsencrypt/renewal-hooks/deploy/xray-reload.sh <<'EOF'
#!/usr/bin/env bash
if [[ -n "${RENEWED_DOMAIN:-}" ]]; then
  chgrp -R xray "/etc/letsencrypt/live/$RENEWED_DOMAIN" "/etc/letsencrypt/archive/$RENEWED_DOMAIN" 2>/dev/null || true
  chmod 0750 "/etc/letsencrypt/live/$RENEWED_DOMAIN" "/etc/letsencrypt/archive/$RENEWED_DOMAIN" 2>/dev/null || true
  chmod 0640 "/etc/letsencrypt/live/$RENEWED_DOMAIN/fullchain.pem" "/etc/letsencrypt/live/$RENEWED_DOMAIN/privkey.pem" 2>/dev/null || true
fi
systemctl reload xray.service || systemctl restart xray.service
EOF
  chmod 0755 /etc/letsencrypt/renewal-hooks/deploy/xray-reload.sh
  # Renewal via webroot (challenge dilayani nginx h1.sock dari /var/www/certbot):
  # Xray tetap pegang port 80, tidak perlu stop/start service saat renewal.
  local renewal="/etc/letsencrypt/renewal/$DOMAIN.conf"
  if [[ -f "$renewal" ]]; then
    sed -i '/^pre_hook =/d; /^post_hook =/d; /^authenticator =/d; /^webroot_path =/d; /^\[\[webroot_map\]\]/d' "$renewal"
    printf 'authenticator = webroot\nwebroot_path = /var/www/certbot,\n[[webroot_map]]\n' >> "$renewal"
  fi
}

verify_systemd_units() {
  systemd-analyze verify "$@" || die "Unit systemd tidak valid."
}

setup_cleanup_timer() {
  install -m 0644 "$ROOT/config/xray-cleanup.service" /etc/systemd/system/xray-cleanup.service
  install -m 0644 "$ROOT/config/xray-cleanup.timer" /etc/systemd/system/xray-cleanup.timer
  systemctl daemon-reload
  verify_systemd_units /etc/systemd/system/xray-cleanup.service /etc/systemd/system/xray-cleanup.timer
  systemctl enable --now xray-cleanup.timer
  systemctl is-active --quiet xray-cleanup.timer || die 'Timer cleanup gagal aktif.'
}
