INIT_FLOW=("app_update_init" "swap_set" "vps_reviews" "term_config" "docker_init" "app_install" "docker_install" "change_timezone" "apt_clean" "sys_reboot")

run_init_flow() {
  local module_id

  for module_id in "${INIT_FLOW[@]}"; do
    run_module "$module_id" || return 1
  done
}

show_main_menu() {
  local i
  local module_id

  echo
  log "选择要运行的脚本:"
  print_divider
  for i in "${!MODULE_IDS[@]}"; do
    module_id="${MODULE_IDS[$i]}"
    printf "|%2s.|%-20s|%-s|\n" "$((i + 1))" "${MODULE_TITLES[$i]}" "${MODULE_DESCRIPTIONS[$i]}"
    print_divider
  done
  log "i. 初始化配置脚本"
  print_divider
}

main() {
  local input
  local index
  local module_id

  ensure_supported_os || return 1
  init_runtime
  github_proxy_set

  while true; do
    show_main_menu
    read -r -p "选择要进行的操作 (q:退出): " input

    case "$input" in
      [iI])
        run_init_flow || warn "初始化流程已中断"
        ;;
      [qQ])
        break
        ;;
      *)
        if [[ "$input" =~ ^[0-9]+$ ]]; then
          index=$((input - 1))
          if (( index >= 0 && index < ${#MODULE_IDS[@]} )); then
            module_id="${MODULE_IDS[$index]}"
            run_module "$module_id"
          else
            log "错误选项：$input"
          fi
        else
          log "错误选项：$input"
        fi
        ;;
    esac
  done

  log "Done!!!"
}

main "$@"
