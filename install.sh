#!/usr/bin/env bash
#
# Omarchy Rob plugins installer
#
# Installs Rob's bar, clock, menu, system-updates, vitals, and workspaces
# plugins into ~/.config/omarchy/plugins/.
#
# Idempotent: safe to re-run. Plugins are overwritten in place.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGINS_DIR="$SCRIPT_DIR/plugins"
BIN_DIR="$SCRIPT_DIR/bin"

C_RESET=$'\033[0m'; C_BOLD=$'\033[1m'
C_GREEN=$'\033[32m'; C_YELLOW=$'\033[33m'; C_RED=$'\033[31m'; C_CYAN=$'\033[36m'

info() { printf '%s\n' "${C_CYAN}==>${C_RESET} ${C_BOLD}$*${C_RESET}"; }
ok()   { printf '%s\n' "${C_GREEN}  ✓${C_RESET} $*"; }
warn() { printf '%s\n' "${C_YELLOW}  !${C_RESET} $*"; }
fail() { printf '%s\n' "${C_RED}  ✗${C_RESET} $*" >&2; }
die()  { fail "$*"; exit 1; }

bundle() {
  printf '\n%s\n' "${C_BOLD}$*${C_RESET}"
}

require() {
  if ! command -v "$1" >/dev/null 2>&1; then
    die "Required command '$1' not found. $2"
  fi
}

prune_backups() {
  local dst="$1"
  local dir; dir="$(dirname "$dst")"
  local name; name="$(basename "$dst")"
  local newest
  newest="$(find "$dir" -maxdepth 1 -name "$name.bak.*" -printf '%T@ %p\n' 2>/dev/null | sort -nr | head -n1 | cut -d' ' -f2-)"
  if [[ -z "$newest" ]]; then
    return 0
  fi
  while IFS= read -r -d '' bak; do
    if [[ "$bak" != "$newest" ]]; then
      rm -rf -- "$bak"
      warn "removed old backup: $(basename "$bak")"
    fi
  done < <(find "$dir" -maxdepth 1 -name "$name.bak.*" -print0 2>/dev/null)
}

install_file() {
  local src="$1" dst="$2"
  if [[ ! -f "$src" ]]; then
    warn "skipping missing source: $src"
    return 0
  fi
  if [[ -e "$dst" ]] && ! cmp -s "$src" "$dst"; then
    local bak
    bak="$dst.bak.$(date +%s)"
    mv "$dst" "$bak"
    warn "backed up existing file: $dst -> $(basename "$bak")"
    prune_backups "$dst"
  fi
  mkdir -p "$(dirname "$dst")"
  cp "$src" "$dst"
  ok "installed $(basename "$dst")"
}

BUNDLED_PLUGINS=(rob.bar rob.clock rob.menu rob.system-updates rob.vitals rob.workspaces)

install_dir_overwrite() {
  local src="$1" dst="$2"
  if [[ ! -d "$src" ]]; then
    warn "skipping missing source dir: $src"
    return 0
  fi
  mkdir -p "$dst"
  cp -r "$src"/. "$dst"/
  ok "installed $(basename "$dst")/"
}

bundle "Preflight"
require omarchy "This installer targets Omarchy (https://omarchy.org)."
info "Omarchy $(omarchy version)"
ok "preflight passed"

bundle "Plugins"

# Remove stale backups. A leftover "rob.*.bak.*" dir duplicates the live
# plugin's manifest id and shadows it in the shell's plugin registry.
while IFS= read -r -d '' plugin_bak; do
  rm -rf -- "$plugin_bak"
  warn "removed stale plugin backup: $(basename "$plugin_bak")"
done < <(find "$HOME/.config/omarchy/plugins" -maxdepth 1 -name '*.bak.*' -print0 2>/dev/null)

info "installing bundled plugins"
for plugin in "${BUNDLED_PLUGINS[@]}"; do
  install_dir_overwrite "$PLUGINS_DIR/$plugin" "$HOME/.config/omarchy/plugins/$plugin"
done

bundle "Bin scripts"
info "installing system-update-count"
install_file "$BIN_DIR/system-update-count" "$HOME/.config/omarchy/bin/system-update-count"
chmod +x "$HOME/.config/omarchy/bin/system-update-count"

bundle "Configure"
info "enabling rob plugins"
omarchy plugin enable rob.bar rob.clock rob.menu rob.system-updates rob.vitals rob.workspaces
ok "rob plugins enabled"

info "disabling conflicting omarchy plugins"
omarchy plugin disable omarchy.menu omarchy.clock omarchy.workspaces omarchy.system-update omarchy.bar 2>/dev/null || true
ok "conflicting plugins disabled"

info "wiring plugins into shell.json"
python3 <<'PYEOF'
import json, os, sys, time

path = os.path.expanduser("~/.config/omarchy/shell.json")

try:
    with open(path) as f:
        config = json.load(f)
except (FileNotFoundError, json.JSONDecodeError):
    config = {"version": 1}

if isinstance(config, dict):
    backup = path + ".bak." + str(int(time.time()))
    try:
        with open(path) as f:
            shutil_copy_source = f.read()
    except Exception:
        pass
    else:
        with open(backup, "w") as f:
            f.write(shutil_copy_source)

    if "bar" not in config:
        config["bar"] = {}
    bar = config["bar"]
    bar["id"] = "rob.bar"
    bar["centerAnchor"] = "rob.clock"

    if "layout" not in bar:
        bar["layout"] = {"left": [], "center": [], "right": []}
    layout = bar["layout"]
    for section in ("left", "center", "right"):
        if section not in layout:
            layout[section] = []

    ID_SWAP = {
        "omarchy.menu": "rob.menu",
        "omarchy.clock": "rob.clock",
        "omarchy.workspaces": "rob.workspaces",
        "omarchy.system-update": "rob.system-updates",
    }

    def swap_id(entry):
        if isinstance(entry, dict) and "id" in entry:
            if entry["id"] in ID_SWAP:
                entry["id"] = ID_SWAP[entry["id"]]
        elif isinstance(entry, str) and entry in ID_SWAP:
            entry = ID_SWAP[entry]
            if isinstance(entry, dict):
                pass
        return entry

    def get_entry(entries, target_id):
        for i, e in enumerate(entries):
            uid = e["id"] if isinstance(e, dict) else e if isinstance(e, str) else ""
            if uid == target_id:
                return i, e
        return None, None

    for section in ("left", "center", "right"):
        layout[section] = [swap_id(e) for e in layout[section]]

    # rob.system-updates belongs in right, next to rob.vitals.
    # Pull it out of wherever the swap left it, then place it.
    rob_updates = None
    for section in ("left", "center", "right"):
        idx, entry = get_entry(layout[section], "rob.system-updates")
        if entry is not None:
            rob_updates = entry
            layout[section].pop(idx)
            break
    if rob_updates is None:
        rob_updates = {"id": "rob.system-updates"}

    # rob.vitals and rob.system-updates together at the head of right
    layout["right"].insert(0, {"id": "rob.vitals"})
    layout["right"].insert(1, rob_updates)

    with open(path, "w") as f:
        json.dump(config, f, indent=2)
        f.write("\n")

    print("shell.json updated")
else:
    print("shell.json is not a valid object, skipping")
PYEOF
ok "shell.json updated"

bundle "Apply"
info "restarting shell"
omarchy restart shell || warn "omarchy restart shell failed"

printf '\n%s\n' "${C_GREEN}${C_BOLD}Rob plugins installed.${C_RESET}"
