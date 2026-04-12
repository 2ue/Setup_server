DOCKER_KEYS=("code-server" "nginx" "pure-ftpd" "web_object_detection" "zfile" "subconverter" "sub-web" "mdserver-web" "qinglong" "webdav-client" "watchtower" "jsxm" "caddy" "codex2api")
DOCKER_INFOS=("在线 Web IDE" "Web 服务器" "FTP 服务器" "在线 web 目标识别" "在线云盘" "订阅转换后端" "订阅转换前端" "一款简单Linux面板服务" "定时任务管理面板" "Webdav 客户端，同步映射到宿主文件系统" "自动化更新 Docker 镜像和容器" "Web 在线 xm 音乐播放器" "Caddy 反向代理（域名反代到本地服务）" "Codex2API 一键部署（自动拉取 compose 和 env）")

docker_stack_root() {
  printf '%s\n' "/root/docker-compose"
}

docker_stack_dir() {
  printf '%s/%s\n' "$(docker_stack_root)" "$1"
}

compose_file_path() {
  printf '%s/%s\n' "$(docker_stack_dir "$1")" "docker-compose.yml"
}

compose_env_path() {
  printf '%s/%s\n' "$(docker_stack_dir "$1")" ".env"
}

docker_service_stack_exists() {
  [ -f "$(compose_file_path "$1")" ]
}

run_service_compose() {
  local service_name="$1"
  local stack_dir
  local compose_path
  local env_path
  shift

  stack_dir="$(docker_stack_dir "$service_name")"
  compose_path="$(compose_file_path "$service_name")"
  env_path="$(compose_env_path "$service_name")"

  if [ ! -f "$compose_path" ]; then
    warn "未找到 ${service_name} 的 compose 文件：$compose_path"
    return 1
  fi

  if [ -f "$env_path" ]; then
    run_privileged docker compose --project-directory "$stack_dir" -f "$compose_path" --env-file "$env_path" "$@"
  else
    run_privileged docker compose --project-directory "$stack_dir" -f "$compose_path" "$@"
  fi
}

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

install_caddy_stack() {
  local compose_path
  local current_domain

  compose_path="$(compose_file_path "caddy")"
  prepare_docker_compose "caddy" || return 1
  prepare_caddy_stack_dirs
  configure_caddy_reverse_proxy || return 1

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

  compose_path="$(compose_file_path "caddy")"
  prepare_docker_compose "caddy" || return 1
  prepare_caddy_stack_dirs

  if [ ! -f "$(caddyfile_path)" ]; then
    configure_caddy_reverse_proxy || return 1
  elif prompt_yes_no_default_no "是否同时更新 Caddy 反向代理配置？"; then
    configure_caddy_reverse_proxy || return 1
  fi

  run_service_compose "caddy" pull || return 1
  run_service_compose "caddy" up -d || return 1
  log "Caddy 已更新。"
}

codex2api_stack_dir() {
  docker_stack_dir "codex2api"
}

codex2api_compose_path() {
  printf '%s/%s\n' "$(codex2api_stack_dir)" "docker-compose.yml"
}

codex2api_env_path() {
  printf '%s/%s\n' "$(codex2api_stack_dir)" ".env"
}

codex2api_env_example_path() {
  printf '%s/%s\n' "$(codex2api_stack_dir)" ".env.example"
}

codex2api_install_info_path() {
  printf '%s/%s\n' "$(codex2api_stack_dir)" "INSTALL_INFO.txt"
}

codex2api_stack_exists() {
  [ -f "$(codex2api_compose_path)" ] && [ -f "$(codex2api_env_path)" ]
}

compose_service_names() {
  local compose_path="$1"

  awk '
    /^services:[[:space:]]*$/ {
      in_services = 1
      next
    }
    in_services && /^[^[:space:]]/ {
      exit
    }
    in_services && /^[[:space:]]{2}[A-Za-z0-9_.-]+:[[:space:]]*$/ {
      name = $1
      sub(/:$/, "", name)
      print name
    }
  ' "$compose_path"
}

docker_container_name_exists() {
  local container_name="$1"

  run_privileged docker ps -a --format '{{.Names}}' | grep -Fx -- "$container_name" >/dev/null 2>&1
}

codex2api_conflicting_container_names() {
  local compose_path="$1"
  local project_name="$2"
  local service_name
  local candidate

  while IFS= read -r service_name; do
    [ -n "$service_name" ] || continue
    for candidate in \
      "$service_name" \
      "${project_name}-${service_name}" \
      "${project_name}-${service_name}-1" \
      "${project_name}_${service_name}" \
      "${project_name}_${service_name}_1"
    do
      if docker_container_name_exists "$candidate"; then
        printf '%s\n' "$candidate"
      fi
    done
  done < <(compose_service_names "$compose_path")
}

