#!/usr/bin/env bash

install_dependencies() {
  export DEBIAN_FRONTEND=noninteractive
  apt-get update -y || die "apt-get update gagal."
  apt-get install -y --no-install-recommends curl openssl ca-certificates jq gpg certbot iproute2 lsb-release || die "apt-get install gagal."
}

configure_timezone() {
  timedatectl set-timezone Asia/Jakarta
}

configure_ipv4_only() {
  [[ -e /proc/sys/net/ipv6/conf/all/disable_ipv6 ]] || return 0
  cat > /etc/sysctl.d/99-disable-ipv6.conf <<'EOF'
net.ipv6.conf.all.disable_ipv6 = 1
net.ipv6.conf.default.disable_ipv6 = 1
net.ipv6.conf.lo.disable_ipv6 = 1
EOF
  sysctl --system >/dev/null 2>&1 || sysctl -p /etc/sysctl.d/99-disable-ipv6.conf >/dev/null 2>&1 || warn 'Gagal menerapkan sysctl IPv6.'
}
