#!/bin/bash
# 日志系统模块
# 日志级别 (DEBUG, INFO, WARNING, ERROR)
LOG_LEVEL=${LOG_LEVEL:-"INFO"}

# 初始化日志系统
init_logging() {
    LOG_DIR="${RES_DIR}/logs"
    mkdir -p "$LOG_DIR"
    find "$LOG_DIR" -name 'build-*.log' -mtime +7 -exec rm -f {} \;
    
    local log_file="${LOG_DIR}/build-$(date +%Y.%m.%d-%H:%M:%S).log"
    exec 3>&1 4>&2
    
    if [[ $1 != "config" ]]; then
        exec > >(tee -a "$log_file") 2>&1
    fi
}

# 增强日志函数
log() {
    local level=$1
    local message=$2
    local timestamp=$(date +"%T")
    local caller_info=""
    
    declare -A log_levels=([DEBUG]=0 [INFO]=1 [SUCCESS]=2 [WARNING]=3 [ERROR]=4)
    [[ ${log_levels[$level]} -lt ${log_levels[$LOG_LEVEL]} ]] && return
    
    local icon color
    case $level in
        "DEBUG")   icon="🛠️ "  ; color="${MAGENTA}" ;;
        "INFO")    icon="ℹ️ "  ; color="${BLUE}" ;;
        "SUCCESS") icon="✅ "  ; color="${GREEN}" ;;
        "WARNING") icon="⚠️ "  ; color="${YELLOW}" ;;
        "ERROR")   icon="❌ "  ; color="${RED}" ;;
        *)         icon="🔹 "  ; color="${NC}" ;;
    esac
    
    # DEBUG级别添加调用信息
    if [[ "$level" == "DEBUG" ]]; then
        local func_name="${FUNCNAME[1]}"
        local line_no="${BASH_LINENO[0]}"
        caller_info="[${func_name}:${line_no}] "
    fi
    
    local level_padded=$(printf "%-7s" "[$level]")
    # 添加文件/操作信息
    local context=""
    [[ -n "$3" ]] && context="(${3}) "
    
    echo -e "[${timestamp}] ${BOLD}${color}${level_padded}${NC} ${icon} ${caller_info}${context}${message}" >&3
}

# 进度条显示函数
show_progress_bar() {
    local current=$1
    local total=$2
    local msg=$3
    local width=50
    
    local percent=$((current * 100 / total))
    local completed_chars=$((current * width / total))
    local remaining_chars=$((width - completed_chars))

    local bar="${GREEN}"
    for ((i=0; i<completed_chars; i++)); do
        bar+="▓"
    done
    bar+="${YELLOW}"
    for ((i=0; i<remaining_chars; i++)); do
        bar+="░"
    done
    bar+="${NC}"

    local progress_info="[${bar}] ${percent}% (${current}/${total}) ${msg}"
    echo -ne "\033[2K\r${progress_info}"
    
    if [ $current -ge $total ]; then
        echo ""
    fi
}