dir_has_entries() {
  local dir_path="$1"

  [ -d "$dir_path" ] || return 1
  find "$dir_path" -mindepth 1 -maxdepth 1 -print -quit 2>/dev/null | grep -q .
}

docker_service_name_by_selection() {
  local selection="$1"

  if ! [[ "$selection" =~ ^[0-9]+$ ]]; then
    return 1
  fi

  printf '%s\n' "${DOCKER_KEYS[$selection]:-}"
}

generate_random_secret() {
  local length="${1:-32}"
  local secret=""

  while [ "${#secret}" -lt "$length" ]; do
    if command_exists openssl; then
      secret="${secret}$(openssl rand -base64 48 | tr -dc 'A-Za-z0-9' | head -c "$length" || true)"
    else
      secret="${secret}$(LC_ALL=C tr -dc 'A-Za-z0-9' </dev/urandom | head -c "$length" || true)"
    fi
  done

  printf '%s\n' "${secret:0:length}"
}

port_is_in_use() {
  local port="$1"
  local port_hex

  if command_exists ss; then
    ss -ltnH 2>/dev/null | awk '{print $4}' | grep -Eq "(:|\\])${port}$"
    return $?
  fi

  if command_exists lsof; then
    lsof -nP -iTCP:"$port" -sTCP:LISTEN >/dev/null 2>&1
    return $?
  fi

  if command_exists netstat; then
    netstat -ltn 2>/dev/null | awk '{print $4}' | grep -Eq "(:|\\])${port}$"
    return $?
  fi

  if [ -r /proc/net/tcp ] || [ -r /proc/net/tcp6 ]; then
    port_hex="$(printf '%04X' "$port")"
    awk -v port_hex="$port_hex" '
      $4 == "0A" {
        split($2, parts, ":")
        if (toupper(parts[2]) == port_hex) {
          found = 1
          exit
        }
      }
      END {
        exit !found
      }
    ' /proc/net/tcp /proc/net/tcp6 2>/dev/null
    return $?
  fi

  return 1
}

random_available_port() {
  local min_port="${1:-20000}"
  local max_port="${2:-59999}"
  local attempts="${3:-200}"
  local candidate
  local i

  for ((i = 0; i < attempts; i++)); do
    candidate=$((RANDOM % (max_port - min_port + 1) + min_port))
    if ! port_is_in_use "$candidate"; then
      printf '%s\n' "$candidate"
      return 0
    fi
  done

  for ((candidate = min_port; candidate <= max_port; candidate++)); do
    if ! port_is_in_use "$candidate"; then
      printf '%s\n' "$candidate"
      return 0
    fi
  done

  warn "未找到可用端口 (${min_port}-${max_port})"
  return 1
}

env_has_key() {
  local env_path="$1"
  local key="$2"

  [ -f "$env_path" ] || return 1
  grep -Eq "^[[:space:]]*${key}=" "$env_path"
}

env_get_value() {
  local env_path="$1"
  local key="$2"

  [ -f "$env_path" ] || return 1
  awk -F= -v key="$key" '
    BEGIN { found = 0 }
    $0 !~ /^[[:space:]]*#/ && $1 == key {
      found = 1
      sub(/^[^=]*=/, "", $0)
      print $0
      exit
    }
    END {
      if (!found) {
        exit 1
      }
    }
  ' "$env_path"
}

env_upsert_value() {
  local env_path="$1"
  local key="$2"
  local value="$3"
  local temp_file="${env_path}.tmp"

  awk -v key="$key" -v value="$value" '
    BEGIN { updated = 0 }
    $0 ~ "^[[:space:]]*" key "=" {
      print key "=" value
      updated = 1
      next
    }
    { print }
    END {
      if (!updated) {
        print key "=" value
      }
    }
  ' "$env_path" >"$temp_file"
  mv "$temp_file" "$env_path"
}

merge_env_defaults_from_template() {
  local env_path="$1"
  local template_path="$2"
  local line
  local key

  while IFS= read -r line; do
    case "$line" in
      ""|"#"*)
        continue
        ;;
      *=*)
        key="${line%%=*}"
        if ! env_has_key "$env_path" "$key"; then
          printf '\n%s\n' "$line" >>"$env_path"
        fi
        ;;
    esac
  done <"$template_path"
}

ensure_env_value() {
  local env_path="$1"
  local key="$2"
  local fallback="$3"
  local current_value

  current_value="$(env_get_value "$env_path" "$key" 2>/dev/null || true)"
  if [ -z "$current_value" ]; then
    env_upsert_value "$env_path" "$key" "$fallback"
  fi
}

env_value_or_default() {
  local env_path="$1"
  local key="$2"
  local fallback="$3"
  local current_value

  current_value="$(env_get_value "$env_path" "$key" 2>/dev/null || true)"
  if [ -z "$current_value" ]; then
    printf '%s\n' "$fallback"
  else
    printf '%s\n' "$current_value"
  fi
}

