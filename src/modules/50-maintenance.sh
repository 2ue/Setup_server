change_timezone() {
  local timezones=("Asia/Shanghai" "America/New_York" "Europe/London" "Australia/Sydney")
  local chosen_timezone

  print_section "调整时区"
  echo "请选择要设置的时区（或直接输入时区名称）："
  select chosen_timezone in "${timezones[@]}" "输入其他时区"; do
    case "$chosen_timezone" in
      "输入其他时区")
        read -r -p "请输入时区名称：" NEW_TIMEZONE
        break
        ;;
      "")
        log "错误选项：$REPLY"
        ;;
      *)
        NEW_TIMEZONE="$chosen_timezone"
        break
        ;;
    esac
  done

  if ! command_exists timedatectl; then
    warn "timedatectl 命令未找到。请确保已安装 systemd。"
    return 1
  fi

  run_privileged timedatectl set-timezone "$NEW_TIMEZONE"
  log "时区已设置为 $NEW_TIMEZONE"
}

apt_clean() {
  print_section "清理 APT 空间"

  if prompt_yes_no_default_yes "是否清理 APT 空间？"; then
    run_privileged apt clean -y || return 1
    run_privileged apt autoclean -y || return 1
    run_privileged apt autoremove --purge -y || return 1
  fi
}

sys_reboot() {
  print_section "重启系统"

  if prompt_yes_no_default_yes "是否重启系统？"; then
    run_privileged reboot
  fi
}

register_module "change_timezone" "change_timezone" "调整时区" "change_timezone"
register_module "apt_clean" "apt_clean" "清理 APT 空间" "apt_clean"
register_module "sys_reboot" "sys_reboot" "重启系统" "sys_reboot"
