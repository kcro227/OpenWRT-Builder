# Bash completion for owbm
_owbm_completions() {
    local cur prev words cword
    _init_completion || return

    case $prev in
        owbm)
            COMPREPLY=($(compgen -W "list select change sync target package build custom run exec" -- "$cur"))
            ;;
        target)
            COMPREPLY=($(compgen -W "init update config feed download clean distclean" -- "$cur"))
            ;;
        package)
            COMPREPLY=($(compgen -W "feed install update" -- "$cur"))
            ;;
        custom)
            local target
            target=$(grep -E '^CONFIG_TARGET=' .config 2>/dev/null | cut -d= -f2 | tr -d '\r')
            if [[ -n "$target" && -d "targets/$target/custom" ]]; then
                local scripts=()
                local f
                for f in "targets/$target/custom"/*; do
                    if [[ -f "$f" ]]; then
                        local base name
                        base=$(basename "$f")
                        name=$(echo "$base" | sed -n 's/^[^_]*_\([^.]*\).*$/\1/p')
                        if [[ -n "$name" ]]; then
                            scripts+=("$name")
                        fi
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