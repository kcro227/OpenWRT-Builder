use anyhow::{Context, Result};
use colored::*;
use dialoguer::{Confirm, Select, theme::ColorfulTheme};
use serde::{Deserialize, Serialize};
use std::env;
use std::fs;
use std::io::Write;
use std::path::Path;
use std::process;

use crate::app::{CONFIG_FILE, CONFIG_SRC_KEY, CONFIG_TARGET_KEY, SourceConfig, SRCS_DIR, TARGETS_DIR};
use crate::build::run_make;
use crate::config::{ensure_dir_exists, get_current_target, read_targets, sync_package_config, update_config};

#[derive(Debug, Serialize, Deserialize)]
struct ExportManifest {
    version: u32,
    package_config: String,
    targets: Vec<String>,
}

fn copy_dir_all(src: &Path, dst: &Path) -> Result<()> {
    if !src.exists() {
        anyhow::bail!("模板目录 '{}' 不存在", src.display());
    }
    fs::create_dir_all(dst).context("创建目标目录失败")?;

    for entry in fs::read_dir(src).context("读取模板目录失败")? {
        let entry = entry.context("读取模板目录项失败")?;
        let src_path = entry.path();
        let dst_path = dst.join(entry.file_name());
        let file_type = entry.file_type().context("读取目录项类型失败")?;

        if file_type.is_dir() {
            copy_dir_all(&src_path, &dst_path)?;
        } else {
            fs::copy(&src_path, &dst_path).with_context(|| {
                format!("复制 '{}' 到 '{}' 失败", src_path.display(), dst_path.display())
            })?;
        }
    }

    Ok(())
}

fn remove_config_key(key: &str) -> Result<()> {
    let config_path = env::current_dir().context("无法获取当前工作目录")?.join(CONFIG_FILE);
    if !config_path.exists() {
        return Ok(());
    }

    let content = fs::read_to_string(&config_path).context("读取 .config 失败")?;
    let lines: Vec<String> = content.lines().map(String::from).collect();
    let filtered: Vec<String> = lines
        .into_iter()
        .filter(|line| !(line.starts_with(key) && line.contains('=')))
        .collect();

    let mut file = fs::File::create(config_path).context("写入 .config 失败")?;
    for line in filtered {
        writeln!(file, "{}", line).context("写入 .config 失败")?;
    }

    Ok(())
}

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

pub fn target_add(name: &str) -> Result<()> {
    let target_name = name.trim();
    if target_name.is_empty() {
        anyhow::bail!("目标名称不能为空");
    }

    let target_dir = Path::new(TARGETS_DIR).join(target_name);
    if target_dir.exists() {
        anyhow::bail!("目标 '{}' 已存在", target_name);
    }

    let template_dir = Path::new(TARGETS_DIR).join("default");
    if template_dir.exists() {
        copy_dir_all(&template_dir, &target_dir).with_context(|| {
            format!("从模板目录 '{}' 复制到新目标 '{}' 失败", template_dir.display(), target_dir.display())
        })?;
    } else {
        fs::create_dir_all(target_dir.join("custom")).context("创建目标自定义脚本目录失败")?;
        fs::create_dir_all(target_dir.join("resource")).context("创建目标 resource 目录失败")?;
        fs::create_dir_all(target_dir.join("resources")).context("创建目标 resources 目录失败")?;

        let template = SourceConfig {
            url: "https://github.com/example/repo.git".to_string(),
            revision: "main".to_string(),
        };
        let template_content = serde_json::to_string_pretty(&template).context("序列化 target template 失败")?;
        fs::write(target_dir.join("source.json"), template_content).context("写入 source.json 失败")?;

        let package_template = "# 按需添加包名，一行一个\n# 例如：\n# qmodem\n# openclash\n";
        fs::write(target_dir.join("packagelist.txt"), package_template).context("写入 packagelist.txt 失败")?;
    }

    println!("{}", format!("已创建新目标: {}", target_name).green());
    println!("{}", format!("模板来源: {}", template_dir.display()).cyan());
    println!("{}", format!("请编辑 {} 里的 source.json 和 packagelist.txt", target_dir.display()).cyan());
    Ok(())
}

pub fn target_remove(name: &str) -> Result<()> {
    let target_name = name.trim();
    if target_name.is_empty() {
        anyhow::bail!("目标名称不能为空");
    }
    if target_name == "default" {
        anyhow::bail!("不能删除模板目标 'default'");
    }

    let target_dir = Path::new(TARGETS_DIR).join(target_name);
    if !target_dir.exists() {
        anyhow::bail!("目标 '{}' 不存在", target_name);
    }

    println!("{}", format!("正在删除目标 '{}' ...", target_name).yellow());
    fs::remove_dir_all(&target_dir).with_context(|| format!("删除目标目录 '{}' 失败", target_dir.display()))?;

    let current_target = crate::config::read_current_target(&env::current_dir().context("无法获取当前工作目录")?.join(CONFIG_FILE))?;
    if current_target.as_deref() == Some(target_name) {
        remove_config_key(CONFIG_TARGET_KEY)?;
        println!("{}", "当前目标已从 .config 中移除。".yellow());
    }

    let src_dir = Path::new(SRCS_DIR).join(target_name);
    if src_dir.exists() {
        fs::remove_dir_all(&src_dir).with_context(|| format!("删除源码目录 '{}' 失败", src_dir.display()))?;
    }

    println!("{}", format!("已删除目标: {}", target_name).green());
    Ok(())
}