codex2api_admin_secret_needs_generation() {
  case "$1" in
    ""|"changeme"|"your-admin-password"|"your_admin_secret"|"your-secure-admin-password-here")
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

codex2api_database_password_needs_generation() {
  case "$1" in
    ""|"codex2api"|"changeme"|"your_db_password"|"your-strong-db-password")
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

resolve_stack_bind_path() {
  local stack_dir="$1"
  local bind_path="$2"

  case "$bind_path" in
    /*)
      printf '%s\n' "$bind_path"
      ;;
    ./*)
      printf '%s/%s\n' "$stack_dir" "${bind_path#./}"
      ;;
    *)
      printf '%s/%s\n' "$stack_dir" "$bind_path"
      ;;
  esac
}

codex2api_prepare_stack_dirs() {
  local stack_dir="$1"
  local env_path="$2"
  local postgres_dir
  local redis_dir
  local logs_dir

  postgres_dir="$(resolve_stack_bind_path "$stack_dir" "$(env_value_or_default "$env_path" "POSTGRES_DATA_DIR" "./data/codex2api-postgres")")"
  redis_dir="$(resolve_stack_bind_path "$stack_dir" "$(env_value_or_default "$env_path" "REDIS_DATA_DIR" "./data/codex2api-redis")")"
  logs_dir="$(resolve_stack_bind_path "$stack_dir" "$(env_value_or_default "$env_path" "LOGS_DIR" "./logs")")"

  ensure_privileged_dir "$postgres_dir" "root"
  ensure_privileged_dir "$redis_dir" "root"
  ensure_privileged_dir "$logs_dir" "root"
}

codex2api_postgres_data_dir() {
  local stack_dir="$1"
  local env_path="${2:-}"

  if [ -n "$env_path" ] && [ -f "$env_path" ]; then
    resolve_stack_bind_path "$stack_dir" "$(env_value_or_default "$env_path" "POSTGRES_DATA_DIR" "./data/codex2api-postgres")"
  else
    printf '%s/%s\n' "$stack_dir" "data/codex2api-postgres"
  fi
}

codex2api_has_existing_postgres_data() {
  local stack_dir="$1"
  local env_path="${2:-}"
  local postgres_dir

  postgres_dir="$(codex2api_postgres_data_dir "$stack_dir" "$env_path")"
  [ -f "$postgres_dir/PG_VERSION" ] || dir_has_entries "$postgres_dir"
}

codex2api_run_compose() {
  local stack_dir="$1"
  local compose_command="$2"

  run_privileged bash -lc "cd $(shell_quote "$stack_dir") && $compose_command"
}

codex2api_sync_remote_files() {
  local repo_owner="$1"
  local repo_ref="$2"
  local stack_dir
  local compose_path
  local env_path
  local env_example_path
  local temp_compose
  local temp_env
  local compose_url
  local env_url

  stack_dir="$(codex2api_stack_dir)"
  compose_path="$(codex2api_compose_path)"
  env_path="$(codex2api_env_path)"
  env_example_path="$(codex2api_env_example_path)"
  temp_compose="$(mktemp)"
  temp_env="$(mktemp)"
  compose_url="https://$github_raw/$repo_owner/codex2api/$repo_ref/docker-compose.yml"
  env_url="https://$github_raw/$repo_owner/codex2api/$repo_ref/.env.example"

  ensure_privileged_dir "$(docker_stack_root)" "root"
  ensure_privileged_dir "$stack_dir" "root"

  download_to "$compose_url" "$temp_compose" || {
    rm -f "$temp_compose" "$temp_env"
    return 1
  }
  download_to "$env_url" "$temp_env" || {
    rm -f "$temp_compose" "$temp_env"
    return 1
  }

  run_privileged mv "$temp_compose" "$compose_path"
  run_privileged mv "$temp_env" "$env_example_path"
  run_privileged chmod 644 "$compose_path" "$env_example_path"
  run_privileged chown root:root "$compose_path" "$env_example_path"

  if [ ! -f "$env_path" ]; then
    run_privileged cp "$env_example_path" "$env_path"
  else
    merge_env_defaults_from_template "$env_path" "$env_example_path"
  fi

  run_privileged chmod 600 "$env_path"
  run_privileged chown root:root "$env_path"
}

codex2api_collect_settings() {
  local env_path="$1"
  local repo_owner
  local repo_ref
  local ghcr_owner
  local image_tag
  local project_name

  repo_owner="$(env_value_or_default "$env_path" "SETUP_SERVER_REPO_OWNER" "yyssp")"
  repo_ref="$(env_value_or_default "$env_path" "SETUP_SERVER_REPO_REF" "main")"
  ghcr_owner="$(env_value_or_default "$env_path" "GHCR_OWNER" "$repo_owner")"
  image_tag="$(env_value_or_default "$env_path" "CODEX_IMAGE_TAG" "latest")"
  project_name="$(env_value_or_default "$env_path" "COMPOSE_PROJECT_NAME" "codex2api")"

  if ! prompt_yes_no_default_yes "使用默认/当前 codex2api 部署参数"; then
    repo_owner="$(prompt_with_default "设置 codex2api 仓库 owner" "$repo_owner")"
    repo_ref="$(prompt_with_default "设置 codex2api 仓库分支或 tag" "$repo_ref")"
    ghcr_owner="$(prompt_with_default "设置 GHCR 镜像 owner" "$ghcr_owner")"
    image_tag="$(prompt_with_default "设置镜像 tag" "$image_tag")"
    project_name="$(prompt_with_default "设置 Compose 项目标识" "$project_name")"
  fi

  printf '%s\n' "$repo_owner|$repo_ref|$ghcr_owner|$image_tag|$project_name"
}

codex2api_configure_env() {
  local env_path="$1"
  local repo_owner="$2"
  local repo_ref="$3"
  local ghcr_owner="$4"
  local image_tag="$5"
  local project_name="$6"
  local codex_port="$7"
  local fresh_install="${8:-0}"
  local admin_secret
  local database_password

  env_upsert_value "$env_path" "SETUP_SERVER_REPO_OWNER" "$repo_owner"
  env_upsert_value "$env_path" "SETUP_SERVER_REPO_REF" "$repo_ref"
  env_upsert_value "$env_path" "GHCR_OWNER" "$ghcr_owner"
  env_upsert_value "$env_path" "CODEX_IMAGE_TAG" "$image_tag"
  env_upsert_value "$env_path" "COMPOSE_PROJECT_NAME" "$project_name"
  env_upsert_value "$env_path" "CODEX_PORT" "$codex_port"

  ensure_env_value "$env_path" "POSTGRES_DATA_DIR" "./data/codex2api-postgres"
  ensure_env_value "$env_path" "REDIS_DATA_DIR" "./data/codex2api-redis"
  ensure_env_value "$env_path" "LOGS_DIR" "./logs"
  ensure_env_value "$env_path" "DATABASE_DRIVER" "postgres"
  ensure_env_value "$env_path" "DATABASE_HOST" "postgres"
  ensure_env_value "$env_path" "DATABASE_PORT" "5432"
  ensure_env_value "$env_path" "DATABASE_USER" "codex2api"
  ensure_env_value "$env_path" "DATABASE_NAME" "codex2api"
  ensure_env_value "$env_path" "CACHE_DRIVER" "redis"
  ensure_env_value "$env_path" "REDIS_ADDR" "redis:6379"
  ensure_env_value "$env_path" "REDIS_DB" "0"
  ensure_env_value "$env_path" "TZ" "Asia/Shanghai"

  admin_secret="$(env_get_value "$env_path" "ADMIN_SECRET" 2>/dev/null || true)"
  if [ "$fresh_install" = "1" ] && codex2api_admin_secret_needs_generation "$admin_secret"; then
    env_upsert_value "$env_path" "ADMIN_SECRET" "$(generate_random_secret 24)"
  elif [ -z "$admin_secret" ]; then
    env_upsert_value "$env_path" "ADMIN_SECRET" "$(generate_random_secret 24)"
  fi

  database_password="$(env_get_value "$env_path" "DATABASE_PASSWORD" 2>/dev/null || true)"
  if [ "$fresh_install" = "1" ] && codex2api_database_password_needs_generation "$database_password"; then
    env_upsert_value "$env_path" "DATABASE_PASSWORD" "$(generate_random_secret 24)"
  elif [ -z "$database_password" ]; then
    env_upsert_value "$env_path" "DATABASE_PASSWORD" "$(generate_random_secret 24)"
  fi

  run_privileged chmod 600 "$env_path"
  run_privileged chown root:root "$env_path"
}

codex2api_write_install_info() {
  local stack_dir="$1"
  local env_path="$2"
  local codex_port="$3"
  local info_path
  local admin_secret
  local database_password
  local temp_file

  info_path="$(codex2api_install_info_path)"
  admin_secret="$(env_get_value "$env_path" "ADMIN_SECRET" 2>/dev/null || true)"
  database_password="$(env_get_value "$env_path" "DATABASE_PASSWORD" 2>/dev/null || true)"
  temp_file="$(mktemp)"

  cat >"$temp_file" <<EOF
codex2api 部署信息

部署目录: $stack_dir
访问地址: http://localhost:$codex_port
管理后台: http://localhost:$codex_port/admin/

ADMIN_SECRET=$admin_secret
DATABASE_PASSWORD=$database_password
EOF

  run_privileged mv "$temp_file" "$info_path"
  run_privileged chmod 600 "$info_path"
  run_privileged chown root:root "$info_path"
}

install_codex2api_stack() {
  local stack_dir
  local compose_path
  local env_path
  local settings
  local repo_owner
  local repo_ref
  local ghcr_owner
  local image_tag
  local project_name
  local codex_port
  local conflict_names

  stack_dir="$(codex2api_stack_dir)"
  compose_path="$(codex2api_compose_path)"
  env_path="$(codex2api_env_path)"
  ensure_privileged_dir "$(docker_stack_root)" "root"
  ensure_privileged_dir "$stack_dir" "root"

  if codex2api_stack_exists; then
    warn "codex2api 已存在：$stack_dir"
    log "请使用“更新 docker 镜像和容器”来刷新现有服务。"
    log "当前访问地址：http://localhost:$(env_value_or_default "$env_path" "CODEX_PORT" "8080")"
    return 0
  fi

  if codex2api_has_existing_postgres_data "$stack_dir"; then
    warn "检测到已存在的 PostgreSQL 数据目录：$(codex2api_postgres_data_dir "$stack_dir")"
    warn "这通常表示之前部署过 codex2api，但只清掉了 compose 文件或容器，没有清掉数据目录。"
    warn "PostgreSQL 只会在首次初始化时读取 DATABASE_PASSWORD；当前继续安装会导致数据库密码与 .env 不一致。"
    log "如需保留旧数据，请恢复原 .env 后执行“更新 docker 镜像和容器”。"
    log "如无需保留旧数据，请先删除目录后再重装：$(codex2api_postgres_data_dir "$stack_dir")"
    return 1
  fi

  settings="$(codex2api_collect_settings "$env_path")"
  IFS='|' read -r repo_owner repo_ref ghcr_owner image_tag project_name <<<"$settings"
  codex_port="$(random_available_port)" || return 1

  codex2api_sync_remote_files "$repo_owner" "$repo_ref" || return 1
  conflict_names="$(codex2api_conflicting_container_names "$compose_path" "$project_name" 2>/dev/null | sort -u)"
  if [ -n "$conflict_names" ]; then
    warn "检测到已存在的同名容器，已停止安装："
    printf '%s\n' "$conflict_names" >&2
    warn "请先清理这些容器，或修改 COMPOSE_PROJECT_NAME 后再安装。"
    return 1
  fi
  codex2api_configure_env "$env_path" "$repo_owner" "$repo_ref" "$ghcr_owner" "$image_tag" "$project_name" "$codex_port" "1"
  codex2api_prepare_stack_dirs "$stack_dir" "$env_path"

  codex2api_run_compose "$stack_dir" "docker compose pull && docker compose up -d" || return 1
  codex2api_write_install_info "$stack_dir" "$env_path" "$codex_port"
  log "codex2api 已部署，配置目录：$stack_dir"
  log "访问地址：http://localhost:$codex_port"
  log "管理后台：http://localhost:$codex_port/admin/"
  log "ADMIN_SECRET: $(env_get_value "$env_path" "ADMIN_SECRET" 2>/dev/null || true)"
  log "数据库密码和管理后台密钥已写入：$env_path"
  log "安装信息文件：$(codex2api_install_info_path)"
}

update_codex2api_stack() {
  local stack_dir
  local env_path
  local repo_owner
  local repo_ref
  local codex_port

  stack_dir="$(codex2api_stack_dir)"
  env_path="$(codex2api_env_path)"

  if [ ! -f "$env_path" ]; then
    warn "未找到 codex2api 的部署目录：$stack_dir"
    return 1
  fi

  repo_owner="$(env_value_or_default "$env_path" "SETUP_SERVER_REPO_OWNER" "yyssp")"
  repo_ref="$(env_value_or_default "$env_path" "SETUP_SERVER_REPO_REF" "main")"
  codex_port="$(env_value_or_default "$env_path" "CODEX_PORT" "")"
  if [ -z "$codex_port" ] || port_is_in_use "$codex_port"; then
    codex_port="$(random_available_port)" || return 1
  fi

  codex2api_sync_remote_files "$repo_owner" "$repo_ref" || return 1
  codex2api_configure_env \
    "$env_path" \
    "$repo_owner" \
    "$repo_ref" \
    "$(env_value_or_default "$env_path" "GHCR_OWNER" "$repo_owner")" \
    "$(env_value_or_default "$env_path" "CODEX_IMAGE_TAG" "latest")" \
    "$(env_value_or_default "$env_path" "COMPOSE_PROJECT_NAME" "codex2api")" \
    "$codex_port" \
    "0"
  codex2api_prepare_stack_dirs "$stack_dir" "$env_path"

  codex2api_run_compose "$stack_dir" "docker compose pull && docker compose up -d" || return 1
  codex2api_write_install_info "$stack_dir" "$env_path" "$codex_port"
  log "codex2api 已更新，配置目录：$stack_dir"
  log "访问地址：http://localhost:$codex_port"
  log "安装信息文件：$(codex2api_install_info_path)"
}

remove_codex2api_stack() {
  local stack_dir

  stack_dir="$(codex2api_stack_dir)"

  if [ ! -f "$(codex2api_compose_path)" ]; then
    warn "未找到 codex2api 的部署目录：$stack_dir"
    return 1
  fi

  codex2api_run_compose "$stack_dir" "docker compose down" || return 1
  log "codex2api 容器已停止并移除，数据目录仍保留：$stack_dir"
}

normalize_container_name() {
  local compose_file="$1"
  local container_name="$2"
  local temp_file

  temp_file="$(mktemp)"
  if grep -q '^[[:space:]]*container_name:' "$compose_file"; then
    run_privileged sed -i "s/^[[:space:]]*container_name:.*/    container_name: $container_name/" "$compose_file"
    rm -f "$temp_file"
    return 0
  fi

  awk -v name="$container_name" '
    !inserted && /^[[:space:]]*image:/ {
      print "    container_name: " name
      inserted=1
    }
    { print }
  ' "$compose_file" >"$temp_file" && run_privileged mv "$temp_file" "$compose_file"

  run_privileged chmod 644 "$compose_file"
  run_privileged chown root:root "$compose_file"
}

