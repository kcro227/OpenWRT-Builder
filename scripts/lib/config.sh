#!/bin/bash
# 配置管理模块

# 应用定制规则
apply_customization() {
    local target_file="$1"
    local action="$2"
    local arg1="$3"
    local arg2="$4"
    
    log DEBUG "应用定制规则: $action 到 $target_file" "配置定制"
    log DEBUG "参数1: '$arg1'" "配置定制"
    log DEBUG "参数2: '$arg2'" "配置定制"
    
    validate_file "$target_file" || {
        [[ "$action" == "append" ]] && {
            touch "$target_file" || {
                log ERROR "创建文件失败: ${target_file/#$PROJECT_ROOT\//}" "配置定制"
                return 1
            }
            log WARNING "创建文件: ${target_file/#$PROJECT_ROOT\//}" "配置定制"
        } || {
            log WARNING "目标文件不存在: ${target_file/#$PROJECT_ROOT\//}" "配置定制"
            return 1
        }
    }
    
    case "$action" in
        "replace")
            [ -z "$arg1" ] || [ -z "$arg2" ] && {
                log WARNING "替换操作需要两个参数: 查找字符串和替换字符串" "配置定制"
                return 1
            }
            sed -i "s|${arg1}|${arg2}|g" "$target_file" || {
                log ERROR "替换失败: ${target_file/#$PROJECT_ROOT\//}" "配置定制"
                return 1
            }
            ;;
            
        "insert-after"|"insert-before")
            [ -z "$arg1" ] || [ -z "$arg2" ] && {
                log WARNING "插入操作需要两个参数: 匹配字符串和插入内容" "配置定制"
                return 1
            }
            
            grep -qF "$arg2" "$target_file" && {
                log WARNING "跳过重复插入: 目标文件中已存在相同内容" "配置定制"
                return 0
            }
            
            local sed_cmd
            [[ "$action" == "insert-after" ]] && sed_cmd="a" || sed_cmd="i"
            
            sed -i "/${arg1}/${sed_cmd} \\${arg2}" "$target_file" || {
                log ERROR "插入失败: ${target_file/#$PROJECT_ROOT\//}" "配置定制"
                return 1
            }
            ;;
            
        "append")
            [ -z "$arg1" ] && {
                log WARNING "追加操作需要内容参数" "配置定制"
                return 1
            }
            
            grep -qF "$arg1" "$target_file" && {
                log WARNING "跳过重复追加: 目标文件中已存在相同内容" "配置定制"
                return 0
            }
            
            echo -e "$arg1" >> "$target_file" || {
                log ERROR "追加失败: ${target_file/#$PROJECT_ROOT\//}" "配置定制"
                return 1
            }
            ;;
            
        "delete")
            [ -z "$arg1" ] && {
                log WARNING "删除操作需要匹配字符串" "配置定制"
                return 1
            }
            
            sed -i "/${arg1}/d" "$target_file" || {
                log ERROR "删除失败: ${target_file/#$PROJECT_ROOT\//}" "配置定制"
                return 1
            }
            ;;
            
        *)
            log WARNING "未知操作类型: $action" "配置定制"
            return 1
            ;;
    esac
    
    log SUCCESS "操作成功: $action → ${target_file/#$PROJECT_ROOT\//}" "配置定制"
    return 0
}

