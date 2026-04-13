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
    1|true|TRUE|yes|YES|y|Y|on|ON)
      printf '1\n'
      ;;
    0|false|FALSE|no|NO|n|N|off|OFF)
      printf '0\n'
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

  if [ "$enabled" = "1" ]; then
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
    1)
      printf '开启\n'
      ;;
    0)
      printf '关闭\n'
      ;;
    *)
      printf '未设置\n'
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

  saved_value="$(github_proxy_preference 2>/dev/null || true)"
  if [ -n "$saved_value" ]; then
    apply_github_proxy_preference "$saved_value"
    return 0
  fi

  while true; do
    read -r -p "是否启用 Github 国内加速? [Y/n] " input
    case "$input" in
      ""|[yY])
        set_github_proxy_preference "1"
        apply_github_proxy_preference "1"
        break
        ;;
      [nN])
        set_github_proxy_preference "0"
        apply_github_proxy_preference "0"
        break
        ;;
      *)
        log "错误选项：$input"
        ;;
    esac
  done
}