prepare_docker_compose() {
  local service_name="$1"
  local stack_dir
  local compose_path
  local temp_compose

  stack_dir="$(docker_stack_dir "$service_name")"
  compose_path="$(compose_file_path "$service_name")"
  ensure_privileged_dir "$(docker_stack_root)" "root"
  ensure_privileged_dir "$stack_dir" "root"

  if [ "$service_name" = "qinglong" ]; then
    temp_compose="$(mktemp)"
    download_to "https://$github_raw/whyour/qinglong/master/docker/docker-compose.yml" "$temp_compose" || {
      rm -f "$temp_compose"
      return 1
    }
    run_privileged mv "$temp_compose" "$compose_path"
    run_privileged chmod 644 "$compose_path"
    run_privileged chown root:root "$compose_path"
  else
    install_asset_file_privileged "docker/$service_name.yml" "$compose_path" "root" 644 || return 1
  fi

  normalize_container_name "$compose_path" "$service_name" || return 1
}

service_stack_file_path() {
  local service_name="$1"
  local relative_path="$2"

  printf '%s/%s\n' "$(docker_stack_dir "$service_name")" "$relative_path"
}

prepare_standard_service_stack_dirs() {
  local service_name="$1"
  local stack_dir
  local temp_file

  stack_dir="$(docker_stack_dir "$service_name")"
  ensure_privileged_dir "$(docker_stack_root)" "root"
  ensure_privileged_dir "$stack_dir" "root"

  case "$service_name" in
    code-server)
      ensure_privileged_dir "$(service_stack_file_path "$service_name" "config")" "root"
      ;;
    nginx)
      ensure_privileged_dir "$(service_stack_file_path "$service_name" "html")" "root"
      if [ ! -f "$(service_stack_file_path "$service_name" "html/index.html")" ]; then
        temp_file="$(mktemp)"
        cat >"$temp_file" <<'EOF'
