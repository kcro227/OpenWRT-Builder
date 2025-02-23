#!/bin/bash

# 获取当前日期(日-月-年 格式)
current_date=$(date +%y-%m-%d)

# 构建目标路径
target_dir="/mnt/d/image/openwrt/xr-30/build/lede/$current_date"

# 创建目标目录（如果不存在）
mkdir -p "$target_dir"

# 复制所有匹配的文件
for file in "$@"; do
    if [ -e "$file" ]; then
        cp -v "$file" "$target_dir/"
    else
        echo "警告: 文件 $file 不存在"
    fi
done

echo "文件已复制到：$target_dir"