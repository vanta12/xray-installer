#!/usr/bin/env bash

vmess_link() {
  local label=${1:-} net=${2:-} port=${3:-} path=${4:-} alpn=${5:-}
  local payload fp='' host=''
  # vmess-tcp butuh ALPN kustom "vmess" yang hanya bisa dikirim via Go TLS standar (fingerprint=unsafe);
  # transport lain cukup fingerprint default uTLS.
  [[ -n "$alpn" ]] && fp=unsafe
  # host diisi domain untuk ws/httpupgrade — sebagian klien (v2rayN, Streisand)
  # menuntut header Host eksplisit agar handshake ws berhasil.
  case "$net" in ws|httpupgrade) host="$DOMAIN";; esac
  payload="$(jq -cn --arg ps "$label" --arg add "$DOMAIN" --arg id "$USER_UUID" --argjson port "$port" --arg net "$net" --arg path "$path" --arg tls "$USER_TLS" --arg sni "$DOMAIN" --arg alpn "$alpn" --arg fp "$fp" --arg host "$host" '({v:"2",ps:$ps,add:$add,port:$port,id:$id,aid:"0",scy:"auto",net:$net,type:"",host:$host,path:$path,tls:$tls,sni:$sni,alpn:$alpn} + (if $fp != "" then {fp:$fp} else {} end))')"
  printf '  %-14s: vmess://%s\n' "$label" "$(printf '%s' "$payload" | base64 -w0)"
}

_ln_sec() { # separator section (tanpa warna, aman untuk CLI xray-config); DRY via _ui_dashcount.
  local t=${1:-} n; n=$(_ui_dashcount "$t" 40 120)
  printf '  ── %s %s\n' "$t" "$(printf '─%.0s' $(seq 1 "$n"))"
}

print_user_links() {
  local name=${1:-}; [[ -n "$name" ]] || die "usage: xray-config links <nama-user>"
  xray_load_site
  local user protocols uuid trojan
  user="$(jq -c --arg n "$name" '.users[] | select(.name==$n)' "$USERS_FILE" 2>/dev/null || true)"; [[ -n "$user" ]] || die "User '$name' tidak ditemukan."
  uuid="$(jq -r '.uuid' <<<"$user")"; trojan="$(jq -r '.trojan' <<<"$user")"; protocols="$(jq -r '.protocols[]' <<<"$user")"
  # vmess_link memakai global USER_UUID/USER_TLS (valid di bawah set -u).
  USER_UUID="$uuid"; USER_TLS=tls
  printf '\n  %-9s: %s\n  %-9s: %s\n  %-9s: %s\n  %-9s: %s\n' 'Profile' "$name" 'Domain' "$DOMAIN" 'UUID' "$uuid" 'Trojan' "$trojan"
  if grep -qx vless <<<"$protocols"; then
    _ln_sec 'VLESS · Port 443 (TLS)'
    printf '  %-14s: vless://%s@%s:443?security=tls&type=tcp&alpn=http/1.1&sni=%s#vless-tcp\n' 'tcp' "$uuid" "$DOMAIN" "$DOMAIN"
    printf '  %-14s: vless://%s@%s:443?security=tls&type=ws&path=%s&sni=%s#vless-ws\n' 'ws' "$uuid" "$DOMAIN" "$P_VL_WS" "$DOMAIN"
    printf '  %-14s: vless://%s@%s:443?security=tls&type=httpupgrade&path=%s&sni=%s#vless-httpupgrade\n' 'httpupgrade' "$uuid" "$DOMAIN" "$P_VL_HU" "$DOMAIN"
    printf '  %-14s: vless://%s@%s:443?security=tls&type=xhttp&path=%s&sni=%s#vless-xhttp\n' 'xhttp' "$uuid" "$DOMAIN" "$P_VL_XH" "$DOMAIN"
    printf '  %-14s: vless://%s@%s:443?security=tls&type=grpc&serviceName=%s&sni=%s#vless-grpc\n' 'grpc' "$uuid" "$DOMAIN" "$G_VL" "$DOMAIN"
    _ln_sec 'VLESS · Port 80 (HTTP)'
    printf '  %-14s: vless://%s@%s:80?security=none&type=ws&path=%s#vless-ws-80\n' 'ws' "$uuid" "$DOMAIN" "$P_VL_WS"
    printf '  %-14s: vless://%s@%s:80?security=none&type=httpupgrade&path=%s#vless-httpupgrade-80\n' 'httpupgrade' "$uuid" "$DOMAIN" "$P_VL_HU"
    printf '  %-14s: vless://%s@%s:80?security=none&type=xhttp&path=%s#vless-xhttp-80\n' 'xhttp' "$uuid" "$DOMAIN" "$P_VL_XH"
  fi
  if grep -qx vmess <<<"$protocols"; then
    _ln_sec 'VMess · Port 443 (TLS)'
    vmess_link vmess-tcp tcp 443 '' vmess; vmess_link vmess-ws ws 443 "$P_VM_WS" ''; vmess_link vmess-httpupgrade httpupgrade 443 "$P_VM_HU" ''; vmess_link vmess-xhttp xhttp 443 "$P_VM_XH" ''; vmess_link vmess-grpc grpc 443 "$G_VM" ''
    _ln_sec 'VMess · Port 80 (HTTP)'; USER_TLS=''
    vmess_link vmess-ws-80 ws 80 "$P_VM_WS" ''; vmess_link vmess-httpupgrade-80 httpupgrade 80 "$P_VM_HU" ''; vmess_link vmess-xhttp-80 xhttp 80 "$P_VM_XH" ''
  fi
  if grep -qx trojan <<<"$protocols"; then
    _ln_sec 'Trojan · Port 443 (TLS)'
    printf '  %-14s: trojan://%s@%s:443?security=tls&type=tcp&alpn=h2&sni=%s#trojan-tcp\n' 'tcp' "$trojan" "$DOMAIN" "$DOMAIN"
    printf '  %-14s: trojan://%s@%s:443?security=tls&type=ws&path=%s&sni=%s#trojan-ws\n' 'ws' "$trojan" "$DOMAIN" "$P_TR_WS" "$DOMAIN"
    printf '  %-14s: trojan://%s@%s:443?security=tls&type=httpupgrade&path=%s&sni=%s#trojan-httpupgrade\n' 'httpupgrade' "$trojan" "$DOMAIN" "$P_TR_HU" "$DOMAIN"
    printf '  %-14s: trojan://%s@%s:443?security=tls&type=xhttp&path=%s&sni=%s#trojan-xhttp\n' 'xhttp' "$trojan" "$DOMAIN" "$P_TR_XH" "$DOMAIN"
    printf '  %-14s: trojan://%s@%s:443?security=tls&type=grpc&serviceName=%s&sni=%s#trojan-grpc\n' 'grpc' "$trojan" "$DOMAIN" "$G_TR" "$DOMAIN"
    _ln_sec 'Trojan · Port 80 (HTTP)'
    printf '  %-14s: trojan://%s@%s:80?security=none&type=ws&path=%s#trojan-ws-80\n' 'ws' "$trojan" "$DOMAIN" "$P_TR_WS"
    printf '  %-14s: trojan://%s@%s:80?security=none&type=httpupgrade&path=%s#trojan-httpupgrade-80\n' 'httpupgrade' "$trojan" "$DOMAIN" "$P_TR_HU"
    printf '  %-14s: trojan://%s@%s:80?security=none&type=xhttp&path=%s#trojan-xhttp-80\n' 'xhttp' "$trojan" "$DOMAIN" "$P_TR_XH"
  fi
}
