use colored::*;
use dialoguer::{Confirm, Select, theme::ColorfulTheme};
use std::env;
use std::fs;
use std::path::Path;
use std::process;

use crate::app::{CONFIG_SRC_KEY, SourceConfig, SRCS_DIR, TARGETS_DIR};
use crate::build::run_make;
use crate::config::{ensure_dir_exists, get_current_target, read_targets, sync_package_config, update_config};

pub fn list_targets<P: AsRef<Path>>(path: P) -> Result<(), Box<dyn std::error::Error>> {
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

pub fn target_init() -> Result<(), Box<dyn std::error::Error>> {
    let target = get_current_target()?;
    println!("{}", format!("当前目标: {}", target).cyan());

    let target_dir = Path::new(TARGETS_DIR).join(&target);
    if !target_dir.exists() {
        return Err(format!("目标目录 '{}' 不存在", target_dir.display()).into());
    }

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
        println!("{}", format!("模板已创建: {}", source_json_path.display()).green());
        println!("{}", "请编辑该文件，填入正确的 URL 和 revision，然后再次运行 owbm target init".cyan());
        return Ok(());
    };

    let src_value = format!("{};{}", source_config.url, source_config.revision);
    update_config(CONFIG_SRC_KEY, &src_value)?;
    println!("{}", format!("已更新 .config 中的 {}={}", CONFIG_SRC_KEY, src_value).green());

    download_source(&target, &source_config)?;
    sync_package_config(&target)?;
    Ok(())
}

pub fn target_update() -> Result<(), Box<dyn std::error::Error>> {
    let target = get_current_target()?;
    println!("{}", format!("当前目标: {}", target).cyan());

    let src_dir = Path::new(SRCS_DIR).join(&target);
    if !src_dir.exists() {
        return Err(format!("源码目录 '{}' 不存在，请先运行 owbm target init", src_dir.display()).into());
    }

    println!("{}", format!("正在更新 {} 的源码...", target).cyan());

    let output = process::Command::new("git")
        .arg("-C")
        .arg(&src_dir)
        .arg("rev-parse")
        .arg("--abbrev-ref")
        .arg("HEAD")
        .output()?;
    if !output.status.success() {
        return Err("无法获取当前分支名".into());
    }
    let current_branch = String::from_utf8_lossy(&output.stdout).trim().to_string();

    let status = process::Command::new("git")
        .arg("-C")
        .arg(&src_dir)
        .arg("pull")
        .arg("--ff-only")
        .status()?;

    if status.success() {
        println!("{}", "源码更新完成。".green());
        return Ok(());
    }

    println!("{}", "git pull 失败，可能因为本地有未提交的更改或存在冲突。".yellow());
    let items = vec![
        "储藏本地更改后重试 (git stash + pull)",
        "强制拉取并丢弃本地更改 (git reset --hard)",
        "取消更新",
    ];
    let selection = Select::with_theme(&ColorfulTheme::default())
        .with_prompt("请选择处理方式")
        .items(&items)
        .default(0)
        .interact()?;

    match selection {
        0 => {
            println!("{}", "正在储藏本地更改...".cyan());
            let stash_status = process::Command::new("git")
                .arg("-C")
                .arg(&src_dir)
                .arg("stash")
                .status()?;
            if !stash_status.success() {
                return Err("git stash 失败".into());
            }

            println!("{}", "正在重新拉取...".cyan());
            let pull_status = process::Command::new("git")
                .arg("-C")
                .arg(&src_dir)
                .arg("pull")
                .arg("--ff-only")
                .status()?;
            if !pull_status.success() {
                return Err("储藏后 git pull 仍然失败".into());
            }

            let pop_stash = Confirm::with_theme(&ColorfulTheme::default())
                .with_prompt("拉取成功。是否恢复之前储藏的本地更改？")
                .default(true)
                .interact()?;
            if pop_stash {
                let pop_status = process::Command::new("git")
                    .arg("-C")
                    .arg(&src_dir)
                    .arg("stash")
                    .arg("pop")
                    .status()?;
                if !pop_status.success() {
                    println!("{}", "警告: git stash pop 失败，可能存在冲突，请手动处理。".yellow());
                }
            }
            println!("{}", "源码更新完成。".green());
        }
        1 => {
            println!("{}", "正在强制拉取（将丢弃所有本地更改）...".yellow());
            let fetch_status = process::Command::new("git")
                .arg("-C")
                .arg(&src_dir)
                .arg("fetch")
                .arg("origin")
                .status()?;
            if !fetch_status.success() {
                return Err("git fetch origin 失败".into());
            }

            let reset_status = process::Command::new("git")
                .arg("-C")
                .arg(&src_dir)
                .arg("reset")
                .arg("--hard")
                .arg(format!("origin/{}", current_branch))
                .status()?;
            if !reset_status.success() {
                return Err(format!("git reset --hard origin/{} 失败", current_branch).into());
            }
            println!("{}", "强制拉取完成。".green());
        }
        2 => {
            println!("{}", "已取消更新。".yellow());
            return Ok(());
        }
        _ => unreachable!(),
    }

    Ok(())
}

