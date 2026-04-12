APP_KEYS=("mw" "bt" "1pctl" "kubesphere")
APP_INFOS=("一款简单Linux面板服务" "aaPanel面板（宝塔国外版）" "现代化、开源的 Linux 服务器运维管理面板" "在 Kubernetes 之上构建的面向云原生应用的分布式操作系统")

print_installed_apps() {
  local i

  log "已安装的自选软件:"
  for i in "${!APP_KEYS[@]}"; do
    case "${APP_KEYS[$i]}" in
      mw|bt|1pctl)
        if command_exists "${APP_KEYS[$i]}"; then
          log "${APP_INFOS[$i]} 已安装"
        fi
        ;;
    esac
  done
}

render_app_menu() {
  local i

  for i in "${!APP_KEYS[@]}"; do
    printf "%2s. %-20s%s\n" "$i" "${APP_KEYS[$i]}" "${APP_INFOS[$i]}"
  done
}

install_selected_app() {
  local selection="$1"
  local script_path

  case "$selection" in
    0)
      run_remote_script "https://$github_raw/midoks/mdserver-web/master/scripts/install.sh"
      ;;
    1)
      script_path="$DOWNLOAD_DIR/install_panel.sh"
      download_to "https://download.bt.cn/install/install_panel.sh" "$script_path" || return 1
      bash "$script_path" ed8484bec
      ;;
    2)
      run_remote_script "https://resource.fit2cloud.com/1panel/package/v2/quick_start.sh"
      ;;
    3)
      run_privileged apt-get -y install socat conntrack ebtables ipset || return 1
      (
        cd "$DOWNLOAD_DIR" || exit 1
        download_to_stdout "https://get-kk.kubesphere.io" | sh -
      ) || return 1
      run_privileged chmod +x "$DOWNLOAD_DIR/kk"
      "$DOWNLOAD_DIR/kk" create cluster --with-kubernetes v1.24.14 --container-manager containerd --with-kubesphere v3.4.0
      ;;
    *)
      log "错误选项：$selection"
      ;;
  esac
}

remove_selected_app() {
  local selection="$1"
  local script_path

  case "$selection" in
    0)
      script_path="$DOWNLOAD_DIR/mdserver-uninstall.sh"
      download_to "https://raw.githubusercontent.com/midoks/mdserver-web/master/scripts/uninstall.sh" "$script_path" || return 1
      bash "$script_path"
      ;;
    1)
      script_path="$DOWNLOAD_DIR/bt-uninstall.sh"
      download_to "http://download.bt.cn/install/bt-uninstall.sh" "$script_path" || return 1
      sh "$script_path"
      ;;
    2)
      1pctl uninstall
      ;;
    [qQ])
      return 0
      ;;
    *)
      log "错误选项：$selection"
      ;;
  esac
}

app_install() {
  print_section "自选软件安装"

  while true; do
    echo
    print_installed_apps
    echo
    render_app_menu
    read -r -p "选择需要安装的软件序号 (q:退出): " input

    case "$input" in
      [qQ])
        break
        ;;
      *)
        install_selected_app "$input"
        ;;
    esac
  done
}

app_remove() {
  print_section "自选软件卸载"

  while true; do
    echo
    print_installed_apps
    echo
    render_app_menu
    read -r -p "选择需要卸载的软件序号 (q:退出): " input

    case "$input" in
      [qQ])
        break
        ;;
      *)
        remove_selected_app "$input"
        ;;
    esac
  done
}

register_module "app_install" "app_install" "自选软件安装" "app_install"
register_module "app_remove" "app_remove" "自选软件卸载" "app_remove"