<!doctype html>
<html lang="zh-CN">
  <head>
    <meta charset="utf-8" />
    <title>nginx</title>
  </head>
  <body>
    <h1>nginx is running</h1>
  </body>
</html>
EOF
        run_privileged mv "$temp_file" "$(service_stack_file_path "$service_name" "html/index.html")"
        run_privileged chmod 644 "$(service_stack_file_path "$service_name" "html/index.html")"
      fi
      ;;
    pure-ftpd)
      ensure_privileged_dir "$(service_stack_file_path "$service_name" "web_root")" "root"
      ensure_privileged_dir "$(service_stack_file_path "$service_name" "ftp_passwd")" "root"
      ;;
    zfile)
      ensure_privileged_dir "$(service_stack_file_path "$service_name" "zfile/db")" "root"
      ensure_privileged_dir "$(service_stack_file_path "$service_name" "zfile/logs")" "root"
      ensure_privileged_dir "$(service_stack_file_path "$service_name" "zfile/file")" "root"
      if [ ! -f "$(service_stack_file_path "$service_name" "application.properties")" ]; then
        run_privileged touch "$(service_stack_file_path "$service_name" "application.properties")"
        run_privileged chmod 644 "$(service_stack_file_path "$service_name" "application.properties")"
      fi
      ;;
  esac
}

