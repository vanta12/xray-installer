#!/usr/bin/env bash

install_nginx() {
  local arch dist codename keyring=/usr/share/keyrings/nginx-archive-keyring.gpg
  arch=$(dpkg --print-architecture)
  case "$arch" in amd64|arm64|i386|ppc64el|s390x) ;; *) die "Arsitektur '$arch' tidak didukung.";; esac
  . /etc/os-release
  dist=$ID; codename="${VERSION_CODENAME:-$(lsb_release -cs)}"
  local keyring_tmp; keyring_tmp=$(mktemp "${keyring}.XXXXXX")
  if curl -fsSL https://nginx.org/keys/nginx_signing.key | gpg --batch --yes --dearmor -o "$keyring_tmp"; then mv -f "$keyring_tmp" "$keyring"; chmod 0644 "$keyring"; else rm -f "$keyring_tmp"; die "Gagal mengunduh/mengubah kunci nginx."; fi
  echo "deb [signed-by=$keyring] https://nginx.org/packages/$dist/ $codename nginx" > /etc/apt/sources.list.d/nginx.list
  cat > /etc/apt/preferences.d/99nginx <<'EOF'
Package: nginx
Pin: origin nginx.org
Pin-Priority: 1000
EOF
  apt-get update -y
  apt-get install -y --no-install-recommends nginx
  rm -f /etc/nginx/conf.d/default.conf /etc/nginx/sites-enabled/default /etc/nginx/sites-available/default
  systemctl stop nginx 2>/dev/null || true
}

write_nginx_config() {
  install -d -m 0755 "$DECOY_DIR" /var/www/certbot
  cat > "$DECOY_DIR/index.html" <<'EOF'
<!DOCTYPE html><html lang="id"><head><meta charset="utf-8"><title>Selamat Datang</title></head><body><h1>Selamat Datang</h1><p>Server ini berfungsi normal.</p></body></html>
EOF
  # Nginx hanya listen di unix socket (dipanggil Xray via fallback).
  # h1.sock: decoy + webroot ACME + routing xhttp dari port 80 (http/1.1)
  # h2c.sock: routing gRPC/xhttp dari port 443 (h2)
  cat > "$NGINX_CONF" <<EOF
server {
    listen unix:$H1_SOCK proxy_protocol;
    server_name _;
    root $DECOY_DIR;
    index index.html;
    location /.well-known/acme-challenge/ {
        root /var/www/certbot;
    }
    location $P_VL_XH/ {
        proxy_pass http://127.0.0.1:$P_XH_VL;
        proxy_http_version 1.1;
        proxy_buffering off;
        proxy_request_buffering off;
        proxy_read_timeout 3600s;
        proxy_send_timeout 3600s;
        proxy_set_header Host \$host;
    }
    location $P_VM_XH/ {
        proxy_pass http://127.0.0.1:$P_XH_VM;
        proxy_http_version 1.1;
        proxy_buffering off;
        proxy_request_buffering off;
        proxy_read_timeout 3600s;
        proxy_send_timeout 3600s;
        proxy_set_header Host \$host;
    }
    location $P_TR_XH/ {
        proxy_pass http://127.0.0.1:$P_XH_TR;
        proxy_http_version 1.1;
        proxy_buffering off;
        proxy_request_buffering off;
        proxy_read_timeout 3600s;
        proxy_send_timeout 3600s;
        proxy_set_header Host \$host;
    }
    location / { try_files \$uri \$uri/ =404; }
}
server {
    listen unix:$H2C_SOCK proxy_protocol;
    http2 on;
    server_name _;
    root $DECOY_DIR;
    index index.html;
    location /$G_VL/ { grpc_pass grpc://127.0.0.1:$P_GR_VL; }
    location /$G_VM/ { grpc_pass grpc://127.0.0.1:$P_GR_VM; }
    location /$G_TR/ { grpc_pass grpc://127.0.0.1:$P_GR_TR; }
    location $P_VL_XH/ {
        proxy_pass http://127.0.0.1:$P_XH_VL;
        proxy_http_version 1.1;
        proxy_buffering off;
        proxy_request_buffering off;
        proxy_read_timeout 3600s;
        proxy_send_timeout 3600s;
        proxy_set_header Host \$host;
    }
    location $P_VM_XH/ {
        proxy_pass http://127.0.0.1:$P_XH_VM;
        proxy_http_version 1.1;
        proxy_buffering off;
        proxy_request_buffering off;
        proxy_read_timeout 3600s;
        proxy_send_timeout 3600s;
        proxy_set_header Host \$host;
    }
    location $P_TR_XH/ {
        proxy_pass http://127.0.0.1:$P_XH_TR;
        proxy_http_version 1.1;
        proxy_buffering off;
        proxy_request_buffering off;
        proxy_read_timeout 3600s;
        proxy_send_timeout 3600s;
        proxy_set_header Host \$host;
    }
    location / { try_files \$uri \$uri/ =404; }
}
EOF
  chmod 0640 "$NGINX_CONF"; chown root:www-data "$NGINX_CONF" 2>/dev/null || chmod 0640 "$NGINX_CONF"
  rm -f "$H1_SOCK" "$H2C_SOCK"
}

validate_nginx() {
  nginx -t || die "Konfigurasi nginx tidak valid."
}

start_nginx() {
  systemctl restart nginx
  systemctl is-active --quiet nginx || die "Service nginx gagal berjalan."
}