pub fn export_targets(output: &str) -> Result<()> {
    let export_root = Path::new(output);
    if export_root.exists() && export_root.is_file() {
        anyhow::bail!("导出路径 '{}' 不能是文件", export_root.display());
    }
    if export_root.exists() {
        fs::remove_dir_all(export_root).context("清理已有导出目录失败")?;
    }
    fs::create_dir_all(export_root).context("创建导出目录失败")?;

    let package_src = Path::new("packages").join("feeds.config");
    if !package_src.exists() {
        anyhow::bail!("未找到 '{}'，无法导出包源配置", package_src.display());
    }

    let target_root = Path::new(TARGETS_DIR);
    let mut target_names = Vec::new();
    if target_root.exists() {
        for entry in fs::read_dir(target_root).context("读取目标目录失败")? {
            let entry = entry.context("读取目标目录项失败")?;
            let file_type = entry.file_type().context("读取目标目录项类型失败")?;
            if file_type.is_dir() {
                if let Some(name) = entry.file_name().to_str() {
                    if name != "default" {
                        target_names.push(name.to_string());
                    }
                }
            }
        }
    }

    let packages_dir = export_root.join("packages");
    fs::create_dir_all(&packages_dir).context("创建 packages 导出目录失败")?;
    fs::copy(&package_src, packages_dir.join("feeds.config")).with_context(|| {
        format!("复制 '{}' 到 '{}' 失败", package_src.display(), packages_dir.join("feeds.config").display())
    })?;

    let export_targets_dir = export_root.join("targets");
    fs::create_dir_all(&export_targets_dir).context("创建 targets 导出目录失败")?;
    for name in &target_names {
        let src_dir = target_root.join(name);
        let dst_dir = export_targets_dir.join(name);
        copy_dir_all(&src_dir, &dst_dir).with_context(|| {
            format!("导出目标 '{}' 失败", name)
        })?;
    }

    let manifest = ExportManifest {
        version: 1,
        package_config: "packages/feeds.config".to_string(),
        targets: target_names,
    };
    let manifest_path = export_root.join("manifest.json");
    let manifest_content = serde_json::to_string_pretty(&manifest).context("序列化导出清单失败")?;
    fs::write(&manifest_path, manifest_content).context("写入导出清单失败")?;

    println!("{}", format!("已导出自定义配置到 {}", export_root.display()).green());
    Ok(())
}

pub fn import_targets(input: &str) -> Result<()> {
    let import_root = Path::new(input);
    if !import_root.exists() {
        anyhow::bail!("导入目录 '{}' 不存在", import_root.display());
    }
    let manifest_path = import_root.join("manifest.json");
    if !manifest_path.exists() {
        anyhow::bail!("导入目录 '{}' 中没有 manifest.json，无法恢复配置", import_root.display());
    }

    let manifest: ExportManifest = serde_json::from_str(&fs::read_to_string(&manifest_path).context("读取导出清单失败")?)
        .context("解析导出清单失败")?;

    let package_src = import_root.join(&manifest.package_config);
    if !package_src.exists() {
        anyhow::bail!("导入目录中缺少包源配置文件 '{}'", package_src.display());
    }
    let package_dst = Path::new("packages").join("feeds.config");
    if let Some(parent) = package_dst.parent() {
        fs::create_dir_all(parent).context("创建 packages 目录失败")?;
    }
    fs::copy(&package_src, &package_dst).with_context(|| {
        format!("复制 '{}' 到 '{}' 失败", package_src.display(), package_dst.display())
    })?;

    let target_root = Path::new(TARGETS_DIR);
    let import_targets_dir = import_root.join("targets");
    if import_targets_dir.exists() {
        for target_name in &manifest.targets {
            let src_dir = import_targets_dir.join(target_name);
            let dst_dir = target_root.join(target_name);
            if dst_dir.exists() {
                println!("{}", format!("目标 '{}' 已存在，覆盖旧副本。", target_name).yellow());
                fs::remove_dir_all(&dst_dir).with_context(|| format!("删除旧目标 '{}' 失败", dst_dir.display()))?;
            }
            copy_dir_all(&src_dir, &dst_dir).with_context(|| {
                format!("导入目标 '{}' 失败", target_name)
            })?;
        }
    }

    println!("{}", format!("已从 {} 导入自定义配置。", import_root.display()).green());
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
