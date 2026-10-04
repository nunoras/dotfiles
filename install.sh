#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
dry_run=false

usage() {
  echo "usage: ./install.sh [--dry-run]"
  echo "Links this repo's configs into ~/.claude, ~/.pi/agent and ~/.agents/skills."
}

for arg in "$@"; do
  case "$arg" in
    --dry-run) dry_run=true ;;
    -h|--help) usage; exit 0 ;;
    *) usage >&2; exit 2 ;;
  esac
done

if [ -t 1 ]; then
  cyan=$'\e[36m' green=$'\e[32m' dim=$'\e[2m' yellow=$'\e[33m' reset=$'\e[0m'
else
  cyan='' green='' dim='' yellow='' reset=''
fi

say() { printf '%s%s%s\n' "$1" "$2" "$reset"; }

link() {
  local link_path="$1" target="$2"

  if [ ! -e "$target" ]; then
    say "$dim" "  skip   (no source) $target"
    return
  fi

  if [ -L "$link_path" ] && [ "$(readlink -f "$link_path")" = "$(readlink -f "$target")" ]; then
    say "$dim" "  ok     $link_path"
    return
  fi

  if $dry_run; then
    say "$yellow" "  WOULD  $link_path -> $target"
    return
  fi

  mkdir -p "$(dirname "$link_path")"

  if [ -e "$link_path" ] || [ -L "$link_path" ]; then
    local backup
    backup="$link_path.bak-$(date +%Y%m%d-%H%M%S)"
    mv "$link_path" "$backup"
    say "$yellow" "  backup $link_path -> $backup"
  fi

  ln -s "$target" "$link_path"
  say "$green" "  link   $link_path -> $target"
}

remove_dangling_repo_links() {
  local dir entry target
  for dir in "$@"; do
    [ -d "$dir" ] || continue
    for entry in "$dir"/* "$dir"/.[!.]*; do
      [ -L "$entry" ] || continue
      target="$(readlink "$entry")"
      case "$target" in "$repo_root"/*) ;; *) continue ;; esac
      [ -e "$target" ] && continue
      if $dry_run; then
        say "$yellow" "  WOULD  remove dangling $entry"
      else
        rm "$entry"
        say "$yellow" "  remove dangling $entry -> $target"
      fi
    done
  done
}

sync_shared_skills() {
  if ! command -v node >/dev/null 2>&1; then
    say "$yellow" "  skip   shared skills (node not found)"
    return
  fi
  say "$cyan" "dotfiles: linking skills into ~/.agents/skills for pi and Codex"
  local sync_args=("$repo_root/ai/scripts/skills-sync.mjs")
  $dry_run && sync_args+=(--dry-run)
  say "$green" "  $(node "${sync_args[@]}" | tail -n 1)"
}

report_missing_tools() {
  local tool
  for tool in git node claude pi codex; do
    command -v "$tool" >/dev/null 2>&1 || say "$yellow" "  missing $tool (not on PATH)"
  done
}

say "$cyan" "dotfiles: checking tools"
report_missing_tools

say "$cyan" "dotfiles: linking configs from $repo_root"

link "$HOME/.claude/CLAUDE.md"                "$repo_root/ai/AGENTS.md"
link "$HOME/.claude/skills"                   "$repo_root/ai/skills"
link "$HOME/.claude/agents"                   "$repo_root/ai/agents"
link "$HOME/.claude/scripts"                  "$repo_root/ai/scripts"
link "$HOME/.claude/settings.json"            "$repo_root/claude/settings.json"
link "$HOME/.claude/statusline.mjs"           "$repo_root/claude/statusline.mjs"
link "$HOME/.claude/pstack-models.md"         "$repo_root/claude/pstack-models.md"

link "$HOME/.pi/agent/AGENTS.md"              "$repo_root/ai/AGENTS.md"
link "$HOME/.pi/agent/settings.json"          "$repo_root/pi/settings.json"
link "$HOME/.pi/agent/extensions"             "$repo_root/pi/extensions"
link "$HOME/.pi/agent/skills"                 "$repo_root/pi/skills"

remove_dangling_repo_links "$HOME/.claude" "$HOME/.claude/hooks" "$HOME/.pi/agent"

sync_shared_skills

say "$cyan" "done."
