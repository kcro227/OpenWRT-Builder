#!/usr/bin/env bash
# -----------------------------------------------------------------------------
# 脚本：bash_cp.sh（彩色日志版）
# -----------------------------------------------------------------------------

set -euo pipefail

# ========== 颜色定义（仅当输出到终端时启用） ==========
if [[ -t 1 ]]; then
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    YELLOW='\033[0;33m'
    BLUE='\033[0;34m'
    RESET='\033[0m'
else
    RED=''
    GREEN=''
    YELLOW=''
    BLUE=''
    RESET=''
fi

# ========== 用户配置区 ==========
FIRMWARE_PATTERNS=(
    "targets/*/*/*sysupgrade.bin"
    # "targets/*/*/*.bin"
)

declare -A MODEL_DEST=(
    # ["n60-pro-512m"]="/mnt/b/image/n60pro/n60pro-512m"
    # ["n60-pro-256m"]="/mnt/b/image/n60pro/n60pro-256m"
    # ["n60-pro"]="/mnt/b/image/n60pro/n60pro"
    ["xr30-nand"]="/mnt/b/image/xr30-237/xr30-nand"
    ["xr30-nand-256m"]="/mnt/b/image/xr30-237/xr30-nand-256m"
)

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
    echo -e "${RED}错误：未找到 target 根目录（缺少 packagelist.txt 或 source.json）${RESET}" >&2
    exit 1
fi

# 3. 确定 target 名称
TARGET_NAME=$(basename "$TARGET_ROOT")

# 4. 确定工作区根目录（假设 targets 和 srcs 在同一父目录下）
WORKSPACE_ROOT=$(dirname "$(dirname "$TARGET_ROOT")")
SRC_DIR="$WORKSPACE_ROOT/srcs/$TARGET_NAME"

if [[ ! -d "$SRC_DIR" ]]; then
    echo -e "${RED}错误：源码目录不存在 $SRC_DIR，请先运行 owbm target init${RESET}" >&2
    exit 1
fi

# 5. 编译产物基础路径
BUILD_OUTPUT_PATH="$SRC_DIR/bin"
if [[ ! -d "$BUILD_OUTPUT_PATH" ]]; then
    echo -e "${YELLOW}警告：未找到 bin 目录 $BUILD_OUTPUT_PATH${RESET}" >&2
fi

# 6. 日期目录
DATE_DIR=$(date +%Y-%m-%d)

# 7. 输出识别结果
echo -e "${BLUE}脚本所在目录:${RESET} $SCRIPT_DIR"
echo -e "${BLUE}Target 根目录:${RESET} $TARGET_ROOT"
echo -e "${BLUE}Target 名称:${RESET} $TARGET_NAME"
echo -e "${BLUE}工作区根目录:${RESET} $WORKSPACE_ROOT"
echo -e "${BLUE}源码目录:${RESET} $SRC_DIR"
echo -e "${BLUE}编译产物基础路径:${RESET} $BUILD_OUTPUT_PATH"

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
    echo -e "${YELLOW}警告：未找到任何匹配的固件文件，匹配模式: ${FIRMWARE_PATTERNS[*]}${RESET}" >&2
    exit 0
fi

# 9. 辅助函数：根据文件名确定目标基础路径（只返回匹配的，不匹配则返回空并返回非零）
get_dest_base() {
    local filename="$1"
    local best_key=""
    local best_len=0

    # 遍历映射，找到最长的匹配键（优先更具体的型号）
    for key in "${!MODEL_DEST[@]}"; do
        if [[ "$filename" == *"$key"* ]]; then
            local len=${#key}
            if (( len > best_len )); then
                best_len=$len
                best_key=$key
            fi
        fi
    done

    if [[ -n "$best_key" ]]; then
        echo "${MODEL_DEST[$best_key]}"
        return 0
    else
        # 无匹配，输出空并返回非零
        echo ""
        return 1
    fi
}

# 10. 复制所有匹配型号映射的固件（未匹配的固件跳过，但不导致脚本退出）
COPIED=0
for file in "${!UNIQUE[@]}"; do
    filename=$(basename "$file")

    # 安全地调用函数，避免因返回非零导致脚本退出
    if ! dest_base=$(get_dest_base "$filename"); then
        echo -e "${YELLOW}跳过固件:${RESET} $file (未匹配到任何型号映射)"
        continue
    fi

    dest_dir="${dest_base}/${DATE_DIR}"

    echo -e "${BLUE}找到固件:${RESET} $file"
    echo -e "  ${BLUE}目标基础路径:${RESET} $dest_base"
    echo -e "  ${BLUE}目标目录:${RESET} $dest_dir"

    if ! mkdir -p "$dest_dir"; then
        echo -e "${RED}  错误：无法创建目录 $dest_dir${RESET}" >&2
        continue
    fi

    if cp "$file" "$dest_dir/"; then
        echo -e "  ${GREEN}成功:$(basename "$file") -> $dest_dir/${RESET}"
        COPIED=$((COPIED + 1))
    else
        echo -e "${RED}  错误: 复制失败${RESET}" >&2
    fi
done

if [[ $COPIED -eq 0 ]]; then
    echo -e "${RED}错误：未成功复制任何固件文件（可能所有固件均未匹配型号映射）${RESET}" >&2
    exit 1
else
    echo -e "${GREEN}完成：共复制 $COPIED 个固件文件${RESET}"
    exit 0
fi