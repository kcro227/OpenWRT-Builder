#!/bin/bash
# feeds管理模块

# 更新并安装feeds
update_and_install_feeds() {
    log INFO "开始更新feeds包" "feeds管理"
    validate_dir "$SRC_DIR" || return 1
    
    pushd "$SRC_DIR" >/dev/null || return 1
    
    local progress_pid=$!
    
    log DEBUG "执行: ./scripts/feeds update -a" "feeds管理"
    ./scripts/feeds update -a || {
        kill $progress_pid >/dev/null 2>&1
        popd >/dev/null
        log ERROR "更新feeds失败" "feeds管理"
        return 1
    }
    
    kill $progress_pid >/dev/null 2>&1
    wait $progress_pid 2>/dev/null
    echo -ne "\r\033[K"
    
    log INFO "开始安装feeds包" "feeds管理"
    
    progress_pid=$!
    
    log DEBUG "执行: ./scripts/feeds install -a" "feeds管理"
    ./scripts/feeds install -a || {
        kill $progress_pid >/dev/null 2>&1
        log ERROR "安装feeds失败" "feeds管理"
        return 1
    }
    
    kill $progress_pid >/dev/null 2>&1
    wait $progress_pid 2>/dev/null
    echo -ne "\r\033[K"
    
    popd >/dev/null
    log SUCCESS "feeds安装完成" "feeds管理"
}