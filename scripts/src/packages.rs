use colored::*;
use dialoguer::{Confirm, theme::ColorfulTheme};
use std::fs;
use std::fs::File;
use std::io::{BufRead, BufReader};
use std::path::{Path, PathBuf};
use std::process;
use walkdir::WalkDir;

use crate::app::{CONFIG_FILE, FEED_CONFIG_FILE, PACKAGES_DIR};
use crate::config::get_current_target;

#[derive(Clone, Debug)]
pub struct FeedEntry {
    pub feed_type: String,
    pub feed_name: String,
    pub base_url: String,
    pub revision: Option<String>,
}

pub fn parse_requested_packages(args: &[String]) -> Vec<String> {
    let mut result = Vec::new();
    for arg in args {
        for part in arg.split(';') {
            let item = part.trim();
            if !item.is_empty() {
                result.push(item.to_string());
            }
        }
    }
    result
}

pub fn parse_feed_entries() -> Result<Vec<FeedEntry>, Box<dyn std::error::Error>> {
    let feed_config_path = Path::new(PACKAGES_DIR).join(FEED_CONFIG_FILE);
    if !feed_config_path.exists() {
        return Err(format!("未找到 {}，请先创建 feeds 配置。", feed_config_path.display()).into());
    }

    let file = File::open(&feed_config_path)?;
    let reader = BufReader::new(file);
    let mut entries = Vec::new();

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

        let feed_type = parts[0].to_string();
        let feed_name = parts[1].to_string();
        let url_and_rev = parts[2];

        let (base_url, revision) = if let Some(semi_pos) = url_and_rev.find(';') {
            let (url, rev) = url_and_rev.split_at(semi_pos);
            let rev = rev.trim_start_matches(';');
            if rev.is_empty() {
                (url.to_string(), None)
            } else {
                (url.to_string(), Some(rev.to_string()))
            }
        } else {
            (url_and_rev.to_string(), None)
        };

        entries.push(FeedEntry {
            feed_type,
            feed_name,
            base_url,
            revision,
        });
    }

    Ok(entries)
}

fn git_remote_url(repo_dir: &Path) -> Result<Option<String>, Box<dyn std::error::Error>> {
    let output = process::Command::new("git")
        .arg("-C")
        .arg(repo_dir)
        .arg("remote")
        .arg("get-url")
        .arg("origin")
        .output()?;

    if !output.status.success() {
        return Ok(None);
    }

    let url = String::from_utf8_lossy(&output.stdout).trim().to_string();
    if url.is_empty() {
        return Ok(None);
    }

    Ok(Some(url))
}

fn ensure_git_remote_matches(repo_dir: &Path, expected_url: &str) -> Result<bool, Box<dyn std::error::Error>> {
    let current = git_remote_url(repo_dir)?;
    if let Some(current_url) = current {
        if current_url == expected_url {
            return Ok(false);
        }
        println!(
            "{}",
            format!(
                "Feed '{}' 的远程地址不匹配，正在切换到 feeds.config 定义的地址: {}",
                repo_dir.display(),
                expected_url
            )
            .yellow()
        );
        let status = process::Command::new("git")
            .arg("-C")
            .arg(repo_dir)
            .arg("remote")
            .arg("set-url")
            .arg("origin")
            .arg(expected_url)
            .status()?;
        if !status.success() {
            return Err(format!("更新 feed 远程地址失败: {}", repo_dir.display()).into());
        }
        return Ok(true);
    }

    let status = process::Command::new("git")
        .arg("-C")
        .arg(repo_dir)
        .arg("remote")
        .arg("add")
        .arg("origin")
        .arg(expected_url)
        .status()?;
    if !status.success() {
        return Err(format!("添加 feed 远程地址失败: {}", repo_dir.display()).into());
    }
    Ok(true)
}

