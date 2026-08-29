use colored::*;
use dialoguer::{Select, theme::ColorfulTheme};
use std::collections::HashSet;
use std::env;
use std::fs::{self, File};
use std::io::{BufRead, BufReader, Write};
use std::path::Path;

use crate::app::{CONFIG_FILE, CONFIG_TARGET_KEY, TARGETS_DIR};

pub fn sync_package_config(target: &str) -> Result<usize, Box<dyn std::error::Error>> {
    let packagelist_path = Path::new(TARGETS_DIR).join(target).join("packagelist.txt");
    if !packagelist_path.exists() {
        println!("{}", format!("目标 '{}' 没有 packagelist.txt，跳过软件包同步。", target).yellow());
        return Ok(0);
    }

    let file = File::open(&packagelist_path)?;
    let reader = BufReader::new(file);
    let mut expected = HashSet::new();
    for line in reader.lines() {
        let line = line?;
        let line = line.trim();
        if line.is_empty() || line.starts_with('#') {
            continue;
        }
        expected.insert(line.to_string());
    }

    let config_path = env::current_dir()?.join(CONFIG_FILE);
    let mut lines = Vec::new();
    let mut current = HashSet::new();
    if config_path.exists() {
        let content = fs::read_to_string(&config_path)?;
        for line in content.lines() {
            let trimmed = line.trim();
            if trimmed.starts_with("CONFIG_PACKAGE_") && trimmed.ends_with("=y") {
                if let Some(pkg) = trimmed
                    .strip_prefix("CONFIG_PACKAGE_")
                    .and_then(|s| s.strip_suffix("=y"))
                {
                    current.insert(pkg.to_string());
                }
            }
            lines.push(line.to_string());
        }
    }

    let to_add: Vec<&String> = expected.difference(&current).collect();
    let to_remove: Vec<&String> = current.difference(&expected).collect();

    if !to_add.is_empty() {
        println!("{}", format!("添加软件包配置 ({}个):", to_add.len()).green());
        for pkg in &to_add {
            println!("  + {}", pkg);
        }
    }
    if !to_remove.is_empty() {
        println!("{}", format!("移除软件包配置 ({}个):", to_remove.len()).yellow());
        for pkg in &to_remove {
            println!("  - {}", pkg);
        }
    }
    if to_add.is_empty() && to_remove.is_empty() {
        println!("{}", "软件包配置无变化。".yellow());
        return Ok(0);
    }

    let mut new_lines = Vec::new();
    for line in lines {
        if line.starts_with("CONFIG_PACKAGE_") && line.ends_with("=y") {
            if let Some(pkg) = line
                .strip_prefix("CONFIG_PACKAGE_")
                .and_then(|s| s.strip_suffix("=y"))
            {
                if expected.contains(pkg) {
                    new_lines.push(line);
                }
            } else {
                new_lines.push(line);
            }
        } else {
            new_lines.push(line);
        }
    }

    for pkg in &to_add {
        new_lines.push(format!("CONFIG_PACKAGE_{}=y", pkg));
    }

    let mut file = File::create(config_path)?;
    for line in new_lines {
        writeln!(file, "{}", line)?;
    }

    Ok(to_add.len())
}

pub fn change_target<P: AsRef<Path>>(path: P) -> Result<(), Box<dyn std::error::Error>> {
    let path = path.as_ref();
    ensure_dir_exists(path)?;

    let targets = read_targets(path)?;
    if targets.is_empty() {
        return Err("没有可用的目标，无法选择。".into());
    }

    let current_dir = env::current_dir()?;
    let config_path = current_dir.join(CONFIG_FILE);
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

    sync_package_config(selected)?;
    Ok(())
}

pub fn get_current_target() -> Result<String, Box<dyn std::error::Error>> {
    let config_path = env::current_dir()?.join(CONFIG_FILE);
    if !config_path.exists() {
        return Err("没有找到 .config 文件，请先运行 owbm change 选择目标。".into());
    }
    let target = read_current_target(&config_path)?;
    target.ok_or_else(|| "当前 .config 中未设置 CONFIG_TARGET，请运行 owbm change 选择目标。".into())
}

pub fn read_current_target(config_path: &Path) -> Result<Option<String>, Box<dyn std::error::Error>> {
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

pub fn update_config(key: &str, value: &str) -> Result<(), Box<dyn std::error::Error>> {
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

pub fn ensure_dir_exists(path: &Path) -> Result<(), Box<dyn std::error::Error>> {
    if !path.exists() {
        return Err(format!("目录 '{}' 不存在", path.display()).into());
    }
    if !path.is_dir() {
        return Err(format!("'{}' 不是一个目录", path.display()).into());
    }
    Ok(())
}

pub fn read_targets(path: &Path) -> Result<Vec<String>, Box<dyn std::error::Error>> {
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