# 定制配置文件
customize_config_files() {
    local context="$1"
    local build_time="$2"
    
    log INFO "开始${context}阶段配置文件定制" "配置定制"
    local applied_rules=0
    
    if [ ! -f "$CUSTOMIZE_CONFIG" ]; then
        log WARNING "定制配置文件不存在，使用默认设置" "配置定制"
        if [ "$context" == "init" ]; then
            customize_default_settings_init
        elif [ "$context" == "build" ]; then
            customize_default_settings_build "$build_time"
        fi
        return 0
    fi
    
    local line_count=0
    while IFS= read -r line; do
        [[ $line =~ ^# || -z $line ]] && continue
        ((line_count++))
        
        # 使用数组处理字段
        IFS=';' read -r -a fields <<< "$line"
        local num_fields=${#fields[@]}
        if [ $num_fields -lt 4 ]; then
            log WARNING "配置行字段不足: $line" "配置定制"
            continue
        fi
        
        # 替换所有字段中的变量
        for i in "${!fields[@]}"; do
            fields[$i]=$(replace_vars "${fields[$i]}" "$build_time")
        done
        
        local line_context="${fields[0]}"
        local action="${fields[1]}"
        
        [ "$line_context" != "$context" ] && [ "$line_context" != "all" ] && continue
        
        # 处理exec操作 (执行Shell命令)
        if [ "$action" == "exec" ]; then
            if [ $num_fields -lt 4 ]; then
                log WARNING "exec操作需要至少4个字段: $line" "配置定制"
                continue
            fi
            
            local cmd_desc="${fields[2]}"
            local actual_cmd="${fields[3]}"
            
            log INFO "执行命令: $cmd_desc" "配置定制"
            log DEBUG "命令: $actual_cmd" "配置定制"
            
            # 执行命令并捕获输出
            output=$(eval "$actual_cmd" 2>&1)
            result=$?
            
            if [ $result -eq 0 ]; then
                log SUCCESS "命令执行成功: $cmd_desc" "配置定制"
                ((applied_rules++))
            else
                log ERROR "命令执行失败: $cmd_desc (退出码: $result)" "配置定制"
                log DEBUG "输出: $output" "配置定制"
            fi
        
        # 处理其他操作类型
        else
            if [ $num_fields -lt 5 ]; then
                log WARNING "非exec操作需要至少5个字段: $line" "配置定制"
                continue
            fi
            
            local target_file="${fields[2]}"
            local arg1="${fields[3]}"
            local arg2="${fields[4]}"
            
            apply_customization "$target_file" "$action" "$arg1" "$arg2" && ((applied_rules++))
        fi
        
    done < "$CUSTOMIZE_CONFIG"
    
    if [ $line_count -eq 0 ]; then
        log WARNING "没有找到适用于${context}上下文的定制规则" "配置定制"
        if [ "$context" == "init" ]; then
            customize_default_settings_init
        elif [ "$context" == "build" ]; then
            customize_default_settings_build "$build_time"
        fi
    else
        log SUCCESS "${context}阶段配置文件定制完成 (应用 ${applied_rules}/${line_count} 条规则)" "配置定制"
    fi
}

# 初始化阶段默认设置定制
customize_default_settings_init() {
    log INFO "应用初始化阶段默认设置" "配置定制"
    local applied=0
    
    # 1. 修改固件描述信息
    local target_desc="LEDE Build by ${AUTHOR} @ __BUILD_TIME__"
    if apply_customization "$ZZZ_SETTINGS" "replace" "DISTRIB_DESCRIPTION='.*'" "DISTRIB_DESCRIPTION='${target_desc}'"; then
        ((applied++))
    fi
    
    # 2. 添加网络和主机名配置
    local network_config="uci set network.lan.ipaddr='192.168.8.1'   # 默认 IP 地址"
    local hostname_config="uci set system.@system[0].hostname='M28C'"
    
    if ! grep -qF "$network_config" "$ZZZ_SETTINGS"; then
        apply_customization "$ZZZ_SETTINGS" "insert-after" "DISTRIB_DESCRIPTION='LEDE Build by ${AUTHOR} @ __BUILD_TIME__'" "$network_config" && ((applied++))
    fi
    
    if ! grep -qF "$hostname_config" "$ZZZ_SETTINGS"; then
        apply_customization "$ZZZ_SETTINGS" "insert-after" "DISTRIB_DESCRIPTION='LEDE Build by ${AUTHOR} @ __BUILD_TIME__'" "$hostname_config" && ((applied++))
    fi
    
    log INFO "应用了 ${applied} 条默认设置" "配置定制"
}

# 编译阶段默认设置定制
customize_default_settings_build() {
    local build_time="$1"
    log INFO "应用编译阶段默认设置" "配置定制"
    local applied=0
    
    local target_desc="LEDE Build by ${AUTHOR} @ ${build_time}"
    sed -i "s|DISTRIB_DESCRIPTION='.*'|DISTRIB_DESCRIPTION='${target_desc}'|g" "$ZZZ_SETTINGS" && {
        log SUCCESS "构建时间更新成功: ${ZZZ_SETTINGS/#$PROJECT_ROOT\//}" "配置定制"
        ((applied++))
    }
    
    log INFO "应用了 ${applied} 条默认设置" "配置定制"
}

# 运行交互式配置
run_interactive_configuration() {
    log INFO "启动交互式配置菜单" "配置管理"
    validate_dir "$SRC_DIR" || return 1
    
    exec >/dev/tty 2>&1
    pushd "$SRC_DIR" >/dev/null || return 1
    log DEBUG "执行: make menuconfig" "配置管理"
    make menuconfig
    local result=$?
    popd >/dev/null
    
    [ $result -eq 0 ] && log SUCCESS "配置菜单操作完成" "配置管理" || log ERROR "配置菜单操作失败" "配置管理"
    return $result
}