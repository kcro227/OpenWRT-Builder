#!/usr/bin/env bash
# -----------------------------------------------------------------------------
# 模板脚本：bash_default.sh
# 功能：自动识别当前 target 的根目录、名称以及编译产物路径。
# 用法：将此脚本放置在任意 target 的 custom/ 目录下，运行即可。
# -----------------------------------------------------------------------------

set -euo pipefail

# 1. 获取脚本所在目录的绝对路径（解析软链接）
SCRIPT_DIR=$(cd "$(dirname "$(readlink -f "$0")")" && pwd)

# 2. 向上查找 target 根目录（特征文件：packagelist.txt 或 source.json）
TARGET_ROOT=""
CURRENT_DIR="$SCRIPT_DIR"
while [[ "$CURRENT_DIR" != "/" ]]; do
    if [[ -f "$CURRENT_DIR/packagelist.txt" || -f "$CURRENT_DIR/source.json" ]]; then
        TARGET_ROOT="$CURRENT_DIR"
        break
    fi
    CURRENT_DIR=$(dirname "$CURRENT_DIR")
done

if [[ -z "$TARGET_ROOT" ]]; then
    echo "错误：未找到 target 根目录（缺少 packagelist.txt 或 source.json）" >&2
    exit 1
fi

# 3. 确定 target 名称和路径
TARGET_NAME=$(basename "$TARGET_ROOT")
TARGET_PATH="$TARGET_ROOT"

# 4. 确定编译产物路径（按常见目录依次检查）
BUILD_OUTPUT_PATH=""
for candidate in "build" "out" "dist" "bin"; do
    if [[ -d "$TARGET_PATH/$candidate" ]]; then
        BUILD_OUTPUT_PATH="$TARGET_PATH/$candidate"
        break
    fi
done

# 如果都未找到，可以设置为默认路径（例如 build）
if [[ -z "$BUILD_OUTPUT_PATH" ]]; then
    BUILD_OUTPUT_PATH="$TARGET_PATH/build"
fi

# 5. 输出识别结果（可在此添加后续逻辑）
echo "脚本所在目录: $SCRIPT_DIR"
echo "Target 根目录: $TARGET_ROOT"
echo "Target 名称: $TARGET_NAME"
echo "Target 路径: $TARGET_PATH"
echo "编译产物路径: $BUILD_OUTPUT_PATH"

# 在此添加你的操作，例如：
# if [[ -d "$BUILD_OUTPUT_PATH" ]]; then
#     cp -r "$BUILD_OUTPUT_PATH"/* /some/destination/
# fi