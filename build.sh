#!/usr/bin/env bash

set -euo pipefail

# 获取脚本所在目录（即项目根目录）
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$SCRIPT_DIR"
RUST_SRC_DIR="$PROJECT_ROOT/scripts"   # 请根据实际 Cargo.toml 位置调整

# ─────────────────── 工具链检测与安装 ───────────────────
install_rustup() {
    if ! command -v curl &> /dev/null; then
        echo "错误: 安装 Rust 需要 curl，请先安装 curl 后重试。"
        exit 1
    fi

    echo "未找到 Rust 工具链，正在通过 rustup 安装..."
    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y --default-toolchain stable --profile minimal

    if [[ -f "$HOME/.cargo/env" ]]; then
        # shellcheck disable=SC1091
        source "$HOME/.cargo/env"
    else
        echo "警告: 未找到 $HOME/.cargo/env，请手动执行 source ~/.cargo/env 后重试。"
        exit 1
    fi
}

# ─────────────────── 参数解析 ───────────────────
MODE="${1:-release}"

# 处理 clean 命令
if [[ "$MODE" == "clean" ]]; then
    echo "正在清理构建产物..."

    TARGET_DIR="$RUST_SRC_DIR/target"
    if [[ -d "$TARGET_DIR" ]]; then
        rm -rf "$TARGET_DIR"
        echo "已删除: $TARGET_DIR"
    else
        echo "跳过: $TARGET_DIR 不存在"
    fi

    echo "清理完成。"
    exit 0
fi

# 正常的编译模式检查
case "$MODE" in
    release)
        TARGET_DIR="release"
        BUILD_ARGS="--release"
        ;;
    debug)
        TARGET_DIR="debug"
        BUILD_ARGS=""
        ;;
    *)
        echo "用法: $0 [release|debug|clean]"
        echo "默认 release"
        exit 1
        ;;
esac

# ─────────────────── 工具链准备 ───────────────────
if ! command -v cargo &> /dev/null; then
    install_rustup
fi

if command -v rustup &> /dev/null; then
    if ! rustup toolchain list | grep -q '^stable'; then
        echo "检测到 rustup 但缺少 stable 工具链，正在安装..."
        rustup toolchain install stable --profile minimal
    fi
    if [[ -f "$RUST_SRC_DIR/rust-toolchain.toml" ]] || [[ -f "$RUST_SRC_DIR/rust-toolchain" ]]; then
        echo "已检测到项目指定的工具链文件，将使用其设定的工具链。"
    else
        echo "使用 stable 工具链进行编译..."
        export RUSTUP_TOOLCHAIN="${RUSTUP_TOOLCHAIN:-stable}"
    fi
else
    echo "注意: cargo 不是通过 rustup 管理的，请确保已安装所需工具链。"
fi

# ─────────────────── 编译 ───────────────────
if [[ ! -f "$RUST_SRC_DIR/Cargo.toml" ]]; then
    echo "错误: 未在 $RUST_SRC_DIR 找到 Cargo.toml"
    exit 1
fi

echo "正在以 $MODE 模式编译 owbm..."
cd "$RUST_SRC_DIR"
cargo build $BUILD_ARGS

# ─────────────────── 复制产物 ───────────────────
SRC_BIN="$RUST_SRC_DIR/target/$TARGET_DIR/owbm"
if [[ ! -f "$SRC_BIN" ]]; then
    echo "错误: 编译后未找到 $SRC_BIN"
    exit 1
fi

DEST_BIN="$PROJECT_ROOT/owbm"
cp "$SRC_BIN" "$DEST_BIN"
echo "已复制 $SRC_BIN -> $DEST_BIN"