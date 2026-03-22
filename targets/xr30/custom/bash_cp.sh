#!/usr/bin/env bash
# -----------------------------------------------------------------------------
# 脚本：bash_cp.sh（修复版，带调试）
# -----------------------------------------------------------------------------

# 启用调试：输出每条执行的命令（如果问题解决后可移除）
# set -x
set -euo pipefail

# ========== 用户配置区 ==========
FIRMWARE_PATTERNS=(
    "targets/*/*/*sysupgrade.bin"
    # "targets/*/*/*.bin"
)

declare -A MODEL_DEST=(
    ["n60-pro-512m"]="/mnt/b/image/n60pro/n60pro-512m"
    ["n60-pro-256m"]="/mnt/b/image/n60pro/n60pro-256m"
    ["n60-pro"]="/mnt/b/image/n60pro/n60pro"
    ["xr30-nand"]="/mnt/b/image/xr30"

)

DEST_BASE="/mnt/b/image"
# ==============================

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

# 3. 确定 target 名称
TARGET_NAME=$(basename "$TARGET_ROOT")

# 4. 确定工作区根目录（假设 targets 和 srcs 在同一父目录下）
WORKSPACE_ROOT=$(dirname "$(dirname "$TARGET_ROOT")")
SRC_DIR="$WORKSPACE_ROOT/srcs/$TARGET_NAME"

if [[ ! -d "$SRC_DIR" ]]; then
    echo "错误：源码目录不存在 $SRC_DIR，请先运行 owbm target init" >&2
    exit 1
fi

# 5. 编译产物基础路径
BUILD_OUTPUT_PATH="$SRC_DIR/bin"
if [[ ! -d "$BUILD_OUTPUT_PATH" ]]; then
    echo "警告：未找到 bin 目录 $BUILD_OUTPUT_PATH" >&2
fi

# 6. 日期目录
DATE_DIR=$(date +%Y-%m-%d)

# 7. 输出识别结果
echo "脚本所在目录: $SCRIPT_DIR"
echo "Target 根目录: $TARGET_ROOT"
echo "Target 名称: $TARGET_NAME"
echo "工作区根目录: $WORKSPACE_ROOT"
echo "源码目录: $SRC_DIR"
echo "编译产物基础路径: $BUILD_OUTPUT_PATH"

# 8. 查找所有匹配的固件文件
FOUND_FILES=()
for pattern in "${FIRMWARE_PATTERNS[@]}"; do
    while IFS= read -r -d '' file; do
        FOUND_FILES+=("$file")
    done < <(find "$BUILD_OUTPUT_PATH" -path "$BUILD_OUTPUT_PATH/$pattern" -type f -print0 2>/dev/null)
done

# 去重
declare -A UNIQUE
for file in "${FOUND_FILES[@]}"; do
    UNIQUE["$file"]=1
done

if [[ ${#UNIQUE[@]} -eq 0 ]]; then
    echo "警告：未找到任何匹配的固件文件，匹配模式: ${FIRMWARE_PATTERNS[*]}" >&2
    exit 0
fi

# 9. 辅助函数：根据文件名确定目标基础路径
get_dest_base() {
    local filename="$1"
    # 优先匹配型号映射
    for key in "${!MODEL_DEST[@]}"; do
        if [[ "$filename" == *"$key"* ]]; then
            echo "${MODEL_DEST[$key]}"
            return 0
        fi
    done
    # 未匹配到，使用当前 target 名称
    echo "${DEST_BASE}/${TARGET_NAME}"
}

# 10. 复制所有找到的固件
COPIED=0
for file in "${!UNIQUE[@]}"; do
    filename=$(basename "$file")
    dest_base=$(get_dest_base "$filename")
    dest_dir="${dest_base}/${DATE_DIR}"

    echo "找到固件: $file"
    echo "  目标基础路径: $dest_base"
    echo "  目标目录: $dest_dir"

    if ! mkdir -p "$dest_dir"; then
        echo "  错误：无法创建目录 $dest_dir" >&2
        continue
    fi

    if cp "$file" "$dest_dir/"; then
        echo "  成功: $(basename "$file") -> $dest_dir/"
        # 修复：使用 $((...)) 避免 ((COPIED++)) 在值为0时返回非0导致脚本退出
        COPIED=$((COPIED + 1))
    else
        echo "  错误: 复制失败" >&2
    fi
done

if [[ $COPIED -eq 0 ]]; then
    echo "错误：未成功复制任何固件文件" >&2
    exit 1
else
    echo "完成：共复制 $COPIED 个固件文件"
    exit 0
fi