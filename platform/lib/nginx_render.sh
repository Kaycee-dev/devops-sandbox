#!/usr/bin/env bash
set -euo pipefail

# shellcheck source=platform/lib/config.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/config.sh"
# shellcheck source=platform/lib/log.sh
source "${LIB_DIR}/log.sh"

reload_nginx() {
    docker exec sandbox-nginx nginx -t
    docker exec sandbox-nginx nginx -s reload
}

write_conf() {
    local env_id="$1"
    local env_name="$2"
    local upstream="sandbox-${env_id}-app:${APP_PORT}"
    local conf="${NGINX_CONF_DIR}/${env_id}.conf"
    local tmp="${conf}.tmp.$$"

    cat >"$tmp" <<EOF
# GENERATED - do not edit by hand. Source: platform/lib/nginx_render.sh
location /${env_id}/ {
    resolver 127.0.0.11 valid=10s ipv6=off;
    set \$upstream ${upstream};
    rewrite ^/${env_id}/?(.*)\$ /\$1 break;
    proxy_http_version 1.1;
    proxy_set_header Host \$host;
    proxy_set_header X-Sandbox-Env ${env_id};
    proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto \$scheme;
    proxy_pass http://\$upstream;
}

location /${env_name}/ {
    resolver 127.0.0.11 valid=10s ipv6=off;
    set \$upstream ${upstream};
    rewrite ^/${env_name}/?(.*)\$ /\$1 break;
    proxy_http_version 1.1;
    proxy_set_header Host \$host;
    proxy_set_header X-Sandbox-Env ${env_id};
    proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto \$scheme;
    proxy_pass http://\$upstream;
}
EOF
    mv -f "$tmp" "$conf"

    if ! reload_nginx; then
        local broken_ts
        broken_ts="$(ts)"
        mkdir -p "${NGINX_CONF_DIR}/.broken"
        mv -f "$conf" "${NGINX_CONF_DIR}/.broken/${env_id}.conf.${broken_ts}"
        log ERROR nginx_render "$env_id" "nginx config failed validation; moved to .broken"
        return 1
    fi
}

delete_conf() {
    local env_id="$1"
    rm -f -- "${NGINX_CONF_DIR}/${env_id}.conf"
    reload_nginx
}