show_docker_inventory() {
  echo
  log "已下载的 Docker 镜像:"
  run_privileged docker images -a
  echo
  log "已安装的 Docker 容器:"
  run_privileged docker ps -a
}

render_docker_menu() {
  local i

  for i in "${!DOCKER_KEYS[@]}"; do
    printf "%2s. %-20s%s\n" "$i" "${DOCKER_KEYS[$i]}" "${DOCKER_INFOS[$i]}"
  done
}

write_env_kv() {
  local env_path="$1"
  local temp_file
  shift

  temp_file="$(mktemp)"
  : >"$temp_file"
  while [ "$#" -gt 0 ]; do
    printf '%s\n' "$1" >>"$temp_file"
    shift
  done

  ensure_privileged_dir "$(dirname "$env_path")" "root"
  run_privileged mv "$temp_file" "$env_path"
  run_privileged chmod 600 "$env_path"
  run_privileged chown root:root "$env_path"
}

docker_init() {
  print_section "安装/更新 Docker"

  while true; do
    read -r -p "是否配置国内源安装 docker? [Y/n] " input
    case "$input" in
      ""|[yY])
        run_remote_script "https://linuxmirrors.cn/docker.sh" || return 1
        break
        ;;
      [nN])
        run_privileged mkdir -p /etc/apt/sources.list.d
        run_remote_script "https://get.docker.com" || return 1
        break
        ;;
      *)
        log "错误选项：$input"
        ;;
    esac
  done

  log "安装/更新 docker 环境完成!"
}

