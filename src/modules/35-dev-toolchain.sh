volta_home() {
  printf '%s/.volta\n' "$TARGET_HOME"
}

volta_bin_path() {
  printf '%s/bin/volta\n' "$(volta_home)"
}

target_login_shell() {
  getent passwd "$TARGET_USER" | cut -d: -f7
}

run_with_volta() {
  local command_text="$1"
  run_as_target_user "export VOLTA_HOME=\$HOME/.volta; export PATH=\$VOLTA_HOME/bin:\$PATH; $command_text"
}

volta_command_exists() {
  local command_name="$1"
  run_with_volta "command -v $(shell_quote "$command_name") >/dev/null 2>&1"
}

volta_tool_version() {
  local command_name="$1"
  local version_text

  version_text="$(run_with_volta "$command_name --version" 2>/dev/null | head -n 1 || true)"
  if [ -z "$version_text" ]; then
    version_text="$(run_with_volta "$command_name -V" 2>/dev/null | head -n 1 || true)"
  fi
  if [ -z "$version_text" ]; then
    version_text="$(run_with_volta "$command_name version" 2>/dev/null | head -n 1 || true)"
  fi

  printf '%s\n' "$version_text"
}

ensure_volta_installed() {
  local current_version
  local shell_path

  if [ -x "$(volta_bin_path)" ]; then
    current_version="$(run_with_volta "volta --version" 2>/dev/null | head -n 1 || true)"
    if [ -n "$current_version" ]; then
      log "Volta 已安装：$current_version"
    else
      log "Volta 已安装"
    fi
  else
    log "Volta 未安装，开始安装"
  fi

  shell_path="$(target_login_shell)"
  if [ -z "$shell_path" ]; then
    shell_path="/bin/bash"
  fi

  run_as_target_user "export SHELL=$(shell_quote "$shell_path"); curl -fsSL https://get.volta.sh | bash" || return 1
  current_version="$(run_with_volta "volta --version" 2>/dev/null | head -n 1 || true)"
  if [ -n "$current_version" ]; then
    log "Volta 当前版本：$current_version"
  fi
}

ensure_node22_default() {
  local current_version

  current_version="$(run_with_volta "node -v" 2>/dev/null | tr -d '\r' || true)"

  if [ -n "$current_version" ]; then
    log "当前默认 Node：$current_version，执行 volta install node@22"
  else
    log "未检测到默认 Node，开始安装 Node 22"
  fi

  run_with_volta "volta install node@22" || return 1
  log "Node 当前版本：$(run_with_volta "node -v" 2>/dev/null | tr -d '\r')"
}

ensure_volta_package() {
  local package_spec="$1"
  local command_name="$2"
  local display_name="$3"
  local current_version

  if volta_command_exists "$command_name"; then
    current_version="$(volta_tool_version "$command_name")"
    if [ -n "$current_version" ]; then
      log "$display_name 已安装：$current_version"
    else
      log "$display_name 已安装"
    fi
  else
    log "$display_name 未安装，开始安装"
  fi

  run_with_volta "volta install $package_spec" || return 1

  current_version="$(volta_tool_version "$command_name")"
  if [ -n "$current_version" ]; then
    log "$display_name 当前版本：$current_version"
  else
    log "$display_name 安装完成"
  fi
}

prompt_auth_type() {
  while true; do
    read -r -p "认证类型 [password/digest]（默认：password）: " auth_type
    case "$auth_type" in
      ""|password|digest)
        printf '%s\n' "${auth_type:-password}"
        return 0
        ;;
      *)
        log "错误选项：$auth_type"
        ;;
    esac
  done
}

configure_ccman_sync() {
  local webdav_url
  local username
  local password
  local auth_type
  local remote_dir
  local sync_password
  local remember_flag="--remember-sync-password"
  local config_command

  if ! volta_command_exists "ccman"; then
    warn "ccman 未安装，跳过同步配置"
    return 1
  fi

  if ! prompt_yes_no_default_no "是否配置 ccman WebDAV 同步？"; then
    return 0
  fi

  webdav_url="$(prompt_with_default "输入 WebDAV 地址" "https://dav.example.com")"
  username="$(prompt_with_default "输入 WebDAV 用户名" "alice")"
  read -r -s -p "输入 WebDAV 密码: " password
  echo
  auth_type="$(prompt_auth_type)"
  remote_dir="$(prompt_with_default "输入远程同步目录" "/ccman")"
  read -r -s -p "输入同步加密密码: " sync_password
  echo

  if ! prompt_yes_no_default_yes "是否记住同步密码？"; then
    remember_flag="--forget-sync-password"
  fi

  config_command="ccman sync config \
    --webdav-url $(shell_quote "$webdav_url") \
    --username $(shell_quote "$username") \
    --password $(shell_quote "$password") \
    --auth-type $(shell_quote "$auth_type") \
    --remote-dir $(shell_quote "$remote_dir") \
    --sync-password $(shell_quote "$sync_password") \
    $remember_flag"

  run_with_volta "$config_command" || return 1

  if prompt_yes_no_default_yes "是否立即从 WebDAV 下载配置？"; then
    run_with_volta "ccman sync download --yes" || return 1
  fi
}

dev_toolchain() {
  print_section "安装/更新开发工具链"

  if ! target_command_exists curl; then
    warn "当前模块按官方方式使用 curl 安装 Volta，请先安装 curl"
    return 1
  fi

  ensure_volta_installed || return 1
  ensure_node22_default || return 1
  ensure_volta_package "ccman" "ccman" "ccman" || return 1
  ensure_volta_package "@openai/codex" "codex" "OpenAI Codex CLI" || return 1
  ensure_volta_package "@anthropic-ai/claude-code" "claude" "Claude Code" || return 1
  configure_ccman_sync || return 1

  log "开发工具链安装完成。如当前 shell 未立即生效，可执行 source ~/.zshrc 或重新打开终端。"
}

register_module "dev_toolchain" "dev_toolchain" "安装/更新 Volta、Node.js、ccman、Codex、Claude Code" "dev_toolchain"
