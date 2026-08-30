#!/usr/bin/env bash

xray_load_site() {
  DOMAIN="$(jq -r '.site.domain // empty' "$USERS_FILE")"; [[ -n "$DOMAIN" ]] || die "site.domain tidak ada di users.json."
  CERT_FILE="$(jq -r '.site.cert_file' "$USERS_FILE")"; KEY_FILE="$(jq -r '.site.key_file' "$USERS_FILE")"; H1_SOCK="$(jq -r '.site.h1_sock' "$USERS_FILE")"; H2C_SOCK="$(jq -r '.site.h2c_sock' "$USERS_FILE")"
  for key in tc_vm tc_tr ws_vl ws_vm ws_tr hu_vl hu_vm hu_tr xh_vl xh_vm xh_tr gr_vl gr_vm gr_tr; do printf -v "P_${key^^}" '%s' "$(jq -r ".site.ports.$key" "$USERS_FILE")"; done
  for key in vl_ws vm_ws tr_ws vl_hu vm_hu tr_hu vl_xh vm_xh tr_xh; do printf -v "P_${key^^}" '%s' "$(jq -r ".site.paths.$key" "$USERS_FILE")"; done
  G_VL="$(jq -r '.site.grpc.vl' "$USERS_FILE")"; G_VM="$(jq -r '.site.grpc.vm' "$USERS_FILE")"; G_TR="$(jq -r '.site.grpc.tr' "$USERS_FILE")"
}

xray_load_clients() {
  VLESS_CLIENTS="$(jq -c '[.users[] | select(.protocols | index("vless")) | {id:.uuid}]' "$USERS_FILE")"
  VMESS_CLIENTS="$(jq -c '[.users[] | select(.protocols | index("vmess")) | {id:.uuid,alterId:0,security:"auto"}]' "$USERS_FILE")"
  TROJAN_CLIENTS="$(jq -c '[.users[] | select(.protocols | index("trojan")) | {password:.trojan}]' "$USERS_FILE")"
  vless_settings="$(jq -cn --argjson c "$VLESS_CLIENTS" '{clients:$c,decryption:"none"}')"; vmess_settings="$(jq -cn --argjson c "$VMESS_CLIENTS" '{clients:$c}')"; trojan_settings="$(jq -cn --argjson c "$TROJAN_CLIENTS" '{clients:$c}')"
}

xray_stream_inbound() {
  local net=$1 port=$2 protocol=$3 settings=$4 path=$5
  # CATATAN: xhttp inbound TIDAK memakai acceptProxyProtocol — sengaja.
  # Xray -> nginx memakai xver:2 (nginx MENERIMA PROXY protocol), tapi nginx ->
  # inbound xhttp via proxy_pass TIDAK mengirim header PROXY protocol (tanpa
  # 'proxy_protocol on'). Jika acceptProxyProtocol:true ditambahkan di sini
  # "biar konsisten" dengan ws/httpupgrade, SEMUA koneksi xhttp langsung ditolak.
  # Jangan ubah tanpa membaca lib/nginx-setup.sh dulu.
  case "$net" in
    ws) jq -cn --arg listen 127.0.0.1 --argjson port "$port" --arg protocol "$protocol" --argjson settings "$settings" --arg path "$path" '{listen:$listen,port:$port,protocol:$protocol,settings:$settings,streamSettings:{network:"ws",security:"none",wsSettings:{acceptProxyProtocol:true,path:$path}}}';;
    httpupgrade) jq -cn --arg listen 127.0.0.1 --argjson port "$port" --arg protocol "$protocol" --argjson settings "$settings" --arg path "$path" '{listen:$listen,port:$port,protocol:$protocol,settings:$settings,streamSettings:{network:"httpupgrade",security:"none",httpupgradeSettings:{acceptProxyProtocol:true,path:$path}}}';;
    xhttp) jq -cn --arg listen 127.0.0.1 --argjson port "$port" --arg protocol "$protocol" --argjson settings "$settings" --arg path "$path" '{listen:$listen,port:$port,protocol:$protocol,settings:$settings,streamSettings:{network:"xhttp",security:"none",xhttpSettings:{path:$path}}}';;
  esac
}

xray_tc_inbound() { jq -cn --arg listen 127.0.0.1 --argjson port "$1" --arg protocol "$2" --argjson settings "$3" '{listen:$listen,port:$port,protocol:$protocol,settings:$settings,streamSettings:{network:"tcp",security:"none",tcpSettings:{acceptProxyProtocol:true}}}'; }
xray_gr_inbound() { jq -cn --arg listen 127.0.0.1 --argjson port "$1" --arg protocol "$2" --argjson settings "$3" --arg name "$4" '{listen:$listen,port:$port,protocol:$protocol,settings:$settings,streamSettings:{network:"grpc",security:"none",grpcSettings:{serviceName:$name}}}'; }
xray_fallback() { local dest=$1 path=${2:-} alpn=${3:-}; if [[ -n "$path" && -n "$alpn" ]]; then jq -cn --arg path "$path" --arg alpn "$alpn" --arg dest "$dest" '{path:$path,alpn:$alpn,dest:$dest,xver:2}'; elif [[ -n "$path" ]]; then jq -cn --arg path "$path" --arg dest "$dest" '{path:$path,dest:$dest,xver:2}'; elif [[ -n "$alpn" ]]; then jq -cn --arg alpn "$alpn" --arg dest "$dest" '{alpn:$alpn,dest:$dest,xver:2}'; else jq -cn --arg dest "$dest" '{dest:$dest,xver:2}'; fi; }

