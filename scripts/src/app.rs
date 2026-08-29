use colored::*;
use serde::{Deserialize, Serialize};
use std::env;
use std::process;

pub const TARGETS_DIR: &str = "targets";
pub const SRCS_DIR: &str = "srcs";
pub const PACKAGES_DIR: &str = "packages";
pub const CONFIG_FILE: &str = ".config";
pub const CONFIG_TARGET_KEY: &str = "CONFIG_TARGET";
pub const CONFIG_SRC_KEY: &str = "CONFIG_SRC";
pub const FEED_CONFIG_FILE: &str = "feed.config";

#[derive(Debug, Serialize, Deserialize)]
pub struct SourceConfig {
    pub url: String,
    pub revision: String,
}

pub static INTERRUPTED: std::sync::atomic::AtomicBool = std::sync::atomic::AtomicBool::new(false);

pub fn run() {
    ctrlc::set_handler(|| {
        INTERRUPTED.store(true, std::sync::atomic::Ordering::SeqCst);
    })
    .expect("设置 Ctrl+C 处理函数失败");

    let args: Vec<String> = env::args().collect();

    if args.len() < 2 {
        print_help();
        process::exit(1);
    }

    let command = &args[1];
    match command.as_str() {
        "list" => {
            if let Err(err) = crate::targets::list_targets(TARGETS_DIR) {
                eprintln!("{}", format!("错误: {}", err).red());
                process::exit(1);
            }
        }
        "change" => {
            if let Err(err) = crate::config::change_target(TARGETS_DIR) {
                eprintln!("{}", format!("错误: {}", err).red());
                process::exit(1);
            }
        }
        "target" => {
            if args.len() < 3 {
                eprintln!("{}", "请指定 target 子命令: init, update, config, feed, download, clean, distclean".red());
                process::exit(1);
            }
            let sub = &args[2];
            let result = match sub.as_str() {
                "init" => crate::targets::target_init(),
                "update" => crate::targets::target_update(),
                "config" => crate::targets::target_config(),
                "feed" => crate::targets::target_feed(),
                "download" => crate::targets::target_download(),
                "clean" => crate::targets::target_clean(),
                "distclean" => crate::targets::target_distclean(),
                _ => {
                    eprintln!("{}", format!("未知 target 子命令: {}", sub).red());
                    process::exit(1);
                }
            };
            if let Err(err) = result {
                eprintln!("{}", format!("错误: {}", err).red());
                process::exit(1);
            }
        }
        "package" => {
            if args.len() < 3 {
                eprintln!("{}", "请指定 package 子命令: feed, update 或 install".red());
                process::exit(1);
            }
            let sub = &args[2];
            let result = match sub.as_str() {
                "feed" => crate::packages::package_feed(),
                "update" => crate::packages::package_update(),
                "install" => crate::packages::package_install(),
                _ => {
                    eprintln!("{}", format!("未知 package 子命令: {}", sub).red());
                    process::exit(1);
                }
            };
            if let Err(err) = result {
                eprintln!("{}", format!("错误: {}", err).red());
                process::exit(1);
            }
        }
        "sync" => {
            if let Err(err) = crate::targets::config_sync() {
                eprintln!("{}", format!("错误: {}", err).red());
                process::exit(1);
            }
        }
        "build" => {
            if let Err(err) = crate::build::build() {
                eprintln!("{}", format!("错误: {}", err).red());
                process::exit(1);
            }
        }
        "custom" => {
            if args.len() < 3 {
                eprintln!("{}", "请指定要执行的自定义脚本名称".red());
                process::exit(1);
            }
            let script_name = &args[2];
            let extra_args: Vec<String> = args.iter().skip(3).cloned().collect();
            if let Err(err) = crate::build::run_custom_script(script_name, &extra_args) {
                eprintln!("{}", format!("错误: {}", err).red());
                process::exit(1);
            }
        }
        "command" => {
            if args.len() < 3 {
                eprintln!("{}", "请指定要在源码目录中执行的命令 (带引号)".red());
                process::exit(1);
            }
            let cmd = &args[2];
            if let Err(err) = crate::build::run_command(cmd) {
                eprintln!("{}", format!("错误: {}", err).red());
                process::exit(1);
            }
        }
        _ => {
            eprintln!("{}", format!("未知命令: {}", command).red());
            print_help();
            process::exit(1);
        }
    }
}

pub fn print_help() {
    println!("{}", "owbm - OpenWrt Build Manager".cyan().bold());
    println!("{}", "用法:".yellow());
    println!("  {} {}", "owbm list".green(), "                 列出所有可用的编译目标".white());
    println!("  {} {}", "owbm change".green(), "               交互式选择编译目标并保存到 .config".white());
    println!("  {} {}", "owbm sync".green(), "                 同步当前目标的软件包配置到 .config".white());
    println!("  {} {}", "owbm target init".green(), "          初始化当前目标的源码配置并下载".white());
    println!("  {} {}", "owbm target update".green(), "        更新当前目标的源码".white());
    println!("  {} {}", "owbm target config".green(), "        运行 make menuconfig 配置内核".white());
    println!("  {} {}", "owbm target feed".green(), "          更新并安装 feeds".white());
    println!("  {} {}", "owbm target download".green(), "       下载所需的软件包 (make download)".white());
    println!("  {} {}", "owbm target clean".green(), "         清理编译中间文件 (make clean)".white());
    println!("  {} {}", "owbm target distclean".green(), "     彻底清理 (make distclean)".white());
    println!("  {} {}", "owbm package feed [pkg;pkg]".green(), " 下载 feeds.config 中定义的软件包（可选指定包名）".white());
    println!("  {} {}", "owbm package update [pkg;pkg]".green(), " 更新 feeds.config 中已下载的软件包（可选指定包名）".white());
    println!("  {} {}", "owbm package install [pkg;pkg]".green(), " 根据 .config 安装选中的软件包（可选指定包名）".white());
    println!("  {} {}", "owbm build".green(), "                编译源码".white());
    println!("  {} {}", "owbm custom <name>".green(), "         执行当前目标的自定义脚本".white());
    println!("  {} {}", "owbm command \"<cmd>\"".green(), "     在源码目录中执行任意命令".white());
}
