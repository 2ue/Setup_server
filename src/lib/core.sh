# Core runtime helpers shared by all modules.

github_repo="github.com"
github_release="github.com"
github_raw="raw.githubusercontent.com"

command_exists() {
  command -v "$1" >/dev/null 2>&1
}

log() {
  printf '%s\n' "$*"
}

warn() {
  printf '%s\n' "$*" >&2
}

shell_quote() {
  printf '%q' "$1"
}

run_privileged() {
  if [ "$(id -u)" -eq 0 ]; then
    "$@"
  else
    sudo "$@"
  fi
}

run_as_target_user() {
  local command_text="$1"

  if [ "$(id -un)" = "$TARGET_USER" ]; then
    HOME="$TARGET_HOME" bash -lc "$command_text"
  elif command_exists sudo; then
    sudo -H -u "$TARGET_USER" env HOME="$TARGET_HOME" bash -lc "$command_text"
  else
    su - "$TARGET_USER" -s /bin/bash -c "$command_text"
  fi
}

target_command_exists() {
  local command_name="$1"
  run_as_target_user "command -v $command_name >/dev/null 2>&1"
}

target_group() {
  id -gn "$TARGET_USER"
}

ensure_dir() {
  local dir_path="$1"
  local owner="${2:-}"
  local mode="${3:-755}"

  install -d -m "$mode" "$dir_path"
  if [ -n "$owner" ] && [ "$(id -u)" -eq 0 ]; then
    chown "$owner:$(id -gn "$owner")" "$dir_path"
  fi
}

ensure_privileged_dir() {
  local dir_path="$1"
  local owner="${2:-root}"
  local mode="${3:-755}"

  run_privileged install -d -m "$mode" "$dir_path"
  if [ -n "$owner" ]; then
    run_privileged chown "$owner:$(id -gn "$owner")" "$dir_path"
  fi
}

set_file_owner() {
  local file_path="$1"
  local owner="${2:-$TARGET_USER}"

  if [ -n "$owner" ] && [ "$(id -u)" -eq 0 ]; then
    chown "$owner:$(id -gn "$owner")" "$file_path"
  fi
}

init_runtime() {
  local passwd_entry

  CURRENT_USER="$(id -un)"
  if [ "$CURRENT_USER" = "root" ] && [ -n "${SUDO_USER:-}" ] && [ "$SUDO_USER" != "root" ]; then
    TARGET_USER="$SUDO_USER"
  else
    TARGET_USER="$CURRENT_USER"
  fi

  passwd_entry="$(getent passwd "$TARGET_USER" 2>/dev/null || true)"
  TARGET_HOME="$(printf '%s\n' "$passwd_entry" | cut -d: -f6)"
  if [ -z "$TARGET_HOME" ]; then
    TARGET_HOME="$HOME"
  fi

  SETUP_HOME="$TARGET_HOME/.setup_server"
  DOWNLOAD_DIR="$SETUP_HOME/downloads"
  GENERATED_DIR="$SETUP_HOME/generated"

  ensure_dir "$SETUP_HOME" "$TARGET_USER"
  ensure_dir "$DOWNLOAD_DIR" "$TARGET_USER"
  ensure_dir "$GENERATED_DIR" "$TARGET_USER"
}

setup_preferences_path() {
  printf '%s/%s\n' "$SETUP_HOME" "preferences.conf"
}

setup_preferences_get() {
  local key="$1"
  local config_path

  config_path="$(setup_preferences_path)"
  [ -f "$config_path" ] || return 1

  awk -F= -v key="$key" '
    BEGIN { found = 0 }
    $0 !~ /^[[:space:]]*#/ && $1 == key {
      found = 1
      sub(/^[^=]*=/, "", $0)
      print $0
      exit
    }
    END {
      if (!found) {
        exit 1
      }
    }
  ' "$config_path"
}

setup_preferences_set() {
  local key="$1"
  local value="$2"
  local config_path
  local temp_file

  config_path="$(setup_preferences_path)"
  temp_file="$(mktemp)"

  if [ -f "$config_path" ]; then
    awk -v key="$key" -v value="$value" '
      BEGIN { updated = 0 }
      $0 ~ "^[[:space:]]*" key "=" {
        print key "=" value
        updated = 1
        next
      }
      { print }
      END {
        if (!updated) {
          print key "=" value
        }
      }
    ' "$config_path" >"$temp_file"
  else
    printf '%s=%s\n' "$key" "$value" >"$temp_file"
  fi

  mv "$temp_file" "$config_path"
  chmod 600 "$config_path"
  set_file_owner "$config_path" "$TARGET_USER"
}

