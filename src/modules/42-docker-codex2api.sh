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
  local codex_port
  local admin_secret
  local database_password

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

  while true; do
    read -r -p "设置 codex2api 访问端口（回车自动分配空闲端口）: " codex_port
    if [ -z "$codex_port" ]; then
      break
    fi
    if ! [[ "$codex_port" =~ ^[0-9]+$ ]] || [ "$codex_port" -lt 1 ] || [ "$codex_port" -gt 65535 ]; then
      warn "端口无效：$codex_port，请重新输入"
      continue
    fi
    if port_is_in_use "$codex_port"; then
      warn "端口已被占用：$codex_port，请重新输入"
      continue
    fi
    break
  done

  read -r -s -p "设置 ADMIN_SECRET（回车自动生成）: " admin_secret
  echo
  read -r -s -p "设置数据库密码（回车自动生成）: " database_password
  echo

  printf '%s\n' "$repo_owner|$repo_ref|$ghcr_owner|$image_tag|$project_name|$codex_port|$admin_secret|$database_password"
}

codex2api_configure_env() {
  local env_path="$1"
  local repo_owner="$2"
  local repo_ref="$3"
  local ghcr_owner="$4"
  local image_tag="$5"
  local project_name="$6"
  local codex_port="$7"
  local admin_secret_override="${8:-}"
  local database_password_override="${9:-}"
  local fresh_install="${10:-0}"
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
  ensure_env_value "$env_path" "DATABASE_HOST" "codex2api-postgres"
  ensure_env_value "$env_path" "DATABASE_PORT" "5432"
  ensure_env_value "$env_path" "DATABASE_USER" "codex2api"
  ensure_env_value "$env_path" "DATABASE_NAME" "codex2api"
  ensure_env_value "$env_path" "CACHE_DRIVER" "redis"
  ensure_env_value "$env_path" "REDIS_ADDR" "codex2api-redis:6379"
  ensure_env_value "$env_path" "REDIS_DB" "0"
  ensure_env_value "$env_path" "TZ" "Asia/Shanghai"

  if [ -n "$admin_secret_override" ]; then
    env_upsert_value "$env_path" "ADMIN_SECRET" "$admin_secret_override"
  fi
  admin_secret="$(env_get_value "$env_path" "ADMIN_SECRET" 2>/dev/null || true)"
  if [ "$fresh_install" = "1" ] && codex2api_admin_secret_needs_generation "$admin_secret"; then
    env_upsert_value "$env_path" "ADMIN_SECRET" "$(generate_random_secret 24)"
  elif [ -z "$admin_secret" ]; then
    env_upsert_value "$env_path" "ADMIN_SECRET" "$(generate_random_secret 24)"
  fi

  if [ -n "$database_password_override" ]; then
    env_upsert_value "$env_path" "DATABASE_PASSWORD" "$database_password_override"
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
  local admin_secret
  local database_password
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

  settings="$(codex2api_collect_settings "$env_path")" || return 1
  IFS='|' read -r repo_owner repo_ref ghcr_owner image_tag project_name codex_port admin_secret database_password <<<"$settings"
  if [ -z "$codex_port" ]; then
    codex_port="$(random_available_port)" || return 1
  fi

  codex2api_sync_remote_files "$repo_owner" "$repo_ref" || return 1
  conflict_names="$(compose_conflicting_container_names "$compose_path" "$project_name" 2>/dev/null | sort -u)"
  if [ -n "$conflict_names" ]; then
    warn "检测到已存在的同名容器，已停止安装："
    printf '%s\n' "$conflict_names" >&2
    warn "请先清理这些容器，或修改 COMPOSE_PROJECT_NAME 后再安装。"
    return 1
  fi
  codex2api_configure_env "$env_path" "$repo_owner" "$repo_ref" "$ghcr_owner" "$image_tag" "$project_name" "$codex_port" "$admin_secret" "$database_password" "1"
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
    "" \
    "" \
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
