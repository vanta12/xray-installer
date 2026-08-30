#!/usr/bin/env bash

install_runtime() {
  install -d -m 0755 "$XRAY_RUNTIME_DIR/lib" "$XRAY_RUNTIME_DIR/config"
  install -m 0644 "$ROOT"/lib/*.sh "$XRAY_RUNTIME_DIR/lib/"
  install -m 0644 "$ROOT"/config/* "$XRAY_RUNTIME_DIR/config/"
  install -m 0755 "$ROOT/bin/xray-config" /usr/local/bin/xray-config
  install -m 0755 "$ROOT/bin/menu" /usr/local/bin/menu
  install -m 0755 "$ROOT/bin/xray-cleanup" /usr/local/bin/xray-cleanup
  install -m 0755 "$ROOT/bin/uninstall" /usr/local/bin/uninstall
}
