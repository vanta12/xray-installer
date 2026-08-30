#!/usr/bin/env bash

users_validate() {
  [[ -f "$USERS_FILE" ]] || die "users.json tidak ada: $USERS_FILE"
  jq -e '
    (.site | type == "object")
    and ((.site.domain|type)=="string") and (.site.domain|length>0)
    and ((.site.cert_file|type)=="string") and ((.site.key_file|type)=="string")
    and ((.site.ports|type)=="object") and ([.site.ports[]|type=="number"]|all)
    and ((.site.paths|type)=="object") and ((.site.grpc|type)=="object")
    and (.users | type == "array") and (.users | length > 0)
    and all(.users[]; (.name|type=="string") and (.uuid|type=="string") and (.trojan|type=="string") and (.protocols|type=="array") and ((.expires == null) or (.expires|type=="string")))
  ' "$USERS_FILE" >/dev/null || die "Format users.json tidak valid."
}
# Prune user expired ke PRUNE_TMP — TIDAK commit. Pemanggil (xray-cleanup) wajib build dulu lalu mv.
# rc: 0=berubah, 1=tanpa perubahan. Admin selalu dipertahankan; expires hanya string/null.
users_prune_expired() {
  local today tmp; today=$(TZ=Asia/Jakarta date +%F)
  tmp=$(mktemp "${USERS_FILE}.prune.XXXXXX"); register_tmp "$tmp"
  jq --arg today "$today" '.users |= map(select(.name=="admin" or (.expires==null) or ((.expires|type)=="string" and .expires >= $today)))' "$USERS_FILE" > "$tmp"
  PRUNE_TMP="$tmp"
  cmp -s "$USERS_FILE" "$tmp" && return 1
  return 0
}