normalize_github_proxy_value() {
  case "$1" in
    ask|ASK|prompt|PROMPT)
      printf 'ask\n'
      ;;
    1|true|TRUE|yes|YES|y|Y|on|ON)
      printf 'on\n'
      ;;
    0|false|FALSE|no|NO|n|N|off|OFF)
      printf 'off\n'
      ;;
    *)
      return 1
      ;;
  esac
}

github_proxy_preference() {
  normalize_github_proxy_value "$(setup_preferences_get "SETUP_SERVER_GITHUB_PROXY" 2>/dev/null || true)"
}

set_github_proxy_preference() {
  local enabled

  enabled="$(normalize_github_proxy_value "$1")" || return 1
  setup_preferences_set "SETUP_SERVER_GITHUB_PROXY" "$enabled"
}

apply_github_proxy_preference() {
  local enabled

  enabled="$(normalize_github_proxy_value "$1")" || return 1
  if [ "$enabled" = "ask" ]; then
    return 0
  fi

  if [ "$enabled" = "on" ]; then
    github_repo="gh-proxy.com/github.com"
    github_release="gh-proxy.com/github.com"
    github_raw="gh-proxy.com/raw.githubusercontent.com"
  else
    github_repo="github.com"
    github_release="github.com"
    github_raw="raw.githubusercontent.com"
  fi
}

github_proxy_label() {
  case "$(normalize_github_proxy_value "$1" 2>/dev/null || true)" in
    ask)
      printf '每次询问\n'
      ;;
    on)
      printf '开启\n'
      ;;
    off)
      printf '关闭\n'
      ;;
    *)
      printf '未设置\n'
      ;;
  esac
}

normalize_apt_mirror_mode() {
  case "$1" in
    ask|ASK|prompt|PROMPT)
      printf 'ask\n'
      ;;
    cn|CN|china|CHINA|mirror|MIRROR|yes|YES|y|Y|on|ON|1|true|TRUE)
      printf 'cn\n'
      ;;
    skip|SKIP|no|NO|n|N|off|OFF|0|false|FALSE|official|OFFICIAL)
      printf 'skip\n'
      ;;
    *)
      return 1
      ;;
  esac
}

apt_mirror_mode_preference() {
  normalize_apt_mirror_mode "$(setup_preferences_get "SETUP_SERVER_APT_MIRROR" 2>/dev/null || true)"
}

set_apt_mirror_mode_preference() {
  local mode

  mode="$(normalize_apt_mirror_mode "$1")" || return 1
  setup_preferences_set "SETUP_SERVER_APT_MIRROR" "$mode"
}

apt_mirror_mode_label() {
  case "$(normalize_apt_mirror_mode "$1" 2>/dev/null || true)" in
    ask)
      printf '每次询问\n'
      ;;
    cn)
      printf '使用 LinuxMirrors 国内源\n'
      ;;
    skip)
      printf '不更换系统软件源\n'
      ;;
    *)
      printf '未设置\n'
      ;;
  esac
}

normalize_docker_install_source() {
  case "$1" in
    ask|ASK|prompt|PROMPT)
      printf 'ask\n'
      ;;
    cn|CN|china|CHINA|mirror|MIRROR|yes|YES|y|Y|on|ON|1|true|TRUE)
      printf 'cn\n'
      ;;
    official|OFFICIAL|docker|DOCKER|github|GITHUB|no|NO|n|N|off|OFF|0|false|FALSE)
      printf 'official\n'
      ;;
    *)
      return 1
      ;;
  esac
}

docker_install_source_preference() {
  normalize_docker_install_source "$(setup_preferences_get "SETUP_SERVER_DOCKER_INSTALL_SOURCE" 2>/dev/null || true)"
}

set_docker_install_source_preference() {
  local source

  source="$(normalize_docker_install_source "$1")" || return 1
  setup_preferences_set "SETUP_SERVER_DOCKER_INSTALL_SOURCE" "$source"
}