fn detect_remote_branch(repo_dir: &Path, revision: Option<&str>) -> Result<String, Box<dyn std::error::Error>> {
    if let Some(rev) = revision {
        return Ok(rev.to_string());
    }

    let symbolic = process::Command::new("git")
        .arg("-C")
        .arg(repo_dir)
        .arg("symbolic-ref")
        .arg("--short")
        .arg("refs/remotes/origin/HEAD")
        .output()?;
    if symbolic.status.success() {
        let value = String::from_utf8_lossy(&symbolic.stdout).trim().to_string();
        if !value.is_empty() {
            let branch = value.strip_prefix("origin/").unwrap_or(&value);
            if !branch.is_empty() {
                return Ok(branch.to_string());
            }
        }
    }

    let show = process::Command::new("git")
        .arg("-C")
        .arg(repo_dir)
        .arg("remote")
        .arg("show")
        .arg("origin")
        .output()?;
    if show.status.success() {
        let text = String::from_utf8_lossy(&show.stdout);
        for line in text.lines() {
            let trimmed = line.trim();
            if trimmed.starts_with("HEAD branch:") {
                let branch = trimmed.trim_start_matches("HEAD branch:").trim();
                if !branch.is_empty() {
                    return Ok(branch.to_string());
                }
            }
        }
    }

    let branch_output = process::Command::new("git")
        .arg("-C")
        .arg(repo_dir)
        .arg("for-each-ref")
        .arg("--format=%(refname:short)")
        .arg("refs/remotes/origin")
        .output()?;
    if branch_output.status.success() {
        let text = String::from_utf8_lossy(&branch_output.stdout);
        for line in text.lines() {
            let trimmed = line.trim();
            if trimmed == "origin/HEAD" {
                continue;
            }
            if let Some(branch) = trimmed.strip_prefix("origin/") {
                if !branch.is_empty() {
                    return Ok(branch.to_string());
                }
            }
        }
    }

    Ok("main".to_string())
}

fn refresh_git_feed(repo_dir: &Path, expected_url: &str, revision: Option<&str>) -> Result<(), Box<dyn std::error::Error>> {
    let branch = detect_remote_branch(repo_dir, revision)?;

    let fetch_status = process::Command::new("git")
        .arg("-C")
        .arg(repo_dir)
        .arg("fetch")
        .arg("origin")
        .arg("--prune")
        .status()?;
    if !fetch_status.success() {
        return Err(format!("git fetch origin 失败: {}", repo_dir.display()).into());
    }

    let reset_target = format!("origin/{}", branch);
    let reset_status = process::Command::new("git")
        .arg("-C")
        .arg(repo_dir)
        .arg("reset")
        .arg("--hard")
        .arg(&reset_target)
        .status()?;

    if !reset_status.success() {
        println!(
            "{}",
            format!(
                "git reset --hard {} 失败，尝试删除目录并按 feeds.config 重新拉取: {}",
                reset_target,
                repo_dir.display()
            )
            .yellow()
        );
        let _ = fs::remove_dir_all(repo_dir);

        let mut clone_cmd = process::Command::new("git");
        clone_cmd.arg("clone").arg("--depth").arg("1");
        if let Some(rev) = revision {
            clone_cmd.arg("--branch").arg(rev);
        }
        clone_cmd.arg(expected_url).arg(repo_dir);
        let clone_status = clone_cmd.status()?;
        if !clone_status.success() {
            return Err(format!("重新拉取 feed 失败: {}", repo_dir.display()).into());
        }
        return Ok(());
    }

    Ok(())
}

