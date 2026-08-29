use clap::{Args, Parser, Subcommand};
use colored::*;
use serde::{Deserialize, Serialize};
use std::process;
use anyhow::Result;

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

#[derive(Parser, Debug)]
#[command(name = "owbm", about = "OpenWrt Build Manager", version)]
struct Cli {
    #[command(subcommand)]
    command: Command,
}

#[derive(Subcommand, Debug)]
enum Command {
    List,
    #[command(alias = "change")]
    Select,
    #[command(alias = "backup")]
    Export(ExportArgs),
    #[command(alias = "restore")]
    Import(ImportArgs),
    Target(TargetArgs),
    Package(PackageArgs),
    Sync,
    Build(BuildArgs),
    Custom(CustomArgs),
    #[command(visible_alias = "exec", alias = "command")]
    Run(CommandArgs),
}

#[derive(Args, Debug)]
struct TargetArgs {
    #[command(subcommand)]
    action: TargetAction,
}

#[derive(Subcommand, Debug)]
enum TargetAction {
    #[command(alias = "new")]
    Add {
        name: String,
    },
    #[command(alias = "delete", alias = "rm")]
    Remove {
        name: String,
    },
    Init,
    Update,
    Config {
        #[arg(trailing_var_arg = true, allow_hyphen_values = true)]
        extra_args: Vec<String>,
    },
    Feed,
    Export {
        output: Option<String>,
    },
    Import {
        input: String,
    },
    Download {
        #[arg(trailing_var_arg = true, allow_hyphen_values = true)]
        extra_args: Vec<String>,
    },
    Clean {
        #[arg(trailing_var_arg = true, allow_hyphen_values = true)]
        extra_args: Vec<String>,
    },
    Distclean {
        #[arg(trailing_var_arg = true, allow_hyphen_values = true)]
        extra_args: Vec<String>,
    },
}

#[derive(Args, Debug)]
struct PackageArgs {
    #[command(subcommand)]
    action: PackageAction,
}

#[derive(Subcommand, Debug)]
enum PackageAction {
    Feed {
        #[arg(trailing_var_arg = true, allow_hyphen_values = true)]
        packages: Vec<String>,
    },
    Update {
        #[arg(trailing_var_arg = true, allow_hyphen_values = true)]
        packages: Vec<String>,
    },
    Install {
        #[arg(trailing_var_arg = true, allow_hyphen_values = true)]
        packages: Vec<String>,
    },
}

#[derive(Args, Debug)]
struct ExportArgs {
    output: Option<String>,
}

#[derive(Args, Debug)]
struct ImportArgs {
    input: String,
}

#[derive(Args, Debug)]
struct BuildArgs {
    #[arg(trailing_var_arg = true, allow_hyphen_values = true)]
    extra_args: Vec<String>,
}

#[derive(Args, Debug)]
struct CustomArgs {
    name: String,
    #[arg(trailing_var_arg = true, allow_hyphen_values = true)]
    extra_args: Vec<String>,
}

#[derive(Args, Debug)]
struct CommandArgs {
    cmd: String,
}

fn exit_on_error<T>(result: Result<T>) {
    if let Err(err) = result {
        // print error with its chain for better diagnostics
        eprintln!("{}", format!("错误: {:#}", err).red());
        process::exit(1);
    }
}

pub fn run() {
    ctrlc::set_handler(|| {
        INTERRUPTED.store(true, std::sync::atomic::Ordering::SeqCst);
    })
    .expect("设置 Ctrl+C 处理函数失败");

    let cli = match Cli::try_parse() {
        Ok(cli) => cli,
        Err(err) => {
            eprintln!("{}", err);
            process::exit(1);
        }
    };

    match cli.command {
        Command::List => exit_on_error(crate::targets::list_targets(TARGETS_DIR)),
        Command::Select => exit_on_error(crate::config::change_target(TARGETS_DIR)),
        Command::Export(args) => exit_on_error(crate::targets::export_targets(args.output.as_deref().unwrap_or("backup/owbm-export"))),
        Command::Import(args) => exit_on_error(crate::targets::import_targets(&args.input)),
        Command::Target(args) => match args.action {
           TargetAction::Add { name } => exit_on_error(crate::targets::target_add(&name)),
           TargetAction::Remove { name } => exit_on_error(crate::targets::target_remove(&name)),
           TargetAction::Init => exit_on_error(crate::targets::target_init()),
           TargetAction::Update => exit_on_error(crate::targets::target_update()),
           TargetAction::Config { .. } => exit_on_error(crate::targets::target_config()),
           TargetAction::Feed => exit_on_error(crate::targets::target_feed()),
           TargetAction::Export { output } => exit_on_error(crate::targets::export_targets(output.as_deref().unwrap_or("backup/owbm-export"))),
           TargetAction::Import { input } => exit_on_error(crate::targets::import_targets(&input)),
           TargetAction::Download { .. } => exit_on_error(crate::targets::target_download()),
           TargetAction::Clean { .. } => exit_on_error(crate::targets::target_clean()),
           TargetAction::Distclean { .. } => exit_on_error(crate::targets::target_distclean()),
        },
        Command::Package(args) => match args.action {
            PackageAction::Feed { .. } => exit_on_error(crate::packages::package_feed()),
            PackageAction::Update { .. } => exit_on_error(crate::packages::package_update()),
            PackageAction::Install { .. } => exit_on_error(crate::packages::package_install()),
        },
        Command::Sync => exit_on_error(crate::targets::config_sync()),
        Command::Build(_) => exit_on_error(crate::build::build()),
        Command::Custom(args) => exit_on_error(crate::build::run_custom_script(&args.name, &args.extra_args)),
        Command::Run(args) => exit_on_error(crate::build::run_command(&args.cmd)),
    }
}
