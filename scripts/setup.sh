#!/usr/bin/env bash

# 确保脚本被 source 而不是直接执行
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    echo "This script must be sourced. Run: source ${BASH_SOURCE[0]}"
    exit 1
fi

# 获取脚本所在目录（绝对路径）
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# 项目根目录（scripts 的上一级）
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# 可能的 owbm 二进制路径
OWBM_BIN="$PROJECT_ROOT/target/release/owbm"
OWBM_BIN_ALT="$PROJECT_ROOT/owbm"

# 如果二进制不存在，尝试编译
if [[ ! -f "$OWBM_BIN" && ! -f "$OWBM_BIN_ALT" ]]; then
    echo "owbm binary not found. Building..."
    cd "$PROJECT_ROOT" || return 1
    cargo build --release
    if [[ $? -ne 0 ]]; then
        echo "Build failed. Exiting."
        return 1
    fi
fi

# 确定二进制所在目录
if [[ -f "$OWBM_BIN" ]]; then
    BIN_DIR="$PROJECT_ROOT/target/release"
elif [[ -f "$OWBM_BIN_ALT" ]]; then
    BIN_DIR="$PROJECT_ROOT"
else
    echo "owbm binary still not found. Exiting."
    return 1
fi

# 将二进制目录添加到当前 shell 的 PATH（如果尚未添加）
case ":${PATH}:" in
    *":$BIN_DIR:"*)
        echo "$BIN_DIR already in PATH."
        ;;
    *)
        export PATH="$BIN_DIR:$PATH"
        echo "Added $BIN_DIR to PATH (current session)."
        ;;
esac

source $SCRIPT_DIR/completion.bash
echo "You can now run 'owbm' from anywhere in this terminal."
echo "To make it permanent, add the following line to your ~/.bashrc or ~/.zshrc:"
echo "export PATH=\"$BIN_DIR:\$PATH\""