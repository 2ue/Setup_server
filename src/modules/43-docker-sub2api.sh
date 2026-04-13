sub2api_stack_dir() {
  docker_stack_dir "sub2api"
}

sub2api_compose_path() {
  printf '%s/%s\n' "$(sub2api_stack_dir)" "docker-compose.yml"
}

sub2api_env_path() {
  printf '%s/%s\n' "$(sub2api_stack_dir)" ".env"
}

sub2api_env_example_path() {
  printf '%s/%s\n' "$(sub2api_stack_dir)" ".env.example"
}

sub2api_install_info_path() {
  printf '%s/%s\n' "$(sub2api_stack_dir)" "INSTALL_INFO.txt"
}

sub2api_stack_exists() {
  [ -f "$(sub2api_compose_path)" ] && [ -f "$(sub2api_env_path)" ]
}

sub2api_has_existing_stack_files() {
  [ -f "$(sub2api_compose_path)" ] \
    || [ -f "$(sub2api_env_path)" ] \
    || [ -f "$(sub2api_env_example_path)" ] \
    || [ -f "$(sub2api_install_info_path)" ]
}

sub2api_existing_data_dirs() {
  local stack_dir="$1"
  local dir_path

  for dir_path in \
    "$stack_dir/data" \
    "$stack_dir/postgres_data" \
    "$stack_dir/redis_data"
  do
    if [ -f "$dir_path/PG_VERSION" ] || dir_has_entries "$dir_path"; then
      printf '%s\n' "$dir_path"
    fi
  done
}

sub2api_postgres_password_needs_generation() {
  case "$1" in
    ""|"change_this_secure_password"|"changeme"|"your_password"|"your-strong-password")
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

sub2api_generate_random_email() {
  local random_part
  random_part="$(generate_random_secret 8 | tr 'A-Z' 'a-z')"
  printf 'admin_%s@sub2api.local\n' "$random_part"
}