install_sub_web_assets() {
  local backend_address="$1"
  local repo_path
  local env_file

  repo_path="$(service_stack_file_path "sub-web" "sub-web")"
  env_file="$repo_path/.env"
  ensure_privileged_dir "$(docker_stack_dir "sub-web")" "root"
  if [ -d "$repo_path/.git" ]; then
    run_privileged git -C "$repo_path" pull --ff-only || return 1
  else
    run_privileged rm -rf "$repo_path"
    run_privileged git clone "https://$github_repo/CareyWang/sub-web" "$repo_path" || return 1
  fi

  if [ -f "$env_file" ]; then
    if grep -q '^VUE_APP_SUBCONVERTER_DEFAULT_BACKEND' "$env_file"; then
      run_privileged sed -i "s|^VUE_APP_SUBCONVERTER_DEFAULT_BACKEND.*|VUE_APP_SUBCONVERTER_DEFAULT_BACKEND = \"http://$backend_address\"|" "$env_file"
    else
      printf '%s\n' "VUE_APP_SUBCONVERTER_DEFAULT_BACKEND = \"http://$backend_address\"" | run_privileged tee -a "$env_file" >/dev/null
    fi
    run_privileged chown root:root "$env_file"
  fi
}

sub_web_current_backend() {
  local env_file
  local backend_value

  env_file="$(service_stack_file_path "sub-web" "sub-web/.env")"
  [ -f "$env_file" ] || return 1

  backend_value="$(awk '
    /^[[:space:]]*VUE_APP_SUBCONVERTER_DEFAULT_BACKEND[[:space:]]*=/ {
      sub(/^[^=]*=[[:space:]]*/, "", $0)
      gsub(/^["'"'"']|["'"'"']$/, "", $0)
      sub(/^https?:\/\//, "", $0)
      print
      exit
    }
  ' "$env_file")"

  [ -n "$backend_value" ] || return 1
  printf '%s\n' "$backend_value"
}

update_generic_docker_stack() {
  local service_name="$1"
  local current_backend

  if ! docker_service_stack_exists "$service_name"; then
    warn "未找到 ${service_name} 的部署目录：$(docker_stack_dir "$service_name")"
    return 1
  fi

  case "$service_name" in
    sub-web)
      current_backend="$(sub_web_current_backend 2>/dev/null || true)"
      install_sub_web_assets "${current_backend:-api.tsanfer.com:25500}" || return 1
      run_service_compose "$service_name" up -d --build || return 1
      ;;
    *)
      run_service_compose "$service_name" pull || return 1
      run_service_compose "$service_name" up -d || return 1
      ;;
  esac

  log "${service_name} 已更新，部署目录：$(docker_stack_dir "$service_name")"
}

remove_generic_docker_stack() {
  local service_name="$1"

  if docker_service_stack_exists "$service_name"; then
    run_service_compose "$service_name" down || return 1
    log "${service_name} 已停止并移除，部署目录仍保留：$(docker_stack_dir "$service_name")"
    return 0
  fi

  run_privileged docker rm -f "$service_name" 2>/dev/null || run_privileged docker stop "$service_name"
}

