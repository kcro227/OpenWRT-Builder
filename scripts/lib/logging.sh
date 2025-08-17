#!/bin/bash
# 日志系统模块
# 日志级别 (DEBUG, INFO, WARNING, ERROR)
LOG_LEVEL=${LOG_LEVEL:-"INFO"}

# 初始化日志系统
init_logging() {
    # 创建日志目录
    LOG_DIR="${RES_DIR}/logs"
    mkdir -p "$LOG_DIR"
    find "$LOG_DIR" -name 'build-*.log' -mtime +7 -exec rm -f {} \;
    
    # 创建日志文件
    LOG_FILE="${LOG_DIR}/build-$(date +%Y.%m.%d-%H:%M:%S).log"
    touch "$LOG_FILE"
    
    # 创建命名管道用于进度条通信
    PROGRESS_PIPE="${LOG_DIR}/progress_pipe"
    [ -p "$PROGRESS_PIPE" ] && rm -f "$PROGRESS_PIPE"
    mkfifo "$PROGRESS_PIPE"
    
    # 保存原始输出描述符
    exec 3>&1 4>&2
    
    # 启动进度条管理器
    start_progress_manager &
    PROGRESS_MANAGER_PID=$!
    
    # 重定向标准输出和错误输出
    if [[ $1 != "config" ]]; then
        exec > >(tee -a "$LOG_FILE") 2>&1
    fi
}

# 启动进度条管理器
start_progress_manager() {
    # 获取终端尺寸
    local term_lines=$(tput lines)
    local term_cols=$(tput cols)
    
    # 计算主输出区域高度（保留底部2行给进度条）
    MAIN_LINES=$((term_lines - 2))
    
    # 设置主输出区域
    tput csr 0 $((MAIN_LINES - 1))
    tput cup 0 0
    
    # 设置进度条区域（底部2行）
    tput cup $MAIN_LINES 0
    echo -ne "${BOLD}${GREEN}系统状态:${NC} 初始化进度条系统..."
    tput cup $((MAIN_LINES + 1)) 0
    echo -ne "${BOLD}${YELLOW}进度:${NC} [等待任务开始]"
    
    # 监听进度条更新
    while true; do
        if read -r progress_data < "$PROGRESS_PIPE"; then
            # 清空进度区域
            tput cup $MAIN_LINES 0
            tput el
            tput cup $((MAIN_LINES + 1)) 0
            tput el
            
            # 解析进度数据 (current;total;message)
            IFS=';' read -r current total message <<< "$progress_data"
            
            # 显示系统状态
            tput cup $MAIN_LINES 0
            echo -ne "${BOLD}${GREEN}系统状态:${NC} ${message}"
            
            # 显示进度条
            tput cup $((MAIN_LINES + 1)) 0
            show_progress_bar "$current" "$total" "$message"
        fi
    done
}

# 增强日志函数
log() {
    local level=$1
    local message=$2
    
    declare -A log_levels=([DEBUG]=0 [INFO]=1 [SUCCESS]=2 [WARNING]=3 [ERROR]=4)
    [[ ${log_levels[$level]} -lt ${log_levels[$LOG_LEVEL]} ]] && return
    
    local icon color timestamp context caller_info
    timestamp=$(date +"%T")
    
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
    
    # 在主输出区域显示日志
    tput cup $MAIN_LINES 0  # 先移动光标到主区域底部
    tput il1  # 插入新行使内容向上滚动
    
    # 输出带颜色的日志消息
    echo -e "[${timestamp}] ${BOLD}${color}${level_padded}${NC} ${icon} ${caller_info}${context}${message}"
    
    # 恢复光标到主区域底部
    tput cup $MAIN_LINES 0
}

# 进度条显示函数
show_progress_bar() {
    local current=$1
    local total=$2
    local msg=$3
    local width=50
    
    # 计算百分比和进度条填充
    local percent=0
    [ $total -gt 0 ] && percent=$((current * 100 / total))
    
    local completed_chars=0
    [ $total -gt 0 ] && completed_chars=$((current * width / total))
    [ $completed_chars -gt $width ] && completed_chars=$width
    
    local remaining_chars=$((width - completed_chars))

    # 构建进度条字符串
    local bar="${GREEN}"
    for ((i = 0; i < completed_chars; i++)); do
        bar+="▓"
    done
    
    bar+="${YELLOW}"
    for ((i = 0; i < remaining_chars; i++)); do
        bar+="░"
    done
    bar+="${NC}"

    # 构建进度信息
    local progress_info="[${bar}] ${percent}% (${current}/${total}) ${msg}"
    
    # 在进度条区域显示
    echo -ne "${progress_info}"
}

# 更新进度条显示
update_progress() {
    local current=$1
    local total=$2
    local msg=$3
    
    # 通过命名管道发送进度数据
    echo "${current};${total};${msg}" > "$PROGRESS_PIPE"
}

# 清理日志系统
cleanup_logging() {
    # 恢复终端设置
    tput csr 0 $(tput lines)
    
    # 结束进度条管理器
    [ -n "$PROGRESS_MANAGER_PID" ] && kill $PROGRESS_MANAGER_PID >/dev/null 2>&1
    
    # 清理命名管道
    [ -p "$PROGRESS_PIPE" ] && rm -f "$PROGRESS_PIPE"
    
    # 恢复标准输出
    exec 1>&3 2>&4
}