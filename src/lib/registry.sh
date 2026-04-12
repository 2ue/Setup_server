# Menu registry used by the main entrypoint.

declare -a MODULE_IDS=()
declare -a MODULE_TITLES=()
declare -a MODULE_DESCRIPTIONS=()
declare -a MODULE_HANDLERS=()

register_module() {
  local module_id="$1"
  local title="$2"
  local description="$3"
  local handler="$4"

  MODULE_IDS+=("$module_id")
  MODULE_TITLES+=("$title")
  MODULE_DESCRIPTIONS+=("$description")
  MODULE_HANDLERS+=("$handler")
}

module_index_by_id() {
  local module_id="$1"
  local i

  for i in "${!MODULE_IDS[@]}"; do
    if [ "${MODULE_IDS[$i]}" = "$module_id" ]; then
      printf '%s\n' "$i"
      return 0
    fi
  done

  return 1
}

run_module() {
  local module_id="$1"
  local module_index
  local handler

  module_index="$(module_index_by_id "$module_id" 2>/dev/null || true)"
  if [ -z "$module_index" ]; then
    warn "未找到模块：$module_id"
    return 1
  fi

  handler="${MODULE_HANDLERS[$module_index]}"
  "$handler"
}