pub fn target_config() -> Result<(), Box<dyn std::error::Error>> {
    let target = get_current_target()?;
    let args: Vec<String> = env::args().collect();
    let extra_args: Vec<String> = args.iter().skip(3).cloned().collect();
    let mut make_args = vec!["menuconfig".to_string()];
    make_args.extend(extra_args);
    run_make(&target, &make_args)?;
    Ok(())
}

pub fn target_download() -> Result<(), Box<dyn std::error::Error>> {
    let target = get_current_target()?;
    let args: Vec<String> = env::args().collect();
    let extra_args: Vec<String> = args.iter().skip(3).cloned().collect();
    let mut make_args = vec!["download".to_string()];
    make_args.extend(extra_args);
    run_make(&target, &make_args)?;
    Ok(())
}

pub fn target_clean() -> Result<(), Box<dyn std::error::Error>> {
    let target = get_current_target()?;
    let args: Vec<String> = env::args().collect();
    let extra_args: Vec<String> = args.iter().skip(3).cloned().collect();
    let mut make_args = vec!["clean".to_string()];
    make_args.extend(extra_args);
    run_make(&target, &make_args)?;
    Ok(())
}

pub fn target_distclean() -> Result<(), Box<dyn std::error::Error>> {
    let target = get_current_target()?;
    let args: Vec<String> = env::args().collect();
    let extra_args: Vec<String> = args.iter().skip(3).cloned().collect();
    let mut make_args = vec!["distclean".to_string()];
    make_args.extend(extra_args);
    run_make(&target, &make_args)?;
    Ok(())
}

pub fn target_feed() -> Result<(), Box<dyn std::error::Error>> {
    crate::build::target_feed()
}

pub fn download_source(target: &str, config: &SourceConfig) -> Result<(), Box<dyn std::error::Error>> {
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

    if let Some(parent) = src_dir.parent() {
        if !parent.exists() {
            fs::create_dir_all(parent)?;
        }
    }

    println!(
        "{}",
        format!("正在浅克隆 {} (分支/标签: {}) 到 {}...", config.url, config.revision, src_dir.display()).cyan()
    );
    let status = process::Command::new("git")
        .arg("clone")
        .arg("--depth")
        .arg("1")
        .arg("--branch")
        .arg(&config.revision)
        .arg(&config.url)
        .arg(&src_dir)
        .status()?;
    if !status.success() {
        return Err(format!("git clone --branch {} 失败", config.revision).into());
    }

    println!("{}", "源码下载完成。".green());
    Ok(())
}

pub fn config_sync() -> Result<(), Box<dyn std::error::Error>> {
    let target = get_current_target()?;
    println!("{}", format!("同步目标 {} 的配置...", target).cyan());
    sync_package_config(&target)?;
    Ok(())
}
