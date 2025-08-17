#!/bin/bash
# feeds管理模块

# 更新并安装feeds
update_and_install_feeds() {
    log INFO "开始更新feeds包" "feeds管理"
    validate_dir "$SRC_DIR" || return 1
    
    pushd "$SRC_DIR" >/dev/null || return 1
    
    # 更新进度
    update_progress 0 3 "更新feeds"
    
    log DEBUG "执行: ./scripts/feeds update -a" "feeds管理"
    ./scripts/feeds update -a || {
        popd >/dev/null
        log ERROR "更新feeds失败" "feeds管理"
        return 1
    }
    
    update_progress 1 3 "更新feeds完成"
    
    log INFO "开始安装feeds包" "feeds管理"
    update_progress 2 3 "安装feeds"
    
    log DEBUG "执行: ./scripts/feeds install -a" "feeds管理"
    ./scripts/feeds install -a || {
        log ERROR "安装feeds失败" "feeds管理"
        return 1
    }
    
    update_progress 3 3 "安装feeds完成"
    
    popd >/dev/null
    log SUCCESS "feeds安装完成" "feeds管理"
}