build_fallbacks() {
  local with_alpn=${1:-0} fb='[]' args dest path alpn
  if [[ "$with_alpn" -eq 1 ]]; then
    for args in "127.0.0.1:$P_TC_VM||vmess" "127.0.0.1:$P_TC_TR||h2"; do
      IFS='|' read -r dest path alpn <<< "$args"; fb="$(jq -c --argjson a "$(xray_fallback "$dest" "$path" "$alpn")" '. + [$a]' <<<"$fb")"
    done
  fi
  for args in "127.0.0.1:$P_WS_VL|$P_VL_WS|" "127.0.0.1:$P_WS_VM|$P_VM_WS|" "127.0.0.1:$P_WS_TR|$P_TR_WS|" "127.0.0.1:$P_HU_VL|$P_VL_HU|" "127.0.0.1:$P_HU_VM|$P_VM_HU|" "127.0.0.1:$P_HU_TR|$P_TR_HU|" "$H1_SOCK||"; do
    IFS='|' read -r dest path alpn <<< "$args"; fb="$(jq -c --argjson a "$(xray_fallback "$dest" "$path" "$alpn")" '. + [$a]' <<<"$fb")"
  done
  printf '%s' "$fb"
}

build_xray_config() {
  xray_load_site; xray_load_clients
  TLS="$(jq -cn --arg cert "$CERT_FILE" --arg key "$KEY_FILE" '{security:"tls",tlsSettings:{certificates:[{certificateFile:$cert,keyFile:$key}],alpn:["h2","http/1.1","vmess"],minVersion:"1.2"}}')"
  INBOUNDS='[]'; add_inbound() { INBOUNDS="$(jq -c --argjson x "$1" '. + [$x]' <<<"$INBOUNDS")"; }
  FALLBACKS="$(build_fallbacks 1)"
  add_inbound "$(jq -cn --argjson tls "$TLS" --argjson settings "$vless_settings" --argjson fallbacks "$FALLBACKS" '{listen:"0.0.0.0",port:443,protocol:"vless",settings:($settings+{fallbacks:$fallbacks}),streamSettings:($tls+{network:"tcp"})}')"
  FB80="$(build_fallbacks 0)"
  add_inbound "$(jq -cn --argjson settings "$vless_settings" --argjson fallbacks "$FB80" '{listen:"0.0.0.0",port:80,protocol:"vless",settings:($settings+{fallbacks:$fallbacks}),streamSettings:{network:"tcp",security:"none"}}')"
  add_inbound "$(xray_tc_inbound "$P_TC_VM" vmess "$vmess_settings")"; TROJAN_TC="$(jq -cn --argjson s "$trojan_settings" --arg h2c "$H2C_SOCK" '{clients:$s.clients,fallbacks:[{dest:$h2c,xver:2}]}')"; add_inbound "$(xray_tc_inbound "$P_TC_TR" trojan "$TROJAN_TC")"
  add_inbound "$(xray_stream_inbound ws "$P_WS_VL" vless "$vless_settings" "$P_VL_WS")"; add_inbound "$(xray_stream_inbound ws "$P_WS_VM" vmess "$vmess_settings" "$P_VM_WS")"; add_inbound "$(xray_stream_inbound ws "$P_WS_TR" trojan "$trojan_settings" "$P_TR_WS")"
  add_inbound "$(xray_stream_inbound httpupgrade "$P_HU_VL" vless "$vless_settings" "$P_VL_HU")"; add_inbound "$(xray_stream_inbound httpupgrade "$P_HU_VM" vmess "$vmess_settings" "$P_VM_HU")"; add_inbound "$(xray_stream_inbound httpupgrade "$P_HU_TR" trojan "$trojan_settings" "$P_TR_HU")"
  add_inbound "$(xray_stream_inbound xhttp "$P_XH_VL" vless "$vless_settings" "$P_VL_XH")"; add_inbound "$(xray_stream_inbound xhttp "$P_XH_VM" vmess "$vmess_settings" "$P_VM_XH")"; add_inbound "$(xray_stream_inbound xhttp "$P_XH_TR" trojan "$trojan_settings" "$P_TR_XH")"
  add_inbound "$(xray_gr_inbound "$P_GR_VL" vless "$vless_settings" "$G_VL")"; add_inbound "$(xray_gr_inbound "$P_GR_VM" vmess "$vmess_settings" "$G_VM")"; add_inbound "$(xray_gr_inbound "$P_GR_TR" trojan "$trojan_settings" "$G_TR")"
  install -d "$(dirname "$CONFIG")"
  local tmp_config; tmp_config=$(mktemp "${CONFIG}.tmp.XXXXXX.json"); register_tmp "$tmp_config"; jq -n --argjson inbounds "$INBOUNDS" '{log:{loglevel:"warning"},inbounds:$inbounds,outbounds:[{protocol:"freedom",settings:{}}]}' > "$tmp_config"
  [[ -x "$XRAY_BIN" ]] || die "Binary Xray tidak ditemukan: $XRAY_BIN"
  "$XRAY_BIN" run -test -config "$tmp_config" >/dev/null 2>&1 || die "config.json tidak valid."
  if id -u xray >/dev/null 2>&1 && getent group xray >/dev/null 2>&1; then chown xray:xray "$tmp_config"; else chmod 0640 "$tmp_config"; fi
  chmod 0640 "$tmp_config"; mv -f "$tmp_config" "$CONFIG"
  printf 'OK: %s dibangun dari %s\n' "$CONFIG" "$USERS_FILE"
}
