#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
TARGET_LINE="source \"$PROJECT_ROOT/scripts/env.sh\""
BASHRC="${HOME}/.bashrc"

if [[ ! -f "$BASHRC" ]]; then
    touch "$BASHRC"
fi

if ! grep -Fqx "$TARGET_LINE" "$BASHRC"; then
    printf '\n# Added by OpenWrt Builder\n%s\n' "$TARGET_LINE" >> "$BASHRC"
    echo "已将 env 引用追加到 $BASHRC"
else
    echo "已存在相同配置，跳过追加"
fi

echo "请执行: source ~/.bashrc"
