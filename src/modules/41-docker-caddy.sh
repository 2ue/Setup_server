caddy_stack_dir() {
  docker_stack_dir "caddy"
}

caddyfile_path() {
  printf '%s/%s\n' "$(caddy_stack_dir)" "Caddyfile"
}

caddy_data_dir() {
  printf '%s/%s\n' "$(caddy_stack_dir)" "data"
}

caddy_config_dir() {
  printf '%s/%s\n' "$(caddy_stack_dir)" "config"
}

caddy_logs_dir() {
  printf '%s/%s\n' "$(caddy_data_dir)" "logs"
}

caddy_current_profile() {
  local caddyfile="$1"

  [ -f "$caddyfile" ] || return 1
  awk -F': ' '
    /^#[[:space:]]*setup-server-caddy-profile:/ {
      print $2
      exit
    }
  ' "$caddyfile"
}

caddy_current_domain() {
  local caddyfile="$1"

  [ -f "$caddyfile" ] || return 1
  awk '
    /^[[:space:]]*$/ { next }
    /^[[:space:]]*#/ { next }
    /^[[:space:]]*\{/ { next }
    /^[[:space:]]*\}/ { next }
    {
      gsub(/[[:space:]]*\{[[:space:]]*$/, "", $0)
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", $0)
      print
      exit
    }
  ' "$caddyfile"
}

caddy_current_upstream() {
  local caddyfile="$1"

  [ -f "$caddyfile" ] || return 1
  awk '
    $1 == "reverse_proxy" {
      print $2
      exit
    }
  ' "$caddyfile"
}

prepare_caddy_stack_dirs() {
  ensure_privileged_dir "$(docker_stack_root)" "root"
  ensure_privileged_dir "$(caddy_stack_dir)" "root"
  ensure_privileged_dir "$(caddy_data_dir)" "root"
  ensure_privileged_dir "$(caddy_config_dir)" "root"
  ensure_privileged_dir "$(caddy_logs_dir)" "root"
}

caddy_default_sub2api_upstream() {
  local env_path
  local sub2api_port

  env_path="$(sub2api_env_path 2>/dev/null || true)"
  if [ -n "$env_path" ] && [ -f "$env_path" ]; then
    sub2api_port="$(env_value_or_default "$env_path" "SERVER_PORT" "8080")"
  else
    sub2api_port="8080"
  fi

  printf 'host.docker.internal:%s\n' "$sub2api_port"
}

caddy_sub2api_request_body_limit() {
  local env_path
  local gateway_bytes
  local server_bytes
  local max_bytes

  env_path="$(sub2api_env_path 2>/dev/null || true)"
  gateway_bytes="268435456"
  server_bytes="268435456"

  if [ -n "$env_path" ] && [ -f "$env_path" ]; then
    gateway_bytes="$(env_value_or_default "$env_path" "GATEWAY_MAX_BODY_SIZE" "$gateway_bytes")"
    server_bytes="$(env_value_or_default "$env_path" "SERVER_MAX_REQUEST_BODY_SIZE" "$server_bytes")"
  fi

  if ! [[ "$gateway_bytes" =~ ^[0-9]+$ ]]; then
    gateway_bytes="268435456"
  fi
  if ! [[ "$server_bytes" =~ ^[0-9]+$ ]]; then
    server_bytes="268435456"
  fi

  if [ "$gateway_bytes" -ge "$server_bytes" ]; then
    max_bytes="$gateway_bytes"
  else
    max_bytes="$server_bytes"
  fi

  if [ "$max_bytes" -gt 0 ] && [ $((max_bytes % 1048576)) -eq 0 ]; then
    printf '%sMB\n' "$((max_bytes / 1048576))"
  else
    printf '%s\n' "$max_bytes"
  fi
}

configure_caddy_reverse_proxy() {
  local caddyfile
  local temp_file
  local default_domain
  local default_upstream
  local domain_name
  local upstream_target

  caddyfile="$(caddyfile_path)"
  temp_file="$(mktemp)"
  default_domain="$(caddy_current_domain "$caddyfile" 2>/dev/null || true)"
  default_upstream="$(caddy_current_upstream "$caddyfile" 2>/dev/null || true)"

  if [ -z "$default_domain" ]; then
    default_domain="example.com"
  fi
  if [ -z "$default_upstream" ]; then
    default_upstream="host.docker.internal:3000"
  fi

  domain_name="$(prompt_with_default "输入需要反向代理的域名" "$default_domain")"
  while [ -z "$domain_name" ]; do
    warn "域名不能为空"
    domain_name="$(prompt_with_default "输入需要反向代理的域名" "$default_domain")"
  done

  upstream_target="$(prompt_with_default "输入本地服务地址（host:port）" "$default_upstream")"
  while [ -z "$upstream_target" ]; do
    warn "本地服务地址不能为空"
    upstream_target="$(prompt_with_default "输入本地服务地址（host:port）" "$default_upstream")"
  done

  cat >"$temp_file" <<EOF
# setup-server-caddy-profile: generic
$domain_name {
    encode zstd gzip
    reverse_proxy $upstream_target
}
EOF
  run_privileged mv "$temp_file" "$caddyfile"
  run_privileged chmod 644 "$caddyfile"
  run_privileged chown root:root "$caddyfile"

  log "Caddy 配置已写入：$caddyfile"
  log "域名：$domain_name"
  log "反代到：$upstream_target"
}

configure_caddy_sub2api_reverse_proxy() {
  local caddyfile
  local temp_file
  local default_domain
  local default_upstream
  local domain_name
  local upstream_target
  local request_body_limit

  caddyfile="$(caddyfile_path)"
  temp_file="$(mktemp)"
  default_domain="$(caddy_current_domain "$caddyfile" 2>/dev/null || true)"
  default_upstream="$(caddy_current_upstream "$caddyfile" 2>/dev/null || true)"
  request_body_limit="$(caddy_sub2api_request_body_limit)"

  if [ -z "$default_domain" ]; then
    default_domain="api.example.com"
  fi
  if [ -z "$default_upstream" ]; then
    default_upstream="$(caddy_default_sub2api_upstream)"
  fi

  domain_name="$(prompt_with_default "输入 sub2api 对外域名" "$default_domain")"
  while [ -z "$domain_name" ]; do
    warn "域名不能为空"
    domain_name="$(prompt_with_default "输入 sub2api 对外域名" "$default_domain")"
  done

  upstream_target="$(prompt_with_default "输入 sub2api 上游地址（host:port）" "$default_upstream")"
  while [ -z "$upstream_target" ]; do
    warn "上游地址不能为空"
    upstream_target="$(prompt_with_default "输入 sub2api 上游地址（host:port）" "$default_upstream")"
  done

  cat >"$temp_file" <<EOF
# setup-server-caddy-profile: sub2api
$domain_name {
    @static {
        path /assets/*
        path /logo.png
        path /favicon.ico
    }
    header @static {
        Cache-Control "public, max-age=31536000, immutable"
        -Pragma
        -Expires
    }

    tls {
        protocols tls1.2 tls1.3
        ciphers TLS_ECDHE_ECDSA_WITH_AES_256_GCM_SHA384 TLS_ECDHE_RSA_WITH_AES_256_GCM_SHA384 TLS_ECDHE_ECDSA_WITH_CHACHA20_POLY1305_SHA256 TLS_ECDHE_RSA_WITH_CHACHA20_POLY1305_SHA256 TLS_ECDHE_ECDSA_WITH_AES_128_GCM_SHA256 TLS_ECDHE_RSA_WITH_AES_128_GCM_SHA256
    }

    reverse_proxy $upstream_target {
        health_uri /health
        health_interval 30s
        health_timeout 10s
        health_status 200

        lb_policy round_robin
        lb_try_duration 5s
        lb_try_interval 250ms

        header_up X-Real-IP {remote_host}
        header_up CF-Connecting-IP {http.request.header.CF-Connecting-IP}

        transport http {
            keepalive 120s
            keepalive_idle_conns 256
            read_buffer 16KB
            write_buffer 16KB
            compression off
        }

        fail_duration 30s
        max_fails 3
        unhealthy_status 500 502 503 504
    }

    encode {
        zstd
        gzip 6
        minimum_length 256
        match {
            header Content-Type text/*
            header Content-Type application/json*
            header Content-Type application/javascript*
            header Content-Type application/xml*
            header Content-Type application/rss+xml*
            header Content-Type image/svg+xml*
        }
    }

    request_body {
        max_size $request_body_limit
    }

    log {
        output file /data/logs/sub2api-access.log {
            roll_size 50mb
            roll_keep 10
            roll_keep_for 720h
        }
        format json
        level INFO
    }

    handle_errors {
        respond "{err.status_code} {err.status_text}"
    }
}
EOF
  run_privileged mv "$temp_file" "$caddyfile"
  run_privileged chmod 644 "$caddyfile"
  run_privileged chown root:root "$caddyfile"

  log "Sub2API 适配版 Caddy 配置已写入：$caddyfile"
  log "域名：$domain_name"
  log "反代到：$upstream_target"
  log "请求体限制：$request_body_limit"
}

configure_caddy_profile() {
  local current_profile="${1:-}"

  if [ "$current_profile" = "sub2api" ]; then
    if prompt_yes_no_default_yes "是否使用适配 sub2api 的 Caddy 配置模板？"; then
      configure_caddy_sub2api_reverse_proxy
    else
      configure_caddy_reverse_proxy
    fi
    return $?
  fi

  if prompt_yes_no_default_no "是否使用适配 sub2api 的 Caddy 配置模板？"; then
    configure_caddy_sub2api_reverse_proxy
  else
    configure_caddy_reverse_proxy
  fi
}

install_caddy_stack() {
  local compose_path
  local current_domain

  compose_path="$(compose_file_path "caddy")"
  prepare_docker_compose "caddy" || return 1
  prepare_caddy_stack_dirs
  configure_caddy_profile "" || return 1

  run_service_compose "caddy" up -d || return 1
  current_domain="$(caddy_current_domain "$(caddyfile_path)" 2>/dev/null || true)"
  log "Caddy 已部署。"
  if [ -n "$current_domain" ]; then
    log "请确保域名已解析到当前服务器：$current_domain"
  fi
  log "80/443 端口需要对外放行，且不应被其他服务占用。"
}

update_caddy_stack() {
  local compose_path
  local current_profile

  compose_path="$(compose_file_path "caddy")"
  prepare_docker_compose "caddy" || return 1
  prepare_caddy_stack_dirs
  current_profile="$(caddy_current_profile "$(caddyfile_path)" 2>/dev/null || true)"

  if [ ! -f "$(caddyfile_path)" ]; then
    configure_caddy_profile "$current_profile" || return 1
  elif prompt_yes_no_default_no "是否同时更新 Caddy 反向代理配置？"; then
    configure_caddy_profile "$current_profile" || return 1
  fi

  run_service_compose "caddy" pull || return 1
  run_service_compose "caddy" up -d || return 1
  log "Caddy 已更新。"
}
