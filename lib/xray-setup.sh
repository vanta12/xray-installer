#!/usr/bin/env bash

install_xray() {
  local installer
  installer=$(mktemp /tmp/xray-install-release.XXXXXX.sh); register_tmp "$installer"
  curl -fsSL -o "$installer" https://github.com/XTLS/Xray-install/raw/main/install-release.sh
  bash "$installer" install
  rm -f "$installer"
  [[ -x "$XRAY_BIN" ]] || die 'Binary Xray tidak ditemukan.'
  id -u xray >/dev/null 2>&1 || useradd --system --no-create-home --shell /usr/sbin/nologin xray
  install -d /etc/systemd/system/xray.service.d
  cat > /etc/systemd/system/xray.service.d/20-user.conf <<'EOF'
[Service]
User=xray
CapabilityBoundingSet=CAP_NET_BIND_SERVICE
AmbientCapabilities=CAP_NET_BIND_SERVICE
NoNewPrivileges=true
EOF
  install -d -m 0755 "$XRAY_DIR"
  chown -R xray:xray /var/log/xray
  systemctl daemon-reload
  systemctl stop "$SERVICE" 2>/dev/null || true
}

generate_site_parameters() {
  local r p; r() { openssl rand -hex 6; }
  # Port internal dari CSPRNG (bukan $RANDOM yang predictable): openssl rand -hex 4 di-mask ke range 40000-60000.
  PORT_USED=(); pick_port() { while :; do p=$((40000 + 16#$(openssl rand -hex 4) % 20001)); [[ " ${PORT_USED[*]} " != *" $p "* ]] && PORT_USED+=("$p") && printf '%s' "$p" && return; done; }
  for key in TC_VM TC_TR WS_VL WS_VM WS_TR HU_VL HU_VM HU_TR XH_VL XH_VM XH_TR GR_VL GR_VM GR_TR; do printf -v "P_$key" '%s' "$(pick_port)"; done
  P_VL_WS="/$(r)"; P_VM_WS="/$(r)"; P_TR_WS="/$(r)"; P_VL_HU="/$(r)"; P_VM_HU="/$(r)"; P_TR_HU="/$(r)"; P_VL_XH="/$(r)"; P_VM_XH="/$(r)"; P_TR_XH="/$(r)"; G_VL=$(r); G_VM=$(r); G_TR=$(r)
}
