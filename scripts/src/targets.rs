use anyhow::{Context, Result};
use colored::*;
use dialoguer::{Confirm, Select, theme::ColorfulTheme};
use std::env;
use std::fs;
use std::path::Path;
use std::process;

use crate::app::{CONFIG_SRC_KEY, SourceConfig, SRCS_DIR, TARGETS_DIR};
use crate::build::run_make;
use crate::config::{ensure_dir_exists, get_current_target, read_targets, sync_package_config, update_config};

pub fn list_targets<P: AsRef<Path>>(path: P) -> Result<()> {
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

pub fn target_init() -> Result<()> {
    let target = get_current_target()?;
    println!("{}", format!("当前目标: {}", target).cyan());

    let target_dir = Path::new(TARGETS_DIR).join(&target);
    if !target_dir.exists() {
        anyhow::bail!("目标目录 '{}' 不存在", target_dir.display());
    }

    let source_json_path = target_dir.join("source.json");
    let source_config: SourceConfig = if source_json_path.exists() {
        let content = fs::read_to_string(&source_json_path).context("读取 source.json 失败")?;
        serde_json::from_str(&content).context("解析 source.json 失败")?
    } else {
        println!("{}", "source.json 不存在，正在创建模板...".yellow());
        let template = SourceConfig {
            url: "https://github.com/example/repo.git".to_string(),
            revision: "main".to_string(),
        };
        let template_content = serde_json::to_string_pretty(&template).context("序列化 source.json 模板失败")?;
        fs::write(&source_json_path, &template_content).context("写入 source.json 失败")?;
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

pub fn target_update() -> Result<()> {
    let target = get_current_target()?;
    println!("{}", format!("当前目标: {}", target).cyan());

    let src_dir = Path::new(SRCS_DIR).join(&target);
    if !src_dir.exists() {
        anyhow::bail!("源码目录 '{}' 不存在，请先运行 owbm target init", src_dir.display());
    }

    println!("{}", format!("正在更新 {} 的源码...", target).cyan());

    let output = process::Command::new("git")
        .arg("-C")
        .arg(&src_dir)
        .arg("rev-parse")
        .arg("--abbrev-ref")
        .arg("HEAD")
        .output()
        .context("获取 git 当前分支名失败")?;
    if !output.status.success() {
        anyhow::bail!("无法获取当前分支名: git rev-parse 返回非零状态");
    }
    let current_branch = String::from_utf8_lossy(&output.stdout).trim().to_string();

    let status = process::Command::new("git")
        .arg("-C")
        .arg(&src_dir)
        .arg("pull")
        .arg("--ff-only")
        .status()
        .context("执行 git pull 失败")?;

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
        .interact()
        .context("交互式选择失败")?;

    match selection {
        0 => {
            println!("{}", "正在储藏本地更改...".cyan());
            let stash_status = process::Command::new("git")
                .arg("-C")
                .arg(&src_dir)
                .arg("stash")
                .status()
                .context("git stash 执行失败")?;
            if !stash_status.success() {
                anyhow::bail!("git stash 失败");
            }

            println!("{}", "正在重新拉取...".cyan());
            let pull_status = process::Command::new("git")
                .arg("-C")
                .arg(&src_dir)
                .arg("pull")
                .arg("--ff-only")
                .status()
                .context("git pull 执行失败")?;
            if !pull_status.success() {
                anyhow::bail!("储藏后 git pull 仍然失败");
            }

            let pop_stash = Confirm::with_theme(&ColorfulTheme::default())
                .with_prompt("拉取成功。是否恢复之前储藏的本地更改？")
                .default(true)
                .interact()
                .context("交互式选择失败")?;
            if pop_stash {
                let pop_status = process::Command::new("git")
                    .arg("-C")
                    .arg(&src_dir)
                    .arg("stash")
                    .arg("pop")
                    .status()
                    .context("git stash pop 执行失败")?;
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
                .status()
                .context("git fetch origin 执行失败")?;
            if !fetch_status.success() {
                anyhow::bail!("git fetch origin 失败");
            }

            let reset_status = process::Command::new("git")
                .arg("-C")
                .arg(&src_dir)
                .arg("reset")
                .arg("--hard")
                .arg(format!("origin/{}", current_branch))
                .status()
                .context("git reset --hard 执行失败")?;
            if !reset_status.success() {
                anyhow::bail!("git reset --hard origin/{} 失败", current_branch);
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

pub fn target_config() -> Result<()> {
    let target = get_current_target()?;
    let args: Vec<String> = env::args().collect();
    let extra_args: Vec<String> = args.iter().skip(3).cloned().collect();
    let mut make_args = vec!["menuconfig".to_string()];
    make_args.extend(extra_args);
    run_make(&target, &make_args)?;
    Ok(())
}

pub fn target_download() -> Result<()> {
    let target = get_current_target()?;
    let args: Vec<String> = env::args().collect();
    let extra_args: Vec<String> = args.iter().skip(3).cloned().collect();
    let mut make_args = vec!["download".to_string()];
    make_args.extend(extra_args);
    run_make(&target, &make_args)?;
    Ok(())
}

pub fn target_clean() -> Result<()> {
    let target = get_current_target()?;
    let args: Vec<String> = env::args().collect();
    let extra_args: Vec<String> = args.iter().skip(3).cloned().collect();
    let mut make_args = vec!["clean".to_string()];
    make_args.extend(extra_args);
    run_make(&target, &make_args)?;
    Ok(())
}

pub fn target_distclean() -> Result<()> {
    let target = get_current_target()?;
    let args: Vec<String> = env::args().collect();
    let extra_args: Vec<String> = args.iter().skip(3).cloned().collect();
    let mut make_args = vec!["distclean".to_string()];
    make_args.extend(extra_args);
    run_make(&target, &make_args)?;
    Ok(())
}

pub fn target_feed() -> Result<()> {
    crate::build::target_feed()
}

pub fn download_source(target: &str, config: &SourceConfig) -> Result<()> {
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
        anyhow::bail!("git clone --branch {} 失败", config.revision);
    }

    println!("{}", "源码下载完成。".green());
    Ok(())
}

pub fn config_sync() -> Result<()> {
    let target = get_current_target()?;
    println!("{}", format!("同步目标 {} 的配置...", target).cyan());
    sync_package_config(&target)?;
    Ok(())
}