pub fn package_feed() -> Result<(), Box<dyn std::error::Error>> {
    let entries = parse_feed_entries()?;
    let args: Vec<String> = std::env::args().collect();
    let selected = parse_requested_packages(&args[3..]);
    let filtered: Vec<_> = if selected.is_empty() {
        entries
    } else {
        entries
            .into_iter()
            .filter(|entry| selected.iter().any(|name| name == &entry.feed_name))
            .collect()
    };

    for entry in filtered {
        let feed_type = entry.feed_type.as_str();
        let feed_name = entry.feed_name.as_str();
        let base_url = entry.base_url.as_str();
        let revision = entry.revision.as_deref();
        let feed_dir = Path::new(PACKAGES_DIR).join(feed_name);

        if feed_dir.exists() {
            let remote_url = git_remote_url(&feed_dir)?;
            if let Some(current_url) = remote_url {
                if current_url != base_url {
                    println!(
                        "{}",
                        format!(
                            "Feed '{}' 远程地址与 feeds.config 不一致，按配置地址重新拉取: {}",
                            feed_name, base_url
                        )
                        .yellow()
                    );
                    let _ = fs::remove_dir_all(&feed_dir);
                } else {
                    let confirm = Confirm::with_theme(&ColorfulTheme::default())
                        .with_prompt(format!("Feed 目录 '{}' 已存在，是否删除并重新下载？", feed_dir.display()))
                        .interact()?;
                    if confirm {
                        fs::remove_dir_all(&feed_dir)?;
                    } else {
                        println!("{}", format!("跳过 feed: {}", feed_name).yellow());
                        continue;
                    }
                }
            } else {
                let confirm = Confirm::with_theme(&ColorfulTheme::default())
                    .with_prompt(format!("Feed 目录 '{}' 已存在，是否删除并重新下载？", feed_dir.display()))
                    .interact()?;
                if confirm {
                    fs::remove_dir_all(&feed_dir)?;
                } else {
                    println!("{}", format!("跳过 feed: {}", feed_name).yellow());
                    continue;
                }
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

pub fn package_update() -> Result<(), Box<dyn std::error::Error>> {
    let entries = parse_feed_entries()?;
    let args: Vec<String> = std::env::args().collect();
    let selected = parse_requested_packages(&args[3..]);
    let filtered: Vec<_> = if selected.is_empty() {
        entries
    } else {
        entries
            .into_iter()
            .filter(|entry| selected.iter().any(|name| name == &entry.feed_name))
            .collect()
    };

    for entry in filtered {
        let feed_type = entry.feed_type.as_str();
        let feed_name = entry.feed_name.as_str();
        let base_url = entry.base_url.as_str();
        let revision = entry.revision.as_deref();
        let feed_dir = Path::new(PACKAGES_DIR).join(feed_name);

        if !feed_dir.exists() {
            eprintln!(
                "{}",
                format!("警告: Feed 目录 '{}' 不存在，跳过更新 (请先运行 owbm package feed)", feed_dir.display()).yellow()
            );
            continue;
        }

        println!("{}", format!("正在更新 feed: {}", feed_name).cyan());

        let status = match feed_type {
            "src-git" => {
                let _ = ensure_git_remote_matches(&feed_dir, base_url)?;
                refresh_git_feed(&feed_dir, base_url, revision)?;
                process::Command::new("git")
                    .arg("-C")
                    .arg(&feed_dir)
                    .arg("status")
                    .status()?
            }
            "src-svn" => process::Command::new("svn").arg("update").arg(&feed_dir).status()?,
            _ => {
                eprintln!("{}", format!("不支持 feed 类型: {}", feed_type).yellow());
                continue;
            }
        };

        if !status.success() {
            eprintln!("{}", format!("更新 feed {} 失败", feed_name).red());
        } else {
            println!("{}", format!("更新 feed {} 完成", feed_name).green());
        }
    }

    Ok(())
}

pub fn package_install() -> Result<(), Box<dyn std::error::Error>> {
    let target = get_current_target()?;
    let target_src_dir = Path::new(crate::app::SRCS_DIR).join(&target);
    if !target_src_dir.exists() {
        return Err(format!(
            "目标源码目录 '{}' 不存在，请先运行 owbm target init",
            target_src_dir.display()
        )
        .into());
    }

    let custom_dir = target_src_dir.join("package").join("custom");
    fs::create_dir_all(&custom_dir)?;

    let args: Vec<String> = std::env::args().collect();
    let requested = parse_requested_packages(&args[3..]);

    let config_path = std::env::current_dir()?.join(CONFIG_FILE);
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

    if !requested.is_empty() {
        selected_packages.retain(|pkg| {
            requested.iter().any(|name| {
                pkg == name
                    || pkg.ends_with(&format!("/{}", name))
                    || name.ends_with(&format!("/{}", pkg))
                    || Path::new(pkg)
                        .file_name()
                        .and_then(|s| s.to_str())
                        .map(|base| base == name)
                        .unwrap_or(false)
            })
        });
    }

    if selected_packages.is_empty() {
        println!(
            "{}",
            ".config 中没有 CONFIG_PACKAGE_xxx=y 条目，或指定的软件包未匹配到配置。".yellow()
        );
        return Ok(());
    }

    println!(
        "{}",
        format!("找到 {} 个软件包需要安装。", selected_packages.len()).cyan()
    );

    for pkg in &selected_packages {
        let found = find_package_dir(pkg)?;
        if let Some(src_path) = found {
            let dest_name = Path::new(pkg)
                .file_name()
                .and_then(|s| s.to_str())
                .unwrap_or(pkg);
            let dest_path = custom_dir.join(dest_name);

            if dest_path.exists() {
                let confirm = Confirm::with_theme(&ColorfulTheme::default())
                    .with_prompt(format!("包 '{}' 已存在，是否覆盖？", dest_name))
                    .interact()?;
                if !confirm {
                    println!("{}", format!("跳过包: {}", dest_name).yellow());
                    continue;
                }
                fs::remove_dir_all(&dest_path)?;
            }

            copy_dir(&src_path, &dest_path)?;
            println!("{}", format!("已安装包: {}", dest_name).green());
        } else {
            println!(
                "{}",
                format!("警告: 未找到软件包 '{}'，请先运行 owbm package feed 下载。", pkg).yellow()
            );
        }
    }

    Ok(())
}

pub fn find_package_dir(package_name: &str) -> Result<Option<PathBuf>, Box<dyn std::error::Error>> {
    let packages_dir = Path::new(PACKAGES_DIR);
    if !packages_dir.exists() {
        return Ok(None);
    }

    if package_name.starts_with("package/") {
        let rel = package_name.trim_start_matches("package/");
        let candidate = packages_dir.join(rel);
        if candidate.exists() && candidate.is_dir() {
            return Ok(Some(candidate));
        }
        return Ok(None);
    }

    if package_name.contains('/') {
        let candidate = packages_dir.join(package_name);
        if candidate.exists() && candidate.is_dir() {
            return Ok(Some(candidate));
        }
        return Ok(None);
    }

    let direct = packages_dir.join(package_name);
    if direct.exists() && direct.is_dir() {
        return Ok(Some(direct));
    }

    let mut matches: Vec<(usize, usize, PathBuf)> = Vec::new();
    for entry in WalkDir::new(packages_dir)
        .min_depth(1)
        .max_depth(20)
        .into_iter()
        .filter_map(|e| e.ok())
        .filter(|e| e.file_type().is_dir())
    {
        if entry.file_name() == package_name {
            let path = entry.path().to_path_buf();
            if let Ok(rel) = path.strip_prefix(packages_dir) {
                let mut comp_count = 0usize;
                for _ in rel.components() {
                    comp_count += 1;
                }
                matches.push((comp_count, entry.depth(), path));
            }
        }
    }

    if matches.is_empty() {
        return Ok(None);
    }

    matches.sort_by(|a, b| a.0.cmp(&b.0).then(a.1.cmp(&b.1)));
    Ok(Some(matches[0].2.clone()))
}

pub fn copy_dir(src: &Path, dst: &Path) -> Result<(), Box<dyn std::error::Error>> {
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
