# Shared interactive helpers.

print_section() {
  printf '\n---------- %s ----------\n\n' "$1"
}

print_divider() {
  printf '%s\n' "----------------------------------------------------------------------"
}

pause_enter() {
  read -r -p "按回车键继续" _
}

prompt_yes_no_default_yes() {
  local prompt_text="$1"

  while true; do
    read -r -p "$prompt_text [Y/n] " input
    case "$input" in
      ""|[yY]) return 0 ;;
      [nN]) return 1 ;;
      *) log "错误选项：$input" ;;
    esac
  done
}

prompt_yes_no_default_no() {
  local prompt_text="$1"

  while true; do
    read -r -p "$prompt_text [y/N] " input
    case "$input" in
      [yY]) return 0 ;;
      ""|[nN]) return 1 ;;
      *) log "错误选项：$input" ;;
    esac
  done
}

prompt_yes_no_with_default() {
  local prompt_text="$1"
  local default_value="$2"
  local prompt_suffix

  case "$default_value" in
    1|true|TRUE|yes|YES|y|Y|on|ON)
      prompt_suffix="[Y/n]"
      default_value="1"
      ;;
    0|false|FALSE|no|NO|n|N|off|OFF)
      prompt_suffix="[y/N]"
      default_value="0"
      ;;
    *)
      warn "无效的默认值：$default_value"
      return 1
      ;;
  esac

  while true; do
    read -r -p "$prompt_text $prompt_suffix " input
    case "$input" in
      "")
        [ "$default_value" = "1" ] && return 0 || return 1
        ;;
      [yY])
        return 0
        ;;
      [nN])
        return 1
        ;;
      *)
        log "错误选项：$input"
        ;;
    esac
  done
}

prompt_with_default() {
  local prompt_text="$1"
  local default_value="$2"
  local user_input

  read -r -p "$prompt_text（默认：$default_value）: " user_input
  if [ -z "$user_input" ]; then
    printf '%s\n' "$default_value"
  else
    printf '%s\n' "$user_input"
  fi
}
