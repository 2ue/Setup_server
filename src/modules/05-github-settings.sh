configure_github_settings() {
  local current_value
  local new_value

  print_section "Github 下载设置"

  current_value="$(github_proxy_preference 2>/dev/null || true)"
  if [ -z "$current_value" ]; then
    current_value="1"
  fi

  log "当前 Github 国内加速：$(github_proxy_label "$current_value")"

  if prompt_yes_no_with_default "后续运行脚本时，是否启用 Github 国内加速？" "$current_value"; then
    new_value="1"
  else
    new_value="0"
  fi

  set_github_proxy_preference "$new_value" || return 1
  apply_github_proxy_preference "$new_value" || return 1

  log "已保存 Github 下载设置：$(github_proxy_label "$new_value")"
  log "配置文件：$(setup_preferences_path)"
}

register_module "github_settings" "github_settings" "修改并记住 Github 国内加速开关" "configure_github_settings"
