install_bottom_if_needed() {
  local package_path="$DOWNLOAD_DIR/bottom_0.10.2-1_amd64.deb"
  local config_dir="$TARGET_HOME/.config/bottom"
  local config_file="$config_dir/bottom.toml"

  if command_exists btm; then
    log "已安装 bottom"
    return 0
  fi

  download_to "https://$github_release/ClementTsang/bottom/releases/download/0.10.2/bottom_0.10.2-1_amd64.deb" "$package_path" || return 1
  run_privileged dpkg -i "$package_path" || run_privileged apt-get install -f -y

  ensure_dir "$config_dir" "$TARGET_USER"
  cat >"$config_file" <<'EOF'
[flags]
enable_cache_memory = true
network_use_bytes = true
process_command = true
EOF
  run_privileged chmod 644 "$config_file"
  set_file_owner "$config_file" "$TARGET_USER"
}

install_fastfetch_if_needed() {
  local package_path="$DOWNLOAD_DIR/fastfetch-linux-amd64.deb"
  local fastfetch_version

  if command_exists fastfetch; then
    log "已安装 fastfetch"
    return 0
  fi

  if [ "${DEBIAN_VERSION_MAJOR:-0}" -ge 13 ]; then
    if run_privileged apt -y install fastfetch; then
      return 0
    fi
    fastfetch_version="2.52.0"
  elif [ "${DEBIAN_VERSION_MAJOR:-0}" -eq 11 ] || [ "${DEBIAN_VERSION_MAJOR:-0}" -eq 12 ]; then
    fastfetch_version="2.40.4"
  else
    warn "Unsupported Debian version: ${DEBIAN_VERSION_MAJOR:-unknown}"
    return 1
  fi

  download_to "https://$github_release/fastfetch-cli/fastfetch/releases/download/${fastfetch_version}/fastfetch-linux-amd64.deb" "$package_path" || return 1
  run_privileged dpkg -i "$package_path" || run_privileged apt-get install -f -y
}

install_target_vimrc_if_needed() {
  local vimrc_path="$TARGET_HOME/.vimrc"

  if [ -f "$vimrc_path" ]; then
    log "[提示] $vimrc_path 已存在，跳过下载。"
    return 0
  fi

  log "[写入] 正在部署 Vim 配置文件 → $vimrc_path ..."
  install_asset_file "vimrc" "$vimrc_path" "$TARGET_USER" 644
}

app_update_init() {
  local apt_mirror_mode

  print_section "APT 软件更新、默认软件安装"

  apt_mirror_mode="$(apt_mirror_mode_preference 2>/dev/null || true)"
  case "$apt_mirror_mode" in
    cn)
      run_remote_script "https://linuxmirrors.cn/main.sh" || return 1
      ;;
    skip)
      ;;
    *)
      if prompt_yes_no_default_yes "是否使用 LinuxMirrors 脚本，更换国内软件源?（需使用 ROOT 用户执行此脚本）"; then
        run_remote_script "https://linuxmirrors.cn/main.sh" || return 1
      fi
      ;;
  esac

  run_privileged apt -y update || return 1
  run_privileged apt -y upgrade || return 1
  run_privileged apt -y install sudo curl wget zsh git vim unzip bc rsync jq htop sysstat || return 1

  install_bottom_if_needed || return 1
  install_fastfetch_if_needed || return 1
  install_target_vimrc_if_needed || return 1

  if command_exists fastfetch; then
    fastfetch -s \
      title:os:kernel:host:board:bios:bootmgr:uptime:packages:shell:cpu:cpucache:gpu:opengl:opencl:vulkan:memory:physicalmemory:swap:disk:physicaldisk:btrfs:zpool:gamepad:display:wifi:localip:publicip:bluetoothradio:battery:poweradapter:loadavg:processes:dateTime:locale:camera:tpm:editor:command:colors:break \
      --cpu-temp --gpu-temp --physicaldisk-temp --battery-temp
  fi

  pause_enter
}

clear_swap_files() {
  run_privileged swapoff -a || return 1
  run_privileged sh -c "awk '/swap/ {print \$1}' /etc/fstab | xargs -r rm -f"
  run_privileged sed -i '/[[:space:]]swap[[:space:]]/d' /etc/fstab
}

swap_set() {
  local swap_size
  local swap_enable_threshold

  print_section "设置 swap 内存"
  free -h

  while true; do
    read -r -p "配置 swap 功能 (Y:覆盖/n:关闭/q:跳过): " input
    case "$input" in
      ""|[yY])
        if ! clear_swap_files; then
          warn "释放 swap 内存失败，请尝试预留更多物理内存后重试"
          continue
        fi

        read -r -p "设置 swap 大小 (单位 MB): " swap_size
        read -r -p "设置内存剩余小于百分之多少时，才启用 swap (单位 %): " swap_enable_threshold

        run_privileged dd if=/dev/zero of=/var/swap bs=1M count="$swap_size" status=progress || return 1
        run_privileged chmod 600 /var/swap
        run_privileged mkswap /var/swap
        set_sysctl_value "vm.swappiness" "$swap_enable_threshold" || return 1
        run_privileged swapon /var/swap
        printf '%s\n' "/var/swap swap swap defaults 0 0" | run_privileged tee -a /etc/fstab >/dev/null
        break
        ;;
      [nN])
        if ! clear_swap_files; then
          warn "释放 swap 内存失败，请尝试预留更多物理内存后重试"
        fi
        break
        ;;
      [qQ])
        break
        ;;
      *)
        log "错误选项：$input"
        ;;
    esac
  done
}

vps_reviews() {
  local goecs_script="$DOWNLOAD_DIR/goecs.sh"

  print_section "VPS 融合怪脚本服务器测试"

  if command_exists goecs; then
    log "goecs 命令已安装，路径为：$(command -v goecs)"
  else
    log "goecs 命令未安装，开始安装 goecs"
    download_to "https://cnb.cool/oneclickvirt/ecs/-/git/raw/main/goecs.sh" "$goecs_script" || return 1
    run_privileged chmod +x "$goecs_script"
    export noninteractive=true
    bash "$goecs_script" env || return 1
    bash "$goecs_script" install || return 1
  fi

  goecs -diskmc=true
  pause_enter
}

register_module "app_update_init" "app_update_init" "APT 软件更新、默认软件安装" "app_update_init"
register_module "swap_set" "swap_set" "设置 swap 内存" "swap_set"
register_module "vps_reviews" "vps_reviews" "服务器测试" "vps_reviews"
