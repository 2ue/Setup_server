cleanup_terminal_theme() {
  local zshrc_path="$TARGET_HOME/.zshrc"

  run_privileged rm -rf "$TARGET_HOME/.oh-my-zsh" "$TARGET_HOME/.poshthemes" "$TARGET_HOME/ohmyzsh"
  run_privileged rm -f "$TARGET_HOME/.local/bin/oh-my-posh"

  if [ -f "$zshrc_path" ]; then
    run_privileged sed -i '/oh-my-posh init zsh/d' "$zshrc_path"
    run_privileged sed -i '/export PATH=\$PATH:\$HOME\/.local\/bin/d' "$zshrc_path"
    set_file_owner "$zshrc_path" "$TARGET_USER"
  fi
}

configure_target_zshrc() {
  local zshrc_path="$TARGET_HOME/.zshrc"

  if [ ! -f "$zshrc_path" ]; then
    return 1
  fi

  if grep -q '^plugins=' "$zshrc_path"; then
    run_privileged sed -i 's/^plugins=.*/plugins=(git zsh-autosuggestions zsh-syntax-highlighting)/' "$zshrc_path"
  else
    printf '%s\n' 'plugins=(git zsh-autosuggestions zsh-syntax-highlighting)' | run_privileged tee -a "$zshrc_path" >/dev/null
  fi

  if run_privileged grep -q '^#\s*DISABLE_MAGIC_FUNCTIONS="true"$' "$zshrc_path"; then
    run_privileged sed -i 's/^#\s*DISABLE_MAGIC_FUNCTIONS="true"$/DISABLE_MAGIC_FUNCTIONS="true"/' "$zshrc_path"
  elif ! run_privileged grep -q '^DISABLE_MAGIC_FUNCTIONS="true"$' "$zshrc_path"; then
    printf '%s\n' 'DISABLE_MAGIC_FUNCTIONS="true"' | run_privileged tee -a "$zshrc_path" >/dev/null
  fi

  set_file_owner "$zshrc_path" "$TARGET_USER"
}

ensure_oh_my_posh_initialized() {
  local zshrc_path="$TARGET_HOME/.zshrc"
  local init_line='eval "$(oh-my-posh init zsh --config ~/.poshthemes/craver.omp.json)"'
  local path_line='export PATH=$PATH:$HOME/.local/bin'

  if [ ! -f "$zshrc_path" ]; then
    return 1
  fi

  if ! grep -Fxq "$path_line" "$zshrc_path"; then
    printf '%s\n' "$path_line" | run_privileged tee -a "$zshrc_path" >/dev/null
  fi

  if ! grep -Fxq "$init_line" "$zshrc_path"; then
    printf '%s\n' "$init_line" | run_privileged tee -a "$zshrc_path" >/dev/null
  fi

  set_file_owner "$zshrc_path" "$TARGET_USER"
}

install_oh_my_posh_for_target() {
  local target_bin_dir="$TARGET_HOME/.local/bin"
  local theme_dir="$TARGET_HOME/.poshthemes"
  local theme_zip="$theme_dir/themes.zip"

  ensure_dir "$target_bin_dir" "$TARGET_USER"
  ensure_dir "$theme_dir" "$TARGET_USER"

  if [ "$github_repo" = "github.com" ]; then
    run_as_target_user "mkdir -p ~/.local/bin && curl -fsSL https://ohmyposh.dev/install.sh | bash -s -- -d ~/.local/bin"
  else
    download_to "https://$github_release/JanDeDobbeleer/oh-my-posh/releases/latest/download/posh-linux-amd64" "$target_bin_dir/oh-my-posh" || return 1
    run_privileged chmod +x "$target_bin_dir/oh-my-posh"
    set_file_owner "$target_bin_dir/oh-my-posh" "$TARGET_USER"
  fi

  download_to "https://$github_release/JanDeDobbeleer/oh-my-posh/releases/latest/download/themes.zip" "$theme_zip" || return 1
  run_privileged unzip -oq "$theme_zip" -d "$theme_dir" || return 1
  run_privileged chmod u+rw "$theme_dir"/*.omp.*
  run_privileged rm -f "$theme_zip"
  run_privileged chown -R "$TARGET_USER:$(target_group)" "$theme_dir"

  ensure_oh_my_posh_initialized || return 1
}

term_config() {
  local oh_my_zsh_dir="$TARGET_HOME/.oh-my-zsh"
  local oh_my_zsh_source
  local oh_my_zsh_repo
  local zsh_path

  print_section "配置终端"

  if [ ! -d "$oh_my_zsh_dir" ]; then
    log "oh-my-zsh 未安装"
    run_privileged rm -rf "$oh_my_zsh_dir" "$TARGET_HOME/.zshrc" "$TARGET_HOME/ohmyzsh"

    run_privileged apt-get update -y || return 1
    run_privileged apt-get install -y zsh || return 1

    oh_my_zsh_source="$(resolve_oh_my_zsh_source)" || return 1
    case "$oh_my_zsh_source" in
      github)
        oh_my_zsh_repo="https://github.com/ohmyzsh/ohmyzsh.git"
        ;;
      *)
        oh_my_zsh_repo="https://mirrors.tuna.tsinghua.edu.cn/git/ohmyzsh.git"
        ;;
    esac

    run_as_target_user "rm -rf ~/ohmyzsh && git clone $(shell_quote "$oh_my_zsh_repo") ~/ohmyzsh && cd ~/ohmyzsh/tools && RUNZSH=no REMOTE=$(shell_quote "$oh_my_zsh_repo") sh install.sh" || return 1
    run_as_target_user "git clone https://$github_repo/zsh-users/zsh-autosuggestions ~/.oh-my-zsh/custom/plugins/zsh-autosuggestions" || true
    run_as_target_user "git clone https://$github_repo/zsh-users/zsh-syntax-highlighting.git ~/.oh-my-zsh/custom/plugins/zsh-syntax-highlighting" || true

    configure_target_zshrc || return 1

    zsh_path="$(command -v zsh)"
    if [ -n "$zsh_path" ]; then
      if [ "$(id -un)" = "$TARGET_USER" ]; then
        chsh -s "$zsh_path" || true
      else
        run_privileged chsh -s "$zsh_path" "$TARGET_USER" || true
      fi
    fi

    if [ ! -x "$TARGET_HOME/.local/bin/oh-my-posh" ]; then
      log "oh-my-posh 未安装"
      if prompt_yes_no_default_yes "是否安装 oh-my-posh?"; then
        install_oh_my_posh_for_target || return 1
      fi
    else
      if prompt_yes_no_default_yes "已安装 oh-my-posh, 是否卸载?"; then
        cleanup_terminal_theme
      fi
    fi
  else
    if prompt_yes_no_default_yes "已安装 oh-my-zsh, 是否卸载 oh-my-zsh 和 oh-my-posh ?"; then
      if [ -x "$oh_my_zsh_dir/tools/uninstall.sh" ]; then
        run_as_target_user "~/.oh-my-zsh/tools/uninstall.sh" || true
      fi
      cleanup_terminal_theme
    fi
  fi
}

register_module "term_config" "term_config" "配置终端" "term_config"