install_selected_docker() {
  local selection="$1"
  local service_name
  local compose_path
  local env_path
  local password
  local sudo_password
  local ftp_username
  local ftp_password
  local sub_web_backend
  local webdav_url
  local webdav_user
  local webdav_pass
  local webdav_local_path
  local update_interval

  service_name="$(docker_service_name_by_selection "$selection" 2>/dev/null || true)"
  if [ -z "$service_name" ]; then
    log "错误选项：$selection"
    return 1
  fi

  if [ "$service_name" = "codex2api" ]; then
    install_codex2api_stack
    return $?
  fi

  if [ "$service_name" = "caddy" ]; then
    install_caddy_stack
    return $?
  fi

  compose_path="$(compose_file_path "$service_name")"
  env_path="$(compose_env_path "$service_name")"
  prepare_docker_compose "$service_name" || return 1
  prepare_standard_service_stack_dirs "$service_name"

  case "$selection" in
    0)
      read -r -s -p "设置密码: " password
      echo
      read -r -s -p "设置 sudo 密码: " sudo_password
      echo
      write_env_kv "$env_path" "PASSWORD=$password" "SUDO_PASSWORD=$sudo_password"
      run_service_compose "$service_name" up -d
      ;;
    1|3|4|5|7|8|11)
      run_service_compose "$service_name" up -d
      ;;
    2)
      read -r -p "设置 ftp 用户名: " ftp_username
      read -r -s -p "设置 ftp 密码: " ftp_password
      echo
      write_env_kv "$env_path" "FTP_USER_NAME=$ftp_username" "FTP_USER_PASS=$ftp_password"
      run_service_compose "$service_name" up -d
      ;;
    6)
      sub_web_backend="$(prompt_with_default "设置订阅转换后端地址" "api.tsanfer.com:25500")"
      install_sub_web_assets "$sub_web_backend" || return 1
      run_service_compose "$service_name" up -d
      ;;
    9)
      webdav_url="$(prompt_with_default "输入 webdav 服务器地址(url)" "https://dav.jianguoyun.com/dav/我的坚果云")"
      webdav_user="$(prompt_with_default "输入 webdav 用户名" "a1124851454@gmail.com")"
      read -r -s -p "输入 webdav 密码: " webdav_pass
      echo
      webdav_local_path="$(prompt_with_default "输入 webdav 本地目录" "/mnt/webdav")"
      write_env_kv "$env_path" \
        "WEBDRIVE_URL=$webdav_url" \
        "WEBDRIVE_USERNAME=$webdav_user" \
        "WEBDRIVE_PASSWORD=$webdav_pass" \
        "WEBDRIVE_LOCAL_PATH=$webdav_local_path"
      run_service_compose "$service_name" up -d
      ;;
    10)
      update_interval="$(prompt_with_default "设置 Docker 镜像检查更新频率，单位：秒" "30")"
      write_env_kv "$env_path" "INTERVAL=$update_interval"
      run_service_compose "$service_name" up -d
      ;;
  esac
}

docker_install() {
  print_section "从 Docker compose 部署 docker 容器"
  log "检查 Docker 状态..."

  if ! command_exists docker; then
    warn "Docker 未安装!"
    return 1
  fi

  while true; do
    echo
    log "已安装的 Docker 容器:"
    run_privileged docker ps -a
    render_docker_menu
    read -r -p "选择需要安装的 Docker 容器序号 (q:退出): " input

    case "$input" in
      [qQ])
        break
        ;;
      *)
        install_selected_docker "$input"
        ;;
    esac
  done

  show_docker_inventory
}

docker_update() {
  print_section "更新 docker 镜像和容器"
  log "检查 Docker 状态..."

  if ! command_exists docker; then
    warn "Docker 未安装!"
    return 1
  fi

  echo
  log "已安装的 Docker 容器:"
  run_privileged docker ps -a

  while true; do
    local service_name

    render_docker_menu
    read -r -p "选择需要更新的 Docker 容器序号 (q:退出): " input

    service_name="$(docker_service_name_by_selection "$input" 2>/dev/null || true)"
    case "$input" in
      [qQ])
        break
        ;;
    esac

    case "$service_name" in
      caddy)
        update_caddy_stack
        ;;
      codex2api)
        update_codex2api_stack
        ;;
      "")
        log "错误选项：$input"
        ;;
      *)
        update_generic_docker_stack "$service_name"
        ;;
    esac
  done

  show_docker_inventory
}

docker_remove() {
  local service_name

  print_section "删除 docker 镜像和容器"
  log "检查 Docker 状态..."

  if ! command_exists docker; then
    warn "Docker 未安装!"
    return 1
  fi

  echo
  log "已安装的 Docker 容器:"
  run_privileged docker ps -a

  while true; do
    local service_name

    render_docker_menu
    read -r -p "选择需要删除的 Docker 容器序号 (q:退出): " input

    service_name="$(docker_service_name_by_selection "$input" 2>/dev/null || true)"
    case "$input" in
      [qQ])
        break
        ;;
    esac

    case "$service_name" in
      codex2api)
        remove_codex2api_stack
        ;;
      "")
        log "错误选项：$input"
        ;;
      *)
        remove_generic_docker_stack "$service_name"
        ;;
    esac
  done

  if prompt_yes_no_default_no "是否同时清理未使用的 Docker 镜像和缓存"; then
    run_privileged docker system prune -a -f
  fi
  show_docker_inventory
}

register_module "docker_init" "docker_init" "安装，更新 Docker" "docker_init"
register_module "docker_install" "docker_install" "从 Docker compose 部署 docker 容器" "docker_install"
register_module "docker_update" "docker_update" "更新 docker 镜像和容器" "docker_update"
register_module "docker_remove" "docker_remove" "删除 docker 镜像和容器" "docker_remove"