sub2api_sync_remote_files() {
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

  stack_dir="$(sub2api_stack_dir)"
  compose_path="$(sub2api_compose_path)"
  env_path="$(sub2api_env_path)"
  env_example_path="$(sub2api_env_example_path)"
  temp_compose="$(mktemp)"
  temp_env="$(mktemp)"
  compose_url="https://$github_raw/$repo_owner/sub2api/$repo_ref/deploy/docker-compose.local.yml"
  env_url="https://$github_raw/$repo_owner/sub2api/$repo_ref/deploy/.env.example"

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

sub2api_collect_settings() {
  local env_path="$1"
  local repo_owner
  local repo_ref
  local sub2api_port
  local admin_email
  local admin_password

  repo_owner="$(env_value_or_default "$env_path" "SETUP_SERVER_REPO_OWNER" "Wei-Shaw")"
  repo_ref="$(env_value_or_default "$env_path" "SETUP_SERVER_REPO_REF" "main")"

  if ! prompt_yes_no_default_yes "使用默认/当前 sub2api 部署参数"; then
    repo_owner="$(prompt_with_default "设置 sub2api 仓库 owner" "$repo_owner")"
    repo_ref="$(prompt_with_default "设置 sub2api 仓库分支或 tag" "$repo_ref")"
  fi

  while true; do
    read -r -p "设置 sub2api 访问端口（回车自动分配空闲端口）: " sub2api_port
    if [ -z "$sub2api_port" ]; then
      break
    fi
    if ! [[ "$sub2api_port" =~ ^[0-9]+$ ]] || [ "$sub2api_port" -lt 1 ] || [ "$sub2api_port" -gt 65535 ]; then
      warn "端口无效：$sub2api_port，请重新输入"
      continue
    fi
    if port_is_in_use "$sub2api_port"; then
      warn "端口已被占用：$sub2api_port，请重新输入"
      continue
    fi
    break
  done

  read -r -p "设置管理员邮箱（回车随机生成）: " admin_email
  read -r -s -p "设置管理员密码（回车随机生成）: " admin_password
  echo

  printf '%s\n' "$repo_owner|$repo_ref|$sub2api_port|$admin_email|$admin_password"
}

sub2api_configure_env() {
  local env_path="$1"
  local repo_owner="$2"
  local repo_ref="$3"
  local sub2api_port="$4"
  local admin_email="${5:-}"
  local admin_password="${6:-}"
  local fresh_install="${7:-0}"
  local postgres_password
  local jwt_secret
  local totp_key

  env_upsert_value "$env_path" "SETUP_SERVER_REPO_OWNER" "$repo_owner"
  env_upsert_value "$env_path" "SETUP_SERVER_REPO_REF" "$repo_ref"
  env_upsert_value "$env_path" "SERVER_PORT" "$sub2api_port"
  ensure_env_value "$env_path" "TZ" "Asia/Shanghai"

  if [ -n "$admin_email" ]; then
    env_upsert_value "$env_path" "ADMIN_EMAIL" "$admin_email"
  elif [ "$fresh_install" = "1" ]; then
    env_upsert_value "$env_path" "ADMIN_EMAIL" "$(sub2api_generate_random_email)"
  fi

  if [ -n "$admin_password" ]; then
    env_upsert_value "$env_path" "ADMIN_PASSWORD" "$admin_password"
  elif [ "$fresh_install" = "1" ]; then
    env_upsert_value "$env_path" "ADMIN_PASSWORD" "$(generate_random_secret 16)"
  fi

  postgres_password="$(env_get_value "$env_path" "POSTGRES_PASSWORD" 2>/dev/null || true)"
  if [ "$fresh_install" = "1" ] && sub2api_postgres_password_needs_generation "$postgres_password"; then
    env_upsert_value "$env_path" "POSTGRES_PASSWORD" "$(generate_random_secret 24)"
  elif [ -z "$postgres_password" ]; then
    env_upsert_value "$env_path" "POSTGRES_PASSWORD" "$(generate_random_secret 24)"
  fi

  jwt_secret="$(env_get_value "$env_path" "JWT_SECRET" 2>/dev/null || true)"
  if [ -z "$jwt_secret" ]; then
    env_upsert_value "$env_path" "JWT_SECRET" "$(generate_random_secret 64)"
  fi

  totp_key="$(env_get_value "$env_path" "TOTP_ENCRYPTION_KEY" 2>/dev/null || true)"
  if [ -z "$totp_key" ]; then
    env_upsert_value "$env_path" "TOTP_ENCRYPTION_KEY" "$(generate_random_secret 64)"
  fi

  run_privileged chmod 600 "$env_path"
  run_privileged chown root:root "$env_path"
}

sub2api_prepare_stack_dirs() {
  local stack_dir="$1"

  ensure_privileged_dir "$stack_dir/data" "root"
  ensure_privileged_dir "$stack_dir/postgres_data" "root"
  ensure_privileged_dir "$stack_dir/redis_data" "root"
}

sub2api_write_install_info() {
  local stack_dir="$1"
  local env_path="$2"
  local sub2api_port="$3"
  local info_path
  local admin_email
  local admin_password
  local postgres_password
  local jwt_secret
  local totp_key
  local temp_file

  info_path="$(sub2api_install_info_path)"
  admin_email="$(env_get_value "$env_path" "ADMIN_EMAIL" 2>/dev/null || true)"
  admin_password="$(env_get_value "$env_path" "ADMIN_PASSWORD" 2>/dev/null || true)"
  postgres_password="$(env_get_value "$env_path" "POSTGRES_PASSWORD" 2>/dev/null || true)"
  jwt_secret="$(env_get_value "$env_path" "JWT_SECRET" 2>/dev/null || true)"
  totp_key="$(env_get_value "$env_path" "TOTP_ENCRYPTION_KEY" 2>/dev/null || true)"
  temp_file="$(mktemp)"

  cat >"$temp_file" <<EOF
sub2api 部署信息

部署目录: $stack_dir
访问地址: http://localhost:$sub2api_port

ADMIN_EMAIL=$admin_email
ADMIN_PASSWORD=$admin_password
POSTGRES_PASSWORD=$postgres_password
JWT_SECRET=$jwt_secret
TOTP_ENCRYPTION_KEY=$totp_key
EOF

  run_privileged mv "$temp_file" "$info_path"
  run_privileged chmod 600 "$info_path"
  run_privileged chown root:root "$info_path"
}

install_sub2api_stack() {
  local stack_dir
  local compose_path
  local env_path
  local settings
  local repo_owner
  local repo_ref
  local sub2api_port
  local admin_email
  local admin_password
  local conflict_names
  local existing_data_dirs

  stack_dir="$(sub2api_stack_dir)"
  compose_path="$(sub2api_compose_path)"
  env_path="$(sub2api_env_path)"
  ensure_privileged_dir "$(docker_stack_root)" "root"
  ensure_privileged_dir "$stack_dir" "root"

  if sub2api_stack_exists; then
    warn "sub2api 已存在：$stack_dir"
    log "请使用“更新 docker 镜像和容器”来刷新现有服务。"
    log "当前访问地址：http://localhost:$(env_value_or_default "$env_path" "SERVER_PORT" "8080")"
    return 0
  fi

  if sub2api_has_existing_stack_files; then
    warn "检测到已有 sub2api 部署文件：$stack_dir"
    log "为避免覆盖现有 compose/.env 文件，安装已停止。"
    log "如为现有部署，请改用“更新 docker 镜像和容器”；如需重装，请先清理 $stack_dir 下的部署文件。"
    return 1
  fi

  existing_data_dirs="$(sub2api_existing_data_dirs "$stack_dir" | sort -u)"
  if [ -n "$existing_data_dirs" ]; then
    warn "检测到已存在的数据目录，可能之前已经部署过 sub2api："
    printf '%s\n' "$existing_data_dirs" >&2
    warn "继续安装可能导致新 .env 与旧数据不一致。"
    log "如需保留旧数据，请恢复原 .env 后执行“更新 docker 镜像和容器”。"
    log "如无需保留旧数据，请先清理上述目录后再重装。"
    return 1
  fi

  settings="$(sub2api_collect_settings "$env_path")" || return 1
  IFS='|' read -r repo_owner repo_ref sub2api_port admin_email admin_password <<<"$settings"
  if [ -z "$sub2api_port" ]; then
    sub2api_port="$(random_available_port)" || return 1
  fi

  sub2api_sync_remote_files "$repo_owner" "$repo_ref" || return 1
  conflict_names="$(compose_conflicting_container_names "$compose_path" "sub2api" 2>/dev/null | sort -u)"
  if [ -n "$conflict_names" ]; then
    warn "检测到已存在的同名容器，已停止安装："
    printf '%s\n' "$conflict_names" >&2
    warn "请先清理这些容器后再安装。"
    return 1
  fi
  sub2api_configure_env "$env_path" "$repo_owner" "$repo_ref" "$sub2api_port" "$admin_email" "$admin_password" "1"
  sub2api_prepare_stack_dirs "$stack_dir"

  run_service_compose "sub2api" pull || return 1
  run_service_compose "sub2api" up -d || return 1
  sub2api_write_install_info "$stack_dir" "$env_path" "$sub2api_port"
  log "sub2api 已部署，配置目录：$stack_dir"
  log "访问地址：http://localhost:$sub2api_port"
  log "管理员邮箱：$(env_get_value "$env_path" "ADMIN_EMAIL" 2>/dev/null || true)"
  log "管理员密码：$(env_get_value "$env_path" "ADMIN_PASSWORD" 2>/dev/null || true)"
  log "数据库密码、JWT_SECRET、TOTP_ENCRYPTION_KEY 等已写入：$env_path"
  log "安装信息文件：$(sub2api_install_info_path)"
}

update_sub2api_stack() {
  local stack_dir
  local env_path
  local repo_owner
  local repo_ref
  local sub2api_port

  stack_dir="$(sub2api_stack_dir)"
  env_path="$(sub2api_env_path)"

  if [ ! -f "$env_path" ]; then
    warn "未找到 sub2api 的部署目录：$stack_dir"
    return 1
  fi

  repo_owner="$(env_value_or_default "$env_path" "SETUP_SERVER_REPO_OWNER" "Wei-Shaw")"
  repo_ref="$(env_value_or_default "$env_path" "SETUP_SERVER_REPO_REF" "main")"
  sub2api_port="$(env_value_or_default "$env_path" "SERVER_PORT" "")"

  if [ -z "$sub2api_port" ] || ! [[ "$sub2api_port" =~ ^[0-9]+$ ]] || [ "$sub2api_port" -lt 1 ] || [ "$sub2api_port" -gt 65535 ]; then
    sub2api_port="$(random_available_port)" || return 1
  fi

  sub2api_sync_remote_files "$repo_owner" "$repo_ref" || return 1
  sub2api_configure_env "$env_path" "$repo_owner" "$repo_ref" "$sub2api_port" "" "" "0"
  sub2api_prepare_stack_dirs "$stack_dir"

  run_service_compose "sub2api" pull || return 1
  run_service_compose "sub2api" up -d || return 1
  sub2api_write_install_info "$stack_dir" "$env_path" "$sub2api_port"
  log "sub2api 已更新，配置目录：$stack_dir"
  log "访问地址：http://localhost:$sub2api_port"
  log "安装信息文件：$(sub2api_install_info_path)"
}

remove_sub2api_stack() {
  local stack_dir

  stack_dir="$(sub2api_stack_dir)"

  if [ ! -f "$(sub2api_compose_path)" ]; then
    warn "未找到 sub2api 的部署目录：$stack_dir"
    return 1
  fi

  run_service_compose "sub2api" down || return 1
  log "sub2api 容器已停止并移除，数据目录仍保留：$stack_dir"
}
