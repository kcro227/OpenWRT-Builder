use colored::*;
use dialoguer::{Confirm, Select, theme::ColorfulTheme};
use serde::{Deserialize, Serialize};
use std::env;
use std::fs::{self, File};
use std::io::{BufRead, BufReader, Write};
use std::path::{Path, PathBuf};
use std::process;
use walkdir::WalkDir;

const TARGETS_DIR: &str = "targets";
const SRCS_DIR: &str = "srcs";
const PACKAGES_DIR: &str = "packages";
const CONFIG_FILE: &str = ".config";
const CONFIG_TARGET_KEY: &str = "CONFIG_TARGET";
const CONFIG_SRC_KEY: &str = "CONFIG_SRC";
const FEED_CONFIG_FILE: &str = "feed.config";

#[derive(Debug, Serialize, Deserialize)]
struct SourceConfig {
    url: String,
    revision: String,
}

fn main() {
    let args: Vec<String> = env::args().collect();

    if args.len() < 2 {
        print_help();
        process::exit(1);
    }

    let command = &args[1];
    match command.as_str() {
        "list" => {
            if let Err(err) = list_targets(TARGETS_DIR) {
                eprintln!("{}", format!("错误: {}", err).red());
                process::exit(1);
            }
        }
        "change" => {
            if let Err(err) = change_target(TARGETS_DIR) {
                eprintln!("{}", format!("错误: {}", err).red());
                process::exit(1);
            }
        }
        "target" => {
            if args.len() < 3 {
                eprintln!("{}", "请指定 target 子命令: init, update, config, feed, download".red());
                process::exit(1);
            }
            let sub = &args[2];
            match sub.as_str() {
                "init" => {
                    if let Err(err) = target_init() {
                        eprintln!("{}", format!("错误: {}", err).red());
                        process::exit(1);
                    }
                }
                "update" => {
                    if let Err(err) = target_update() {
                        eprintln!("{}", format!("错误: {}", err).red());
                        process::exit(1);
                    }
                }
                "config" => {
                    if let Err(err) = target_config() {
                        eprintln!("{}", format!("错误: {}", err).red());
                        process::exit(1);
                    }
                }
                "feed" => {
                    if let Err(err) = target_feed() {
                        eprintln!("{}", format!("错误: {}", err).red());
                        process::exit(1);
                    }
                }
                "download" => {
                    if let Err(err) = target_download() {
                        eprintln!("{}", format!("错误: {}", err).red());
                        process::exit(1);
                    }
                }
                _ => {
                    eprintln!("{}", format!("未知 target 子命令: {}", sub).red());
                    process::exit(1);
                }
            }
        }
        "package" => {
            if args.len() < 3 {
                eprintln!("{}", "请指定 package 子命令: feed 或 install".red());
                process::exit(1);
            }
            let sub = &args[2];
            match sub.as_str() {
                "feed" => {
                    if let Err(err) = package_feed() {
                        eprintln!("{}", format!("错误: {}", err).red());
                        process::exit(1);
                    }
                }
                "install" => {
                    if let Err(err) = package_install() {
                        eprintln!("{}", format!("错误: {}", err).red());
                        process::exit(1);
                    }
                }
                _ => {
                    eprintln!("{}", format!("未知 package 子命令: {}", sub).red());
                    process::exit(1);
                }
            }
        }
        "sync" => {
            if let Err(err) = config_sync() {
                eprintln!("{}", format!("错误: {}", err).red());
                process::exit(1);
            }
        }
        "build" => {
            if let Err(err) = build() {
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
            if let Err(err) = run_custom_script(script_name, &extra_args) {
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
            if let Err(err) = run_command(cmd) {
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

fn print_help() {
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
    println!("  {} {}", "owbm package feed".green(), "         下载 feeds.config 中定义的软件包".white());
    println!("  {} {}", "owbm package install".green(), "      根据 .config 安装选中的软件包".white());
    println!("  {} {}", "owbm build".green(), "                编译源码".white());
    println!("  {} {}", "owbm custom <name>".green(), "         执行当前目标的自定义脚本".white());
    println!("  {} {}", "owbm command \"<cmd>\"".green(), "     在源码目录中执行任意命令".white());
}

/// 列出 targets 目录下所有一级子目录
fn list_targets<P: AsRef<Path>>(path: P) -> Result<(), Box<dyn std::error::Error>> {
    let path = path.as_ref();
    ensure_dir_exists(path)?;

    let targets = read_targets(path)?;
    if targets.is_empty() {
        println!("{}", "没有找到任何目标。".yellow());
    } else {
        println!("{}", "可用的编译目标:".cyan());
        for target in targets {
            println!("  {}", target.green());
        }
    }
    Ok(())
}

/// 同步软件包配置：读取 targets/<target>/packagelist.txt，将每个包名写入 .config 的 CONFIG_PACKAGE_包名=y
/// 返回添加的包数量（新添加或更新的）
fn sync_package_config(target: &str) -> Result<usize, Box<dyn std::error::Error>> {
    let packagelist_path = Path::new(TARGETS_DIR).join(target).join("packagelist.txt");
    if !packagelist_path.exists() {
        println!("{}", format!("目标 '{}' 没有 packagelist.txt，跳过软件包同步。", target).yellow());
        return Ok(0);
    }

    let file = File::open(&packagelist_path)?;
    let reader = BufReader::new(file);
    let mut count = 0;
    for line in reader.lines() {
        let line = line?;
        let line = line.trim();
        if line.is_empty() || line.starts_with('#') {
            continue;
        }
        let pkg_key = format!("CONFIG_PACKAGE_{}", line);
        update_config(&pkg_key, "y")?;
        count += 1;
    }
    Ok(count)
}

/// 交互式选择目标，以 CONFIG_TARGET=xxx 格式更新 .config
fn change_target<P: AsRef<Path>>(path: P) -> Result<(), Box<dyn std::error::Error>> {
    let path = path.as_ref();
    ensure_dir_exists(path)?;

    let targets = read_targets(path)?;
    if targets.is_empty() {
        return Err("没有可用的目标，无法选择。".into());
    }

    let current_dir = env::current_dir()?;
    let config_path = current_dir.join(CONFIG_FILE);

    // 读取当前选中的目标
    let current_target = read_current_target(&config_path)?;

    let default_index = current_target
        .as_ref()
        .and_then(|cur| targets.iter().position(|t| t == cur))
        .unwrap_or(0);

    let selection = Select::with_theme(&ColorfulTheme::default())
        .with_prompt(format!(
            "请选择编译目标 (当前: {})",
            current_target.as_deref().unwrap_or("无")
        ))
        .default(default_index)
        .items(&targets)
        .interact()?;

    let selected = &targets[selection];
    update_config(CONFIG_TARGET_KEY, selected)?;
    println!(
        "{}",
        format!("已选择目标: {}，并保存到 .config", selected).green()
    );

    // 同步包配置
    let added = sync_package_config(selected)?;
    if added > 0 {
        println!("{}", format!("已同步 {} 个软件包配置到 .config", added).green());
    } else {
        println!("{}", "软件包配置无变化。".yellow());
    }
    Ok(())
}

/// target init 命令
fn target_init() -> Result<(), Box<dyn std::error::Error>> {
    // 1. 读取当前目标
    let target = get_current_target()?;
    println!("{}", format!("当前目标: {}", target).cyan());

    // 2. 确保 targets/<target> 目录存在
    let target_dir = Path::new(TARGETS_DIR).join(&target);
    if !target_dir.exists() {
        return Err(format!("目标目录 '{}' 不存在", target_dir.display()).into());
    }

    // 3. 处理 source.json
    let source_json_path = target_dir.join("source.json");
    let source_config: SourceConfig = if source_json_path.exists() {
        let content = fs::read_to_string(&source_json_path)?;
        serde_json::from_str(&content)?
    } else {
        println!("{}", "source.json 不存在，正在创建模板...".yellow());
        let template = SourceConfig {
            url: "https://github.com/example/repo.git".to_string(),
            revision: "main".to_string(),
        };
        let template_content = serde_json::to_string_pretty(&template)?;
        fs::write(&source_json_path, &template_content)?;
        println!(
            "{}",
            format!("模板已创建: {}", source_json_path.display()).green()
        );
        println!(
            "{}",
            "请编辑该文件，填入正确的 URL 和 revision，然后再次运行 owbm target init".cyan()
        );
        return Ok(());
    };

    // 4. 将 source_config 写入 .config 的 CONFIG_SRC
    let src_value = format!("{};{}", source_config.url, source_config.revision);
    update_config(CONFIG_SRC_KEY, &src_value)?;
    println!(
        "{}",
        format!("已更新 .config 中的 {}={}", CONFIG_SRC_KEY, src_value).green()
    );

    // 5. 下载源码到 srcs/<target>
    download_source(&target, &source_config)?;

    // 6. 同步包配置
    let added = sync_package_config(&target)?;
    if added > 0 {
        println!("{}", format!("已同步 {} 个软件包配置到 .config", added).green());
    } else {
        println!("{}", "未找到 packagelist.txt 或文件为空，软件包配置无变化。".yellow());
    }

    Ok(())
}

/// target update 命令
fn target_update() -> Result<(), Box<dyn std::error::Error>> {
    let target = get_current_target()?;
    println!("{}", format!("当前目标: {}", target).cyan());

    let src_value = read_config_value(CONFIG_SRC_KEY)?;
    let (_url, revision) = parse_src_value(&src_value)?;

    let src_dir = Path::new(SRCS_DIR).join(&target);
    if !src_dir.exists() {
        return Err(format!(
            "源码目录 '{}' 不存在，请先运行 owbm target init",
            src_dir.display()
        )
        .into());
    }

    println!("{}", format!("正在更新 {} 的源码...", target).cyan());
    let status = process::Command::new("git")
        .arg("-C")
        .arg(&src_dir)
        .arg("fetch")
        .status()?;
    if !status.success() {
        return Err("git fetch 失败".into());
    }

    let status = process::Command::new("git")
        .arg("-C")
        .arg(&src_dir)
        .arg("checkout")
        .arg(&revision)
        .status()?;
    if !status.success() {
        return Err(format!("git checkout {} 失败", revision).into());
    }

    if revision.len() != 40 || revision.chars().any(|c| !c.is_ascii_hexdigit()) {
        let status = process::Command::new("git")
            .arg("-C")
            .arg(&src_dir)
            .arg("pull")
            .status()?;
        if !status.success() {
            return Err("git pull 失败".into());
        }
    } else {
        println!("{}", format!("已切换到 commit {}", revision).green());
    }

    println!("{}", "源码更新完成。".green());
    Ok(())
}

/// 通用函数：在源码目录中执行 make 命令，传递所有额外参数
fn run_make(target: &str, make_args: &[String]) -> Result<(), Box<dyn std::error::Error>> {
    let src_dir = Path::new(SRCS_DIR).join(target);
    if !src_dir.exists() {
        return Err(format!("源码目录 '{}' 不存在，请先运行 owbm target init", src_dir.display()).into());
    }

    let mut cmd = process::Command::new("make");
    cmd.arg("-C").arg(&src_dir);
    cmd.args(make_args);

    println!("{}", format!("执行命令: {:?}", cmd).cyan());
    let status = cmd.status()?;
    if !status.success() {
        return Err("make 命令执行失败".into());
    }
    Ok(())
}

/// target config 命令：运行 make menuconfig，传递额外参数
fn target_config() -> Result<(), Box<dyn std::error::Error>> {
    let target = get_current_target()?;
    let args: Vec<String> = env::args().collect();
    let extra_args: Vec<String> = args.iter().skip(3).cloned().collect(); // 跳过 "target" 和 "config"
    let mut make_args = vec!["menuconfig".to_string()];
    make_args.extend(extra_args);
    run_make(&target, &make_args)?;
    Ok(())
}

/// target download 命令：调用 make download，传递所有额外参数
fn target_download() -> Result<(), Box<dyn std::error::Error>> {
    let target = get_current_target()?;
    let args: Vec<String> = env::args().collect();
    let extra_args: Vec<String> = args.iter().skip(3).cloned().collect(); // 跳过 "target" 和 "download"
    let mut make_args = vec!["download".to_string()];
    make_args.extend(extra_args);
    run_make(&target, &make_args)?;
    Ok(())
}

/// build 命令：直接编译源码，传递所有额外参数
fn build() -> Result<(), Box<dyn std::error::Error>> {
    let target = get_current_target()?;
    let args: Vec<String> = env::args().collect();
    let extra_args: Vec<String> = args.iter().skip(2).cloned().collect(); // 跳过 "build"
    run_make(&target, &extra_args)?;
    Ok(())
}

/// target feed 命令：更新并安装 feeds
fn target_feed() -> Result<(), Box<dyn std::error::Error>> {
    let target = get_current_target()?;
    let src_dir = Path::new(SRCS_DIR).join(&target);
    if !src_dir.exists() {
        return Err(format!("源码目录 '{}' 不存在，请先运行 owbm target init", src_dir.display()).into());
    }
    let scripts_dir = src_dir.join("scripts");
    if !scripts_dir.exists() {
        return Err("scripts 目录不存在，可能不是 OpenWrt 源码？".into());
    }

    println!("{}", "正在更新 feeds...".cyan());
    let status = process::Command::new("./scripts/feeds")
        .arg("update")
        .current_dir(&src_dir)
        .status()?;
    if !status.success() {
        return Err("feeds update 失败".into());
    }

    println!("{}", "正在安装 feeds...".cyan());
    let status = process::Command::new("./scripts/feeds")
        .arg("install")
        .arg("-a")
        .current_dir(&src_dir)
        .status()?;
    if !status.success() {
        return Err("feeds install 失败".into());
    }

    println!("{}", "feeds 更新完成。".green());
    Ok(())
}

/// custom 命令：执行当前目标下的自定义脚本
fn run_custom_script(name: &str, extra_args: &[String]) -> Result<(), Box<dyn std::error::Error>> {
    let target = get_current_target()?;
    let cus_dir = Path::new(TARGETS_DIR).join(&target).join("cus");
    if !cus_dir.exists() {
        return Err(format!("自定义脚本目录不存在: {}", cus_dir.display()).into());
    }

    // 扫描目录，匹配以 name 结尾且符合 `<interpreter>_<name>.sh` 格式的文件
    let entries = fs::read_dir(&cus_dir)?;
    let mut matches = Vec::new();
    for entry in entries {
        let entry = entry?;
        let file_name = entry.file_name();
        let file_name_str = file_name.to_string_lossy();
        // 格式：解释器_名称.扩展名
        if let Some(underscore_pos) = file_name_str.find('_') {
            let (_, rest) = file_name_str.split_at(underscore_pos + 1);
            if let Some(dot_pos) = rest.find('.') {
                let base_name = &rest[..dot_pos];
                if base_name == name {
                    matches.push((file_name_str.to_string(), entry.path()));
                }
            } else {
                // 无扩展名，整个剩余部分作为名称
                if rest == name {
                    matches.push((file_name_str.to_string(), entry.path()));
                }
            }
        }
    }

    if matches.is_empty() {
        return Err(format!("未找到脚本 '{}' 在目录 {}", name, cus_dir.display()).into());
    }

    if matches.len() > 1 {
        println!(
            "{}",
            format!("找到多个匹配脚本，将使用第一个: {}", matches[0].0).yellow()
        );
    }

    let (script_name, script_path) = &matches[0];
    let interpreter = script_name.split('_').next().unwrap_or("bash");
    println!(
        "{}",
        format!("执行自定义脚本: {} (解释器: {})", script_name, interpreter).cyan()
    );

    let mut cmd = process::Command::new(interpreter);
    cmd.arg(script_path);
    cmd.args(extra_args);
    let status = cmd.status()?;
    if !status.success() {
        return Err(format!("脚本 '{}' 执行失败", script_name).into());
    }
    Ok(())
}

/// command 命令：在源码目录执行任意命令
fn run_command(cmd: &str) -> Result<(), Box<dyn std::error::Error>> {
    let target = get_current_target()?;
    let src_dir = Path::new(SRCS_DIR).join(&target);
    if !src_dir.exists() {
        return Err(format!("源码目录 '{}' 不存在，请先运行 owbm target init", src_dir.display()).into());
    }

    println!("{}", format!("在源码目录中执行: {}", cmd).cyan());
    let status = process::Command::new("sh")
        .arg("-c")
        .arg(cmd)
        .current_dir(&src_dir)
        .status()?;
    if !status.success() {
        return Err(format!("命令 '{}' 执行失败", cmd).into());
    }
    Ok(())
}

/// package feed: 下载 feeds.config 中定义的软件包
fn package_feed() -> Result<(), Box<dyn std::error::Error>> {
    let feed_config_path = Path::new(PACKAGES_DIR).join(FEED_CONFIG_FILE);
    if !feed_config_path.exists() {
        return Err(format!(
            "未找到 {}，请先创建 feeds 配置。",
            feed_config_path.display()
        )
        .into());
    }

    let file = File::open(&feed_config_path)?;
    let reader = BufReader::new(file);
    for line in reader.lines() {
        let line = line?;
        let line = line.trim();
        if line.is_empty() || line.starts_with('#') {
            continue;
        }
        let parts: Vec<&str> = line.split_whitespace().collect();
        if parts.len() < 3 {
            eprintln!("{}", format!("警告: 无效的 feed 配置行: {}", line).yellow());
            continue;
        }
        let feed_type = parts[0];
        let feed_name = parts[1];
        let url_and_rev = parts[2];

        let (base_url, revision) = if let Some(semi_pos) = url_and_rev.find(';') {
            let (url, rev) = url_and_rev.split_at(semi_pos);
            let rev = rev.trim_start_matches(';');
            if rev.is_empty() {
                (url, None)
            } else {
                (url, Some(rev))
            }
        } else {
            (url_and_rev, None)
        };

        let feed_dir = Path::new(PACKAGES_DIR).join(feed_name);

        if feed_dir.exists() {
            let confirm = Confirm::with_theme(&ColorfulTheme::default())
                .with_prompt(format!(
                    "Feed 目录 '{}' 已存在，是否删除并重新下载？",
                    feed_dir.display()
                ))
                .interact()?;
            if confirm {
                fs::remove_dir_all(&feed_dir)?;
            } else {
                println!("{}", format!("跳过 feed: {}", feed_name).yellow());
                continue;
            }
        }

        if !Path::new(PACKAGES_DIR).exists() {
            fs::create_dir_all(PACKAGES_DIR)?;
        }

        println!(
            "{}",
            format!("正在下载 feed: {} ({} {})", feed_name, feed_type, base_url).cyan()
        );
        if let Some(rev) = revision {
            println!("{}", format!("  使用 revision: {}", rev).cyan());
        } else {
            println!("{}", format!("  使用默认分支/版本").cyan());
        }

        let status = match feed_type {
            "src-git" => {
                let mut cmd = process::Command::new("git");
                cmd.arg("clone").arg("--depth").arg("1");
                if let Some(rev) = revision {
                    cmd.arg("--branch").arg(rev);
                }
                cmd.arg(base_url).arg(&feed_dir).status()?
            }
            "src-svn" => {
                let mut cmd = process::Command::new("svn");
                cmd.arg("checkout").arg("--depth").arg("immediates");
                if let Some(rev) = revision {
                    cmd.arg("-r").arg(rev);
                }
                cmd.arg(base_url).arg(&feed_dir).status()?
            }
            _ => {
                eprintln!("{}", format!("不支持 feed 类型: {}", feed_type).yellow());
                continue;
            }
        };
        if !status.success() {
            eprintln!("{}", format!("下载 feed {} 失败", feed_name).red());
        } else {
            println!("{}", format!("下载 feed {} 完成", feed_name).green());
        }
    }

    Ok(())
}

/// package install: 根据 .config 中选中的软件包，复制到目标源码的 package/custom 目录
fn package_install() -> Result<(), Box<dyn std::error::Error>> {
    let target = get_current_target()?;
    let target_src_dir = Path::new(SRCS_DIR).join(&target);
    if !target_src_dir.exists() {
        return Err(format!(
            "目标源码目录 '{}' 不存在，请先运行 owbm target init",
            target_src_dir.display()
        )
        .into());
    }

    let custom_dir = target_src_dir.join("package").join("custom");
    fs::create_dir_all(&custom_dir)?;

    // 从 .config 中读取所有 CONFIG_PACKAGE_* = y 的包
    let config_path = env::current_dir()?.join(CONFIG_FILE);
    if !config_path.exists() {
        return Err(".config 文件不存在，请先运行 owbm change 选择目标。".into());
    }

    let file = File::open(config_path)?;
    let reader = BufReader::new(file);
    let mut selected_packages = Vec::new();

    for line in reader.lines() {
        let line = line?;
        let line = line.trim();
        if line.starts_with("CONFIG_PACKAGE_") && line.ends_with("=y") {
            if let Some(pkg_name) = line
                .strip_prefix("CONFIG_PACKAGE_")
                .and_then(|s| s.strip_suffix("=y"))
            {
                selected_packages.push(pkg_name.to_string());
            }
        }
    }

    if selected_packages.is_empty() {
        println!(
            "{}",
            "没有选中的软件包（.config 中没有 CONFIG_PACKAGE_xxx=y 条目）。".yellow()
        );
        return Ok(());
    }

    println!(
        "{}",
        format!("找到 {} 个软件包需要安装。", selected_packages.len()).cyan()
    );

    // 在 packages 目录下递归查找每个包
    for pkg in &selected_packages {
        let found = find_package_dir(pkg)?;
        if let Some(src_path) = found {
            let dest_path = custom_dir.join(pkg);
            if dest_path.exists() {
                let confirm = Confirm::with_theme(&ColorfulTheme::default())
                    .with_prompt(format!("包 '{}' 已存在，是否覆盖？", pkg))
                    .interact()?;
                if !confirm {
                    println!("{}", format!("跳过包: {}", pkg).yellow());
                    continue;
                }
                fs::remove_dir_all(&dest_path)?;
            }
            copy_dir(&src_path, &dest_path)?;
            println!("{}", format!("已安装包: {}", pkg).green());
        } else {
            println!(
                "{}",
                format!(
                    "警告: 未找到软件包 '{}'，请先运行 owbm package feed 下载。",
                    pkg
                )
                .yellow()
            );
        }
    }

    Ok(())
}

/// 在 packages 目录下递归查找与包名同名的子目录
fn find_package_dir(package_name: &str) -> Result<Option<PathBuf>, Box<dyn std::error::Error>> {
    let packages_dir = Path::new(PACKAGES_DIR);
    if !packages_dir.exists() {
        return Ok(None);
    }

    for entry in WalkDir::new(packages_dir)
        .min_depth(1)
        .max_depth(10)
        .into_iter()
        .filter_entry(|e| e.file_type().is_dir())
    {
        let entry = entry?;
        if entry.file_name() == package_name {
            return Ok(Some(entry.path().to_path_buf()));
        }
    }
    Ok(None)
}

/// 递归复制目录
fn copy_dir(src: &Path, dst: &Path) -> Result<(), Box<dyn std::error::Error>> {
    fs::create_dir_all(dst)?;
    for entry in fs::read_dir(src)? {
        let entry = entry?;
        let src_path = entry.path();
        let dst_path = dst.join(entry.file_name());
        if src_path.is_dir() {
            copy_dir(&src_path, &dst_path)?;
        } else {
            fs::copy(&src_path, &dst_path)?;
        }
    }
    Ok(())
}

/// 从 .config 读取当前目标
fn get_current_target() -> Result<String, Box<dyn std::error::Error>> {
    let config_path = env::current_dir()?.join(CONFIG_FILE);
    if !config_path.exists() {
        return Err("没有找到 .config 文件，请先运行 owbm change 选择目标。".into());
    }
    let target = read_current_target(&config_path)?;
    target
        .ok_or_else(|| "当前 .config 中未设置 CONFIG_TARGET，请运行 owbm change 选择目标。".into())
}

/// 从 .config 中读取指定键的值
fn read_config_value(key: &str) -> Result<String, Box<dyn std::error::Error>> {
    let config_path = env::current_dir()?.join(CONFIG_FILE);
    if !config_path.exists() {
        return Err(format!(".config 文件不存在，无法读取 {}", key).into());
    }
    let file = File::open(config_path)?;
    let reader = BufReader::new(file);
    for line in reader.lines() {
        let line = line?;
        if line.starts_with(key) && line.contains('=') {
            if let Some(value) = line.split('=').nth(1) {
                return Ok(value.trim().to_string());
            }
        }
    }
    Err(format!(".config 中未找到键 {}", key).into())
}

/// 解析 CONFIG_SRC 的值，格式为 "url;revision"
fn parse_src_value(value: &str) -> Result<(String, String), Box<dyn std::error::Error>> {
    let parts: Vec<&str> = value.split(';').collect();
    if parts.len() != 2 {
        return Err("CONFIG_SRC 格式错误，应为 url;revision".into());
    }
    Ok((parts[0].to_string(), parts[1].to_string()))
}

/// 下载源码到 srcs/<target> (浅克隆)
fn download_source(target: &str, config: &SourceConfig) -> Result<(), Box<dyn std::error::Error>> {
    let src_dir = Path::new(SRCS_DIR).join(target);
    if src_dir.exists() {
        let confirm = Confirm::with_theme(&ColorfulTheme::default())
            .with_prompt(format!(
                "目录 '{}' 已存在，是否删除并重新克隆？",
                src_dir.display()
            ))
            .interact()?;
        if confirm {
            fs::remove_dir_all(&src_dir)?;
        } else {
            println!("{}", "取消下载。".yellow());
            return Ok(());
        }
    }

    if let Some(parent) = src_dir.parent() {
        if !parent.exists() {
            fs::create_dir_all(parent)?;
        }
    }

    println!(
        "{}",
        format!("正在浅克隆 {} 到 {}...", config.url, src_dir.display()).cyan()
    );
    let status = process::Command::new("git")
        .arg("clone")
        .arg("--depth")
        .arg("1")
        .arg(&config.url)
        .arg(&src_dir)
        .status()?;
    if !status.success() {
        return Err("git clone 失败".into());
    }

    println!(
        "{}",
        format!("正在切换到 revision {}...", config.revision).cyan()
    );
    let status = process::Command::new("git")
        .arg("-C")
        .arg(&src_dir)
        .arg("checkout")
        .arg(&config.revision)
        .status()?;
    if !status.success() {
        return Err(format!("git checkout {} 失败", config.revision).into());
    }

    println!("{}", "源码下载完成。".green());
    Ok(())
}

/// 从 .config 文件中读取 CONFIG_TARGET 的值
fn read_current_target(config_path: &Path) -> Result<Option<String>, Box<dyn std::error::Error>> {
    if !config_path.exists() {
        return Ok(None);
    }
    let file = File::open(config_path)?;
    let reader = BufReader::new(file);
    for line in reader.lines() {
        let line = line?;
        if line.starts_with(CONFIG_TARGET_KEY) && line.contains('=') {
            if let Some(value) = line.split('=').nth(1) {
                return Ok(Some(value.trim().to_string()));
            }
        }
    }
    Ok(None)
}

/// 更新 .config 文件中的指定键值对（若键已存在则替换，否则追加）
fn update_config(key: &str, value: &str) -> Result<(), Box<dyn std::error::Error>> {
    let config_path = env::current_dir()?.join(CONFIG_FILE);
    let new_line = format!("{}={}", key, value);

    if !config_path.exists() {
        fs::write(&config_path, new_line + "\n")?;
        return Ok(());
    }

    let content = fs::read_to_string(&config_path)?;
    let mut lines: Vec<String> = content.lines().map(String::from).collect();
    let mut found = false;

    for line in &mut lines {
        if line.starts_with(key) && line.contains('=') {
            *line = new_line.clone();
            found = true;
            break;
        }
    }

    if !found {
        lines.push(new_line);
    }

    let mut file = File::create(config_path)?;
    for line in lines {
        writeln!(file, "{}", line)?;
    }
    Ok(())
}

/// 确保目录存在且是目录
fn ensure_dir_exists(path: &Path) -> Result<(), Box<dyn std::error::Error>> {
    if !path.exists() {
        return Err(format!("目录 '{}' 不存在", path.display()).into());
    }
    if !path.is_dir() {
        return Err(format!("'{}' 不是一个目录", path.display()).into());
    }
    Ok(())
}

/// 读取 targets 目录下的所有一级子目录名，排序后返回
fn read_targets(path: &Path) -> Result<Vec<String>, Box<dyn std::error::Error>> {
    let entries = fs::read_dir(path)?;
    let mut targets = Vec::new();

    for entry in entries {
        let entry = entry?;
        let file_type = entry.file_type()?;
        if file_type.is_dir() {
            if let Some(name) = entry.file_name().to_str() {
                targets.push(name.to_string());
            } else {
                eprintln!(
                    "{}",
                    format!("警告: 忽略非 UTF-8 目录名: {:?}", entry.file_name()).yellow()
                );
            }
        }
    }

    targets.sort();
    Ok(targets)
}

/// config sync 命令 (顶级 sync)
fn config_sync() -> Result<(), Box<dyn std::error::Error>> {
    let target = get_current_target()?;
    println!("{}", format!("同步目标 {} 的配置...", target).cyan());
    let added = sync_package_config(&target)?;
    if added > 0 {
        println!("{}", format!("已同步 {} 个软件包配置到 .config", added).green());
    } else {
        println!("{}", "软件包配置无变化。".yellow());
    }
    Ok(())
}