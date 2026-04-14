source_settings_read_value() {
  local prompt_text="$1"
  local default_value="$2"
  local normalizer="$3"
  local options_text="$4"
  local raw_input
  local normalized_value

  while true; do
    read -r -p "$prompt_text（可选：$options_text；默认：$default_value）: " raw_input
    if [ -z "$raw_input" ]; then
      printf '%s\n' "$default_value"
      return 0
    fi

    normalized_value="$("$normalizer" "$raw_input" 2>/dev/null || true)"
    if [ -n "$normalized_value" ]; then
      printf '%s\n' "$normalized_value"
      return 0
    fi

    log "错误选项：$raw_input"
  done
}

configure_source_settings() {
  local config_path
  local github_value
  local apt_value
  local docker_value
  local oh_my_zsh_value

  print_section "下载源与镜像源设置"

  config_path="$(setup_preferences_path)"
  github_value="$(github_proxy_preference 2>/dev/null || true)"
  apt_value="$(apt_mirror_mode_preference 2>/dev/null || true)"
  docker_value="$(docker_install_source_preference 2>/dev/null || true)"
  oh_my_zsh_value="$(oh_my_zsh_source_preference 2>/dev/null || true)"

  log "配置文件：$config_path"
  log "当前 Github 国内加速：$(github_proxy_label "$github_value")"
  log "当前 APT 国内源策略：$(apt_mirror_mode_label "$apt_value")"
  log "当前 Docker 安装源策略：$(docker_install_source_label "$docker_value")"
  log "当前 oh-my-zsh 仓库源：$(oh_my_zsh_source_label "$oh_my_zsh_value")"

  github_value="$(source_settings_read_value "设置 SETUP_SERVER_GITHUB_PROXY" "${github_value:-ask}" "normalize_github_proxy_value" "ask/on/off")" || return 1
  apt_value="$(source_settings_read_value "设置 SETUP_SERVER_APT_MIRROR" "${apt_value:-ask}" "normalize_apt_mirror_mode" "ask/cn/skip")" || return 1
  docker_value="$(source_settings_read_value "设置 SETUP_SERVER_DOCKER_INSTALL_SOURCE" "${docker_value:-ask}" "normalize_docker_install_source" "ask/cn/official")" || return 1
  oh_my_zsh_value="$(source_settings_read_value "设置 SETUP_SERVER_OH_MY_ZSH_SOURCE" "${oh_my_zsh_value:-tuna}" "normalize_oh_my_zsh_source" "ask/tuna/github")" || return 1

  set_github_proxy_preference "$github_value" || return 1
  set_apt_mirror_mode_preference "$apt_value" || return 1
  set_docker_install_source_preference "$docker_value" || return 1
  set_oh_my_zsh_source_preference "$oh_my_zsh_value" || return 1

  case "$github_value" in
    on|off)
      apply_github_proxy_preference "$github_value" || return 1
      ;;
    ask)
      if prompt_yes_no_default_yes "当前这次运行，是否启用 Github 国内加速？"; then
        apply_github_proxy_preference "on" || return 1
      else
        apply_github_proxy_preference "off" || return 1
      fi
      ;;
  esac

  log "已保存下载源相关配置。"
  log "Github 国内加速：$(github_proxy_label "$github_value")"
  log "APT 国内源策略：$(apt_mirror_mode_label "$apt_value")"
  log "Docker 安装源策略：$(docker_install_source_label "$docker_value")"
  log "oh-my-zsh 仓库源：$(oh_my_zsh_source_label "$oh_my_zsh_value")"
}

register_module "source_settings" "source_settings" "配置下载源与镜像源偏好" "configure_source_settings"
