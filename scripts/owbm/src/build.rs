use anyhow::{Context, Result};
use colored::*;
use std::env;
use std::fs;
use std::path::Path;
use std::process;
use std::thread;
use std::time::Duration;

use nix::sys::signal::{kill, Signal};
use nix::unistd::Pid;

use crate::app::{INTERRUPTED, SRCS_DIR};
use crate::config::get_current_target;

pub fn run_make(target: &str, make_args: &[String]) -> Result<()> {
    let src_dir = Path::new(SRCS_DIR).join(target);
    if !src_dir.exists() {
        anyhow::bail!("源码目录 '{}' 不存在，请先运行 owbm target init", src_dir.display());
    }

    let mut cmd = process::Command::new("make");
    cmd.arg("-C").arg(&src_dir);
    cmd.args(make_args);

    println!("{}", format!("执行命令: {:?}", cmd).cyan());

    let mut child = cmd.spawn().context("启动 make 子进程失败")?;
    let pid = child.id() as i32;

    loop {
        match child.try_wait() {
            Ok(Some(status)) => {
                if !status.success() {
                    anyhow::bail!("make 命令执行失败");
                }
                return Ok(());
            }
            Ok(None) => {
                if INTERRUPTED.load(std::sync::atomic::Ordering::SeqCst) {
                    println!("{}", "收到中断信号，正在终止 make...".yellow());
                    kill(Pid::from_raw(pid), Signal::SIGINT).context("发送 SIGINT 给 make 失败")?;
                    let _ = child.wait().context("等待 make 子进程退出失败")?;
                    anyhow::bail!("make 命令被中断");
                }
                thread::sleep(Duration::from_millis(100));
            }
            Err(e) => {
                anyhow::bail!("等待子进程失败: {}", e);
            }
        }
    }
}

pub fn target_feed() -> Result<()> {
    let target = get_current_target()?;
    let src_dir = Path::new(SRCS_DIR).join(&target);
    if !src_dir.exists() {
        anyhow::bail!("源码目录 '{}' 不存在，请先运行 owbm target init", src_dir.display());
    }
    let scripts_dir = src_dir.join("scripts");
    if !scripts_dir.exists() {
        anyhow::bail!("scripts 目录不存在，可能不是 OpenWrt 源码？");
    }

    println!("{}", "正在更新 feeds...".cyan());
    let status = process::Command::new("./scripts/feeds")
        .arg("update")
        .current_dir(&src_dir)
        .status()
        .context("执行 feeds update 失败")?;
    if !status.success() {
        anyhow::bail!("feeds update 失败");
    }

    println!("{}", "正在安装 feeds...".cyan());
    let status = process::Command::new("./scripts/feeds")
        .arg("install")
        .arg("-a")
        .current_dir(&src_dir)
        .status()
        .context("执行 feeds install 失败")?;
    if !status.success() {
        anyhow::bail!("feeds install 失败");
    }

    println!("{}", "feeds 更新完成。".green());
    Ok(())
}

pub fn run_custom_script(name: &str, extra_args: &[String]) -> Result<()> {
    let target = get_current_target()?;
    let cus_dir = Path::new(crate::app::TARGETS_DIR).join(&target).join("custom");
    if !cus_dir.exists() {
        anyhow::bail!("自定义脚本目录不存在: {}", cus_dir.display());
    }

    let entries = fs::read_dir(&cus_dir).context("读取自定义脚本目录失败")?;
    let mut matches = Vec::new();
    for entry in entries {
        let entry = entry.context("遍历自定义脚本目录失败")?;
        let file_name = entry.file_name();
        let file_name_str = file_name.to_string_lossy();
        if let Some(underscore_pos) = file_name_str.find('_') {
            let (_, rest) = file_name_str.split_at(underscore_pos + 1);
            if let Some(dot_pos) = rest.find('.') {
                let base_name = &rest[..dot_pos];
                if base_name == name {
                    matches.push((file_name_str.to_string(), entry.path()));
                }
            } else if rest == name {
                matches.push((file_name_str.to_string(), entry.path()));
            }
        }
    }

    if matches.is_empty() {
        anyhow::bail!("未找到脚本 '{}' 在目录 {}", name, cus_dir.display());
    }

    if matches.len() > 1 {
        println!("{}", format!("找到多个匹配脚本，将使用第一个: {}", matches[0].0).yellow());
    }

    let (script_name, script_path) = &matches[0];
    let interpreter = script_name.split('_').next().unwrap_or("bash");
    println!("{}", format!("执行自定义脚本: {} (解释器: {})", script_name, interpreter).cyan());

    let mut cmd = process::Command::new(interpreter);
    cmd.arg(script_path);
    cmd.args(extra_args);
    let status = cmd.status().context("执行脚本失败")?;
    if !status.success() {
        anyhow::bail!("脚本 '{}' 执行失败", script_name);
    }
    Ok(())
}

pub fn run_command(cmd: &str) -> Result<()> {
    let target = get_current_target()?;
    let src_dir = Path::new(SRCS_DIR).join(&target);
    if !src_dir.exists() {
        anyhow::bail!("源码目录 '{}' 不存在，请先运行 owbm target init", src_dir.display());
    }

    println!("{}", format!("在源码目录中执行: {}", cmd).cyan());
    let status = process::Command::new("sh")
        .arg("-c")
        .arg(cmd)
        .current_dir(&src_dir)
        .status()
        .context("执行自定义命令失败")?;
    if !status.success() {
        anyhow::bail!("命令 '{}' 执行失败", cmd);
    }
    Ok(())
}

pub fn build() -> Result<()> {
    let target = get_current_target()?;
    let args: Vec<String> = env::args().collect();
    let extra_args: Vec<String> = args.iter().skip(2).cloned().collect();
    run_make(&target, &extra_args)?;
    Ok(())
}