docker_install_source_label() {
  case "$(normalize_docker_install_source "$1" 2>/dev/null || true)" in
    ask)
      printf '每次询问\n'
      ;;
    cn)
      printf 'LinuxMirrors 国内源\n'
      ;;
    official)
      printf 'Docker 官方安装脚本\n'
      ;;
    *)
      printf '未设置\n'
      ;;
  esac
}

normalize_oh_my_zsh_source() {
  case "$1" in
    ask|ASK|prompt|PROMPT)
      printf 'ask\n'
      ;;
    tuna|TUNA|cn|CN|china|CHINA|mirror|MIRROR)
      printf 'tuna\n'
      ;;
    github|GITHUB|official|OFFICIAL)
      printf 'github\n'
      ;;
    *)
      return 1
      ;;
  esac
}

oh_my_zsh_source_preference() {
  normalize_oh_my_zsh_source "$(setup_preferences_get "SETUP_SERVER_OH_MY_ZSH_SOURCE" 2>/dev/null || true)"
}

set_oh_my_zsh_source_preference() {
  local source

  source="$(normalize_oh_my_zsh_source "$1")" || return 1
  setup_preferences_set "SETUP_SERVER_OH_MY_ZSH_SOURCE" "$source"
}

oh_my_zsh_source_label() {
  case "$(normalize_oh_my_zsh_source "$1" 2>/dev/null || true)" in
    ask)
      printf '每次询问\n'
      ;;
    tuna)
      printf '清华镜像\n'
      ;;
    github)
      printf '官方 GitHub\n'
      ;;
    *)
      printf '未设置\n'
      ;;
  esac
}

resolve_oh_my_zsh_source() {
  local saved_source

  saved_source="$(oh_my_zsh_source_preference 2>/dev/null || true)"
  case "$saved_source" in
    tuna|github)
      printf '%s\n' "$saved_source"
      ;;
    ask)
      if prompt_yes_no_default_yes "安装 oh-my-zsh 时是否使用清华镜像源？"; then
        printf 'tuna\n'
      else
        printf 'github\n'
      fi
      ;;
    *)
      printf 'tuna\n'
      ;;
  esac
}

ensure_supported_os() {
  if [ ! -f /etc/os-release ]; then
    warn "无法识别操作系统 /etc/os-release 文件未找到"
    return 1
  fi

  # shellcheck disable=SC1091
  . /etc/os-release
  if [ "$ID" != "debian" ] && [[ "${ID_LIKE:-}" != *debian* ]]; then
    warn "操作系统不是基于 Debian"
    return 1
  fi

  DEBIAN_VERSION_MAJOR="${VERSION_ID%%.*}"
  log "操作系统基于 Debian"
  return 0
}

github_proxy_fallback_url() {
  local url="$1"

  case "$url" in
    https://gh-proxy.com/*)
      printf 'https://%s\n' "${url#https://gh-proxy.com/}"
      ;;
    http://gh-proxy.com/*)
      printf 'https://%s\n' "${url#http://gh-proxy.com/}"
      ;;
    https://ghfast.top/https://*)
      printf 'https://%s\n' "${url#https://ghfast.top/https://}"
      ;;
    https://ghfast.top/http://*)
      printf 'http://%s\n' "${url#https://ghfast.top/http://}"
      ;;
    *)
      return 1
      ;;
  esac
}

download_to() {
  local url="$1"
  local output_path="$2"
  local fallback_url
  local exit_code

  fallback_url="$(github_proxy_fallback_url "$url" 2>/dev/null || true)"

  if command_exists curl; then
    curl -fsSL "$url" -o "$output_path" && return 0
    exit_code=$?
    if [ -n "$fallback_url" ] && [ "$fallback_url" != "$url" ]; then
      warn "下载失败，尝试回退到官方地址：$fallback_url"
      curl -fsSL "$fallback_url" -o "$output_path"
      return $?
    fi
    return "$exit_code"
  fi

  if command_exists wget; then
    wget -q "$url" -O "$output_path" && return 0
    exit_code=$?
    if [ -n "$fallback_url" ] && [ "$fallback_url" != "$url" ]; then
      warn "下载失败，尝试回退到官方地址：$fallback_url"
      wget -q "$fallback_url" -O "$output_path"
      return $?
    fi
    return "$exit_code"
  fi

  warn "请先安装 curl 或 wget"
  return 1
}

