#!/usr/bin/env bash

set -e

# 获取脚本所在目录（即项目根目录）
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$SCRIPT_DIR"
RUST_SRC_DIR="$PROJECT_ROOT/scripts"

if [[ ! -f "$RUST_SRC_DIR/Cargo.toml" ]]; then
    echo "错误: 未在 $RUST_SRC_DIR 找到 Cargo.toml"
    exit 1
fi

# 检查 cargo
if ! command -v cargo &> /dev/null; then
    echo "错误: 未找到 cargo，请先安装 Rust (https://rustup.rs/)"
    exit 1
fi

# 解析编译模式
MODE="${1:-release}"
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
        echo "用法: $0 [release|debug]"
        echo "默认 release"
        exit 1
        ;;
esac

echo "正在以 $MODE 模式编译 owbm..."
cd "$RUST_SRC_DIR"
cargo build $BUILD_ARGS

# 源文件路径
SRC_BIN="$RUST_SRC_DIR/target/$TARGET_DIR/owbm"
if [[ ! -f "$SRC_BIN" ]]; then
    echo "错误: 编译后未找到 $SRC_BIN"
    exit 1
fi

# 目标路径（项目根目录）
DEST_BIN="$PROJECT_ROOT/owbm"
cp "$SRC_BIN" "$DEST_BIN"
echo "已复制 $SRC_BIN -> $DEST_BIN"