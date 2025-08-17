#!/bin/bash
# 日志系统模块
# 全局变量声明
declare -gi MAIN_LINES=0
declare -g LOG_FILE PROGRESS_PIPE PROGRESS_MANAGER_PID
declare -g USE_TPUT=1  # 添加tput使用标志

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
    
    # 检查是否支持tput
    if ! command -v tput &> /dev/null || [ ! -t 1 ]; then
        USE_TPUT=0
        log "WARNING" "终端不支持tput命令或非交互式终端，禁用进度条功能"
    else
        # 启动进度条管理器
        start_progress_manager
    fi
    
    # 重定向标准输出和错误输出
    if [[ $1 != "config" ]]; then
        exec > >(tee -a "$LOG_FILE") 2>&1
    fi
    
    # 设置信号捕获确保退出时清理
    trap 'cleanup_logging' EXIT INT TERM
}

# 启动进度条管理器
start_progress_manager() {
    # 在子进程中运行进度管理器
    (
        # 获取终端尺寸
        local term_lines=$(tput lines)
        local term_cols=$(tput cols)
        
        # 计算主输出区域高度（保留底部2行给进度条）
        MAIN_LINES=$((term_lines - 2))
        
        # 设置主输出区域（允许向上滚动）
        tput csr 0 $((MAIN_LINES - 1))
        tput cup $((MAIN_LINES - 1)) 0  # 初始光标位置在底部
        
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
                
                # 恢复光标到日志区域
                safe_tput "cup $((MAIN_LINES - 1)) 0"
            fi
        done
    ) &
    PROGRESS_MANAGER_PID=$!
}

# 安全tput函数
safe_tput() {
    [ $USE_TPUT -eq 1 ] && tput $1 2>/dev/null || true
}

# 增强日志函数（修复光标位置问题）
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
    
    # 构建日志行
    local log_line="[${timestamp}] ${BOLD}${color}${level_padded}${NC} ${icon} ${caller_info}${context}${message}"
    
    if [ $USE_TPUT -eq 1 ]; then
        # 在主输出区域显示日志
        safe_tput "cup $((MAIN_LINES - 1)) 0"
        echo -e "$log_line"
        
        # 向下滚动一行（模拟自然滚动）
        safe_tput "il1"
        
        # 恢复光标到日志区域底部
        safe_tput "cup $((MAIN_LINES - 1)) 0"
    else
        # 非交互式终端直接输出
        echo -e "$log_line"
    fi
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
        bar+="="
    done
    
    bar+="${YELLOW}"
    for ((i = 0; i < remaining_chars; i++)); do
        bar+="-"
    done
    bar+="${NC}"

    # 构建进度信息
    local progress_info="[${bar}] ${percent}% (${current}/${total})"
    
    # 在进度条区域显示
    echo -ne "${progress_info}"
    
    # 恢复光标到日志区域
    safe_tput "cup $((MAIN_LINES - 1)) 0"
}

# 更新进度条显示
update_progress() {
    local current=$1
    local total=$2
    local msg=$3
    
    # 通过命名管道发送进度数据
    [ $USE_TPUT -eq 1 ] && echo "${current};${total};${msg}" > "$PROGRESS_PIPE"
}

# 清理日志系统（保留日志显示）
cleanup_logging() {
    # 恢复终端滚动区域
    [ $USE_TPUT -eq 1 ] && safe_tput "csr 0 $(tput lines)"
    
    # 结束进度条管理器及其子进程
    if [ -n "$PROGRESS_MANAGER_PID" ] && [ $USE_TPUT -eq 1 ]; then
        kill -TERM "$PROGRESS_MANAGER_PID" 2>/dev/null
        wait "$PROGRESS_MANAGER_PID" 2>/dev/null
    fi
    
    # 清理命名管道
    [ -p "$PROGRESS_PIPE" ] && rm -f "$PROGRESS_PIPE" 2>/dev/null
    
    # 恢复标准输出
    exec 1>&3 2>&4
    
    if [ $USE_TPUT -eq 1 ]; then
        # 清除进度条区域
        safe_tput "cup $MAIN_LINES 0"
        safe_tput "el"
        safe_tput "cup $((MAIN_LINES + 1)) 0"
        safe_tput "el"
        
        # 将光标移动到屏幕底部
        safe_tput "cup $(tput lines) 0"
        echo -ne "\n"  # 确保新提示符在下一行
    fi
}