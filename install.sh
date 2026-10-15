#!/usr/bin/env bash
#
# install.sh — install tmux-agent, its Kiro hook and its Kiro skill.
#
# Everything is symlinked back into this repo, so `git pull` updates the
# install in place. Existing files at the target paths are backed up first.
#
#   ./install.sh               install
#   ./install.sh --uninstall   remove the symlinks (backups are left alone)
#
# Overridable locations:
#   BIN_DIR    where the command goes   (default: ~/.local/bin)
#   KIRO_HOME  Kiro's config root       (default: ~/.kiro)

set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BIN_DIR="${BIN_DIR:-$HOME/.local/bin}"
KIRO_DIR="${KIRO_HOME:-$HOME/.kiro}"

# source (in repo) -> target (installed)
LINKS=(
    "bin/tmux-agent|$BIN_DIR/tmux-agent"
    "hooks/detect-env.sh|$KIRO_DIR/hooks/tmux-agent-env.sh"
    "skills/tmux-agent/SKILL.md|$KIRO_DIR/skills/tmux-agent/SKILL.md"
)

link() {
    local src="$REPO/$1" dst="$2"
    mkdir -p "$(dirname "$dst")"
    if [[ -L "$dst" && "$(readlink "$dst")" == "$src" ]]; then
        echo "  ok       $dst"
        return
    fi
    if [[ -e "$dst" || -L "$dst" ]]; then
        local bak
        bak="$dst.bak-$(date +%Y%m%d%H%M%S)"
        mv "$dst" "$bak"
        echo "  backup   $dst -> $bak"
    fi
    ln -s "$src" "$dst"
    echo "  linked   $dst -> $src"
}

unlink_target() {
    local src="$REPO/$1" dst="$2"
    if [[ -L "$dst" && "$(readlink "$dst")" == "$src" ]]; then
        rm "$dst"
        echo "  removed  $dst"
    fi
}

if [[ "${1:-}" == "--uninstall" ]]; then
    echo "Uninstalling tmux-agent"
    for entry in "${LINKS[@]}"; do unlink_target "${entry%%|*}" "${entry#*|}"; done
    exit 0
fi

command -v tmux >/dev/null 2>&1 ||
    echo "warning: tmux is not installed (macOS: brew install tmux)" >&2
command -v kiro-cli >/dev/null 2>&1 ||
    echo "warning: kiro-cli is not on PATH; agents will not start until it is" >&2

chmod +x "$REPO/bin/tmux-agent" "$REPO/hooks/detect-env.sh"

echo "Installing tmux-agent from $REPO"
for entry in "${LINKS[@]}"; do link "${entry%%|*}" "${entry#*|}"; done

# Put BIN_DIR on PATH if it isn't already.
case ":$PATH:" in
    *":$BIN_DIR:"*) ;;
    *)
        case "${SHELL##*/}" in
            zsh)  rc="$HOME/.zshrc" ;;
            bash) rc="$HOME/.bashrc"; [[ "$(uname)" == "Darwin" ]] && rc="$HOME/.bash_profile" ;;
            *)    rc="" ;;
        esac
        line="export PATH=\"$BIN_DIR:\$PATH\"  # tmux-agent"
        if [[ -n "$rc" ]]; then
            grep -qF "# tmux-agent" "$rc" 2>/dev/null || printf '\n%s\n' "$line" >> "$rc"
            echo
            echo "Added $BIN_DIR to PATH in $rc. Open a new terminal or run: source $rc"
        else
            echo
            echo "Add $BIN_DIR to your PATH:  $line"
        fi
        ;;
esac

cat <<EOF

Done. Next: wire the hook and skill into the Kiro agents you run with tmux-agent
(see "Kiro integration" in README.md), then try:

  id=\$(tmux-agent start) && tmux attach -t "\$id"
EOF
