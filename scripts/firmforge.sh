#!/bin/bash
# OpenWrt高级构建管理系统 - 主入口
# 版本: 3.8.1
# 作者: KCrO
# 更新: 2025-07-09

# 加载库
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib/common.sh"
source "${SCRIPT_DIR}/lib/logging.sh"
source "${SCRIPT_DIR}/lib/backup.sh"
source "${SCRIPT_DIR}/lib/packages.sh"
source "${SCRIPT_DIR}/lib/feeds.sh"
source "${SCRIPT_DIR}/lib/build.sh"
source "${SCRIPT_DIR}/lib/config.sh"
source "${SCRIPT_DIR}/lib/artifacts.sh"

# 设置错误处理和清理
trap 'cleanup_logging; exit' EXIT
trap 'trap_error ${LINENO} "$BASH_COMMAND"; cleanup_logging; exit 1' ERR

# 主函数
main() {
    init_logging "$1"
    
    case "$1" in
    init) initialize_build_environment ;;
    clean) clean_build_environment ;;
    backup) backup_critical_files ;;
    install) install_custom_packages ;;
    download) download_remote_packages ;;
    update) shift; update_downloaded_packages "$@" ;;
    feeds) update_and_install_feeds ;;
    build) compile_firmware ;;
    clean-build) clean_compilation_files ;;
    config) run_interactive_configuration ;;
    copy) 
        shift
        copy_build_artifacts "$1" 
        ;;
    full-build) full_build_process;;
    help | *) show_help ;;
    esac
}

# 启动脚本
main "$@"