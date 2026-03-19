use dialoguer::{Confirm, Select, theme::ColorfulTheme};
use serde::{Deserialize, Serialize};
use colored::*;
use std::env;
use std::fs::{self, File};
use std::io::{BufRead, BufReader, Write};
use std::path::Path;
use std::process;

const TARGETS_DIR: &str = "targets";
const SRCS_DIR: &str = "srcs";
const CONFIG_FILE: &str = ".config";
const CONFIG_TARGET_KEY: &str = "CONFIG_TARGET";
const CONFIG_SRC_KEY: &str = "CONFIG_SRC";

#[derive(Debug, Serialize, Deserialize)]
struct SourceConfig {
    url: String,
    revision: String, // 可以是分支名或 commit hash
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
                eprintln!("{}", "请指定 target 子命令: init 或 update".red());
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
                _ => {
                    eprintln!("{}", format!("未知 target 子命令: {}", sub).red());
                    process::exit(1);
                }
            }
        }
        "completions" => {
            if args.len() < 3 {
                eprintln!("{}", "请指定 shell 类型，例如: owbm completions bash".red());
                process::exit(1);
            }
            let shell = &args[2];
            if let Err(err) = print_completions(shell) {
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
    println!("  {} {}", "owbm target init".green(), "          初始化当前目标的源码配置并下载".white());
    println!("  {} {}", "owbm target update".green(), "        更新当前目标的源码".white());
    println!("  {} {}", "owbm completions <shell>".green(), "   生成 shell 补全脚本 (目前支持 bash)".white());
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
    println!("{}", format!("已选择目标: {}，并保存到 .config", selected).green());

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
        // 读取现有配置
        let content = fs::read_to_string(&source_json_path)?;
        serde_json::from_str(&content)?
    } else {
        // 创建模板并提示用户编辑
        println!("{}", "source.json 不存在，正在创建模板...".yellow());
        let template = SourceConfig {
            url: "https://github.com/example/repo.git".to_string(),
            revision: "main".to_string(),
        };
        let template_content = serde_json::to_string_pretty(&template)?;
        fs::write(&source_json_path, &template_content)?;
        println!("{}", format!("模板已创建: {}", source_json_path.display()).green());
        println!("{}", "请编辑该文件，填入正确的 URL 和 revision，然后再次运行 owbm target init".cyan());
        return Ok(());
    };

    // 4. 将 source_config 写入 .config 的 CONFIG_SRC
    let src_value = format!("{};{}", source_config.url, source_config.revision);
    update_config(CONFIG_SRC_KEY, &src_value)?;
    println!("{}", format!("已更新 .config 中的 {}={}", CONFIG_SRC_KEY, src_value).green());

    // 5. 下载源码到 srcs/<target>
    download_source(&target, &source_config)?;

    Ok(())
}

/// target update 命令
fn target_update() -> Result<(), Box<dyn std::error::Error>> {
    let target = get_current_target()?;
    println!("{}", format!("当前目标: {}", target).cyan());

    // 读取 CONFIG_SRC
    let src_value = read_config_value(CONFIG_SRC_KEY)?;
    let (_url, revision) = parse_src_value(&src_value)?;

    let src_dir = Path::new(SRCS_DIR).join(&target);
    if !src_dir.exists() {
        return Err(format!("源码目录 '{}' 不存在，请先运行 owbm target init", src_dir.display()).into());
    }

    // 进入目录执行 git pull 和 checkout
    println!("{}", format!("正在更新 {} 的源码...", target).cyan());
    let status = process::Command::new("git")
        .arg("-C")
        .arg(&src_dir)
        .arg("fetch")
        .status()?;
    if !status.success() {
        return Err("git fetch 失败".into());
    }

    // checkout 到指定 revision
    let status = process::Command::new("git")
        .arg("-C")
        .arg(&src_dir)
        .arg("checkout")
        .arg(&revision)
        .status()?;
    if !status.success() {
        return Err(format!("git checkout {} 失败", revision).into());
    }

    // 如果是分支，还需要 pull
    // 简单判断 revision 是否像 commit hash (40位16进制)，否则当作分支 pull
    if revision.len() != 40 || revision.chars().any(|c| !c.is_ascii_hexdigit()) {
        // 可能是分支名，执行 git pull
        let status = process::Command::new("git")
            .arg("-C")
            .arg(&src_dir)
            .arg("pull")
            .status()?;
        if !status.success() {
            return Err("git pull 失败".into());
        }
    } else {
        // 是 commit hash，只需要 fetch 后 checkout 即可
        println!("{}", format!("已切换到 commit {}", revision).green());
    }

    println!("{}", "源码更新完成。".green());
    Ok(())
}

/// 从 .config 读取当前目标
fn get_current_target() -> Result<String, Box<dyn std::error::Error>> {
    let config_path = env::current_dir()?.join(CONFIG_FILE);
    if !config_path.exists() {
        return Err("没有找到 .config 文件，请先运行 owbm change 选择目标。".into());
    }
    let target = read_current_target(&config_path)?;
    target.ok_or_else(|| "当前 .config 中未设置 CONFIG_TARGET，请运行 owbm change 选择目标。".into())
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
            .with_prompt(format!("目录 '{}' 已存在，是否删除并重新克隆？", src_dir.display()))
            .interact()?;
        if confirm {
            fs::remove_dir_all(&src_dir)?;
        } else {
            println!("{}", "取消下载。".yellow());
            return Ok(());
        }
    }

    // 确保父目录存在
    if let Some(parent) = src_dir.parent() {
        if !parent.exists() {
            fs::create_dir_all(parent)?;
        }
    }

    println!("{}", format!("正在浅克隆 {} 到 {}...", config.url, src_dir.display()).cyan());
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

    // checkout 指定 revision（浅克隆可能无法切换到历史 commit，但指定分支或最新 commit 可以）
    println!("{}", format!("正在切换到 revision {}...", config.revision).cyan());
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
        // 文件不存在，直接创建并写入
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

/// 输出 shell 补全脚本（bash）
fn print_completions(shell: &str) -> Result<(), Box<dyn std::error::Error>> {
    match shell {
        "bash" => {
            println!("# 将以下内容添加到 .bashrc 或执行 source <(owbm completions bash)");
            println!("_owbm_completions() {{");
            println!("  local cur prev words cword");
            println!("  _init_completion || return");
            println!("  case $prev in");
            println!("    owbm)");
            println!("      COMPREPLY=($(compgen -W \"list change target completions\" -- \"$cur\"))");
            println!("      ;;");
            println!("    target)");
            println!("      COMPREPLY=($(compgen -W \"init update\" -- \"$cur\"))");
            println!("      ;;");
            println!("    *)");
            println!("      ;;");
            println!("  esac");
            println!("}}");
            println!("complete -F _owbm_completions owbm");
        }
        _ => return Err(format!("不支持的 shell: {}", shell).into()),
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
                eprintln!("{}", format!("警告: 忽略非 UTF-8 目录名: {:?}", entry.file_name()).yellow());
            }
        }
    }

    targets.sort();
    Ok(targets)
}