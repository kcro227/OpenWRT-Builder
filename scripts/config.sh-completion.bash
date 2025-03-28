_config_comp() {
    local cur prev opts
    COMPREPLY=()
    cur="${COMP_WORDS[COMP_CWORD]}"
    opts="init clean backup install download update help"  # 新增download
    
    case ${cur} in
        cl*) COMPREPLY=( $(compgen -W "clean" -- "$cur") ) ;;
        i*)  COMPREPLY=( $(compgen -W "init install" -- "$cur") ) ;;
        d*)  COMPREPLY=( $(compgen -W "download" -- "$cur") ) ;;
        u*)  COMPREPLY=( $(compgen -W "update" -- "$cur"));;
        *)   COMPREPLY=( $(compgen -W "$opts" -- "$cur") ) ;;
    esac
}

complete -F _config_comp config.sh
complete -F _config_comp ./config.sh
complete -F _config_comp ../scripts/config.sh
complete -F _config_comp ./scripts/config.sh