#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
RUST_SRC_DIR="$PROJECT_ROOT/scripts/owbm"
BIN_PATH="$PROJECT_ROOT/owbm"

MODE="${1:-release}"

case "$MODE" in
    release)
        BUILD_ARGS="--release"
        OUTPUT_PATH="$RUST_SRC_DIR/target/release/owbm"
        ;;
    debug)
        BUILD_ARGS=""
        OUTPUT_PATH="$RUST_SRC_DIR/target/debug/owbm"
        ;;
    clean)
        rm -rf "$RUST_SRC_DIR/target" "$BIN_PATH"
        echo "已清理构建产物：$RUST_SRC_DIR/target 和 $BIN_PATH"
        exit 0
        ;;
    *)
        echo "用法: $0 [release|debug|clean]"
        exit 1
        ;;
 esac

if [[ ! -f "$RUST_SRC_DIR/Cargo.toml" ]]; then
    echo "错误: 未找到 Rust 项目配置：$RUST_SRC_DIR/Cargo.toml"
    exit 1
fi

cd "$RUST_SRC_DIR"
cargo build $BUILD_ARGS

if [[ ! -f "$OUTPUT_PATH" ]]; then
    echo "错误: 编译产物不存在：$OUTPUT_PATH"
    exit 1
fi

cp "$OUTPUT_PATH" "$BIN_PATH"
printf '已编译并复制：%s -> %s\n' "$OUTPUT_PATH" "$BIN_PATH"
