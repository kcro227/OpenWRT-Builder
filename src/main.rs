use std::env;
use std::fs;
use std::path::Path;
use std::process;

fn main() {
    // 解析命令行参数：第一个参数为 targets 目录路径，默认为 "./targets"
    let args: Vec<String> = env::args().collect();
    let targets_path = if args.len() > 1 {
        args[1].clone()
    } else {
        "./targets".to_string()
    };

    // 执行列出目标的操作
    if let Err(err) = list_targets(&targets_path) {
        eprintln!("错误: {}", err);
        process::exit(1);
    }
}

/// 列出指定路径下的所有一级子目录（目标名）
fn list_targets<P: AsRef<Path>>(path: P) -> Result<(), Box<dyn std::error::Error>> {
    let path = path.as_ref();

    // 检查目录是否存在
    if !path.exists() {
        return Err(format!("目录 '{}' 不存在", path.display()).into());
    }
    if !path.is_dir() {
        return Err(format!("'{}' 不是一个目录", path.display()).into());
    }

    // 读取目录内容
    let entries = fs::read_dir(path)?;

    let mut targets = Vec::new();
    for entry in entries {
        let entry = entry?;
        let file_type = entry.file_type()?;

        // 只处理目录，忽略文件和其他类型
        if file_type.is_dir() {
            if let Some(name) = entry.file_name().to_str() {
                targets.push(name.to_string());
            } else {
                // 处理非 UTF-8 文件名（不太可能，但以防万一）
                eprintln!("警告: 忽略非 UTF-8 目录名: {:?}", entry.file_name());
            }
        }
    }

    // 按字母顺序排序，使输出更友好
    targets.sort();

    if targets.is_empty() {
        println!("没有找到任何目标。");
    } else {
        println!("可用的编译目标:");
        for target in targets {
            println!("  {}", target);
        }
    }

    Ok(())
}