download_to_stdout() {
  local url="$1"
  local fallback_url
  local exit_code

  fallback_url="$(github_proxy_fallback_url "$url" 2>/dev/null || true)"

  if command_exists curl; then
    curl -fsSL "$url" && return 0
    exit_code=$?
    if [ -n "$fallback_url" ] && [ "$fallback_url" != "$url" ]; then
      warn "下载失败，尝试回退到官方地址：$fallback_url"
      curl -fsSL "$fallback_url"
      return $?
    fi
    return "$exit_code"
  fi

  if command_exists wget; then
    wget -qO- "$url" && return 0
    exit_code=$?
    if [ -n "$fallback_url" ] && [ "$fallback_url" != "$url" ]; then
      warn "下载失败，尝试回退到官方地址：$fallback_url"
      wget -qO- "$fallback_url"
      return $?
    fi
    return "$exit_code"
  fi

  warn "请先安装 curl 或 wget"
  return 1
}

run_remote_script() {
  local url="$1"
  local script_path
  local script_name
  local exit_code

  script_name="$(basename "${url%%\?*}")"
  script_name="${script_name:-remote.sh}"
  script_path="$DOWNLOAD_DIR/$script_name"

  download_to "$url" "$script_path" || return 1
  run_privileged chmod +x "$script_path"

  if [[ "$url" == *".sh" ]] || head -n 1 "$script_path" | grep -q '^#!'; then
    bash "$script_path"
  else
    sh "$script_path"
  fi
  exit_code=$?

  return "$exit_code"
}

set_sysctl_value() {
  local key="$1"
  local value="$2"
  local sysctl_file="/etc/sysctl.conf"

  if run_privileged grep -q "^${key}=" "$sysctl_file"; then
    run_privileged sed -i "s/^${key}=.*/${key}=${value}/" "$sysctl_file"
  else
    printf '%s=%s\n' "$key" "$value" | run_privileged tee -a "$sysctl_file" >/dev/null
  fi

  run_privileged sysctl -p
}

install_asset_file() {
  local asset_key="$1"
  local output_path="$2"
  local owner="${3:-$TARGET_USER}"
  local mode="${4:-644}"

  ensure_dir "$(dirname "$output_path")" "${owner:-}"
  write_embedded_asset "$asset_key" "$output_path" || return 1
  run_privileged chmod "$mode" "$output_path"
  if [ -n "$owner" ]; then
    set_file_owner "$output_path" "$owner"
  fi
}

install_asset_file_privileged() {
  local asset_key="$1"
  local output_path="$2"
  local owner="${3:-root}"
  local mode="${4:-644}"
  local temp_file

  temp_file="$(mktemp)"
  write_embedded_asset "$asset_key" "$temp_file" || {
    rm -f "$temp_file"
    return 1
  }

  ensure_privileged_dir "$(dirname "$output_path")" "$owner"
  run_privileged cp "$temp_file" "$output_path"
  run_privileged chmod "$mode" "$output_path"
  if [ -n "$owner" ]; then
    run_privileged chown "$owner:$(id -gn "$owner")" "$output_path"
  fi

  rm -f "$temp_file"
}

github_proxy_set() {
  local saved_value
  local persist_choice

  saved_value="$(github_proxy_preference 2>/dev/null || true)"
  if [ "$saved_value" = "on" ] || [ "$saved_value" = "off" ]; then
    apply_github_proxy_preference "$saved_value"
    return 0
  fi

  persist_choice="1"
  if [ "$saved_value" = "ask" ]; then
    persist_choice="0"
  fi

  while true; do
    read -r -p "是否启用 Github 国内加速? [Y/n] " input
    case "$input" in
      ""|[yY])
        if [ "$persist_choice" = "1" ]; then
          set_github_proxy_preference "on"
        fi
        apply_github_proxy_preference "on"
        break
        ;;
      [nN])
        if [ "$persist_choice" = "1" ]; then
          set_github_proxy_preference "off"
        fi
        apply_github_proxy_preference "off"
        break
        ;;
      *)
        log "错误选项：$input"
        ;;
    esac
  done
}
