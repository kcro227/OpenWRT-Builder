# Bash completion for owbm
_owbm_completions() {
    local cur prev words cword
    _init_completion || return

    case $prev in
        owbm)
            COMPREPLY=($(compgen -W "list change sync target package build custom command" -- "$cur"))
            ;;
        target)
            COMPREPLY=($(compgen -W "init update config feed download" -- "$cur"))
            ;;
        package)
            COMPREPLY=($(compgen -W "feed install update" -- "$cur"))
            ;;
        custom)
            # 获取当前目标
            local target=$(grep -E '^CONFIG_TARGET=' .config 2>/dev/null | cut -d= -f2)
            if [[ -n "$target" && -d "targets/$target/cus" ]]; then
                # 列出 cus 目录下的所有脚本（按命名规则提取短名）
                local scripts=()
                for f in targets/$target/cus/*; do
                    if [[ -f "$f" ]]; then
                        local base=$(basename "$f")
                        # 提取下划线后的部分，直到点号
                        local name=$(echo "$base" | sed -n 's/^[^_]*_\([^.]*\).*$/\1/p')
                        [[ -n "$name" ]] && scripts+=("$name")
                    fi
                done
                COMPREPLY=($(compgen -W "${scripts[*]}" -- "$cur"))
            fi
            ;;
        *)
            ;;
    esac
}
complete -F _owbm_completions owbm ./owbm