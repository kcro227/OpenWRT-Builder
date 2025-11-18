#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdbool.h>
#include <unistd.h>
#include <getopt.h>
#include <libgen.h>
#include <linux/limits.h>
#include <sys/stat.h>
#include <errno.h>

#include "../utils/utils.h"
#include "../utils/color.h"

// 打印使用说明
void print_usage(const char *program_name) {
    printf("%s用法: %s [选项] <目标型号>%s\n", STYLE_BOLD, program_name, COLOR_RESET);
    printf("选项:\n");
    printf("  -h, --help          显示此帮助信息\n");
    printf("  -f, --force         强制重新下载源码\n");
    printf("  -u, --update        更新已存在的源码\n");
    printf("  -b, --branch <分支>  指定源码分支 (默认: master)\n");
    printf("  -s, --source <url>   指定源码仓库URL\n");
    printf("  -c, --commit <提交>  指定源码提交哈希\n");
    printf("参数:\n");
    printf("  目标型号: 指定要初始化源码的型号名称 (如: m28c, xr30)\n");
}

// 读取源码配置文件
int read_source_config(const char *model, char *repo_url, char *branch, char *commit) {
    char config_path[PATH_MAX];
    snprintf(config_path, sizeof(config_path), "configs/%s/source.conf", model);
    
    if (!file_exists(config_path)) {
        log_info("型号 %s 的 source.conf 文件不存在", model);
        return -1;
    }
    
    FILE *file = fopen(config_path, "r");
    if (file == NULL) {
        log_error("无法打开文件 %s: %s", config_path, strerror(errno));
        return -1;
    }
    
    char line[1024];
    bool found_repo = false;
    bool found_branch = false;
    bool found_commit = false;
    
    // 设置默认值
    strcpy(branch, "master");
    strcpy(commit, "");
    
    while (fgets(line, sizeof(line), file) != NULL) {
        // 跳过注释行和空行
        if (line[0] == '#' || line[0] == '\n') {
            continue;
        }
        
        // 移除行尾的换行符
        line[strcspn(line, "\n")] = 0;
        
        // 解析键值对
        char *key = strtok(line, "=");
        char *value = strtok(NULL, "=");
        
        if (key != NULL && value != NULL) {
            // 去除键和值的空白字符
            char *trimmed_key = trim_whitespace(key);
            char *trimmed_value = trim_whitespace(value);
            
            if (strcmp(trimmed_key, "REPO_URL") == 0) {
                strncpy(repo_url, trimmed_value, PATH_MAX - 1);
                found_repo = true;
            } else if (strcmp(trimmed_key, "BRANCH") == 0) {
                strncpy(branch, trimmed_value, PATH_MAX - 1);
                found_branch = true;
            } else if (strcmp(trimmed_key, "COMMIT") == 0) {
                strncpy(commit, trimmed_value, PATH_MAX - 1);
                found_commit = true;
            }
        }
    }
    
    fclose(file);
    
    if (!found_repo) {
        log_error("在 %s 中未找到 REPO_URL 配置", config_path);
        return -1;
    }
    
    if (found_branch) {
        log_info("使用分支: %s", branch);
    } else {
        log_info("使用默认分支: %s", branch);
    }
    
    if (found_commit) {
        log_info("使用提交: %s", commit);
    }
    
    return 0;
}

// 切换到指定的提交
int switch_to_commit(const char *target_dir, const char *commit) {
    char current_dir[PATH_MAX];
    if (getcwd(current_dir, sizeof(current_dir)) == NULL) {
        log_error("获取当前目录失败: %s", strerror(errno));
        return -1;
    }
    
    // 切换到目标目录
    if (chdir(target_dir) != 0) {
        log_error("无法进入目录: %s", target_dir);
        return -1;
    }
    
    log_info("切换到提交: %s", commit);
    
    // 检查提交是否存在
    char check_cmd[256];
    snprintf(check_cmd, sizeof(check_cmd), "git cat-file -e %s 2>/dev/null", commit);
    int check_result = system(check_cmd);
    
    if (check_result != 0) {
        log_warning("提交 %s 在本地不存在，尝试获取...", commit);
        
        // 获取远程更新
        int fetch_result = system("git fetch --all 2>&1");
        if (fetch_result != 0) {
            log_error("git fetch 失败");
            chdir(current_dir);
            return -1;
        }
        
        // 再次检查提交
        check_result = system(check_cmd);
        if (check_result != 0) {
            log_error("提交 %s 不存在于仓库中", commit);
            chdir(current_dir);
            return -1;
        }
    }
    
    // 切换到指定提交
    char switch_cmd[256];
    snprintf(switch_cmd, sizeof(switch_cmd), "git checkout %s 2>&1", commit);
    
    FILE *switch_output = popen(switch_cmd, "r");
    char output[1024] = {0};
    if (switch_output != NULL) {
        while (fgets(output, sizeof(output), switch_output) != NULL) {
            // 可以记录输出，但为了简洁这里不显示
        }
        int switch_result = pclose(switch_output);
        
        if (switch_result == 0) {
            log_success("成功切换到提交: %s", commit);
            
            // 获取提交信息
            char info_cmd[256];
            snprintf(info_cmd, sizeof(info_cmd), "git log -1 --oneline %s", commit);
            FILE *info_output = popen(info_cmd, "r");
            if (info_output != NULL) {
                char commit_info[256];
                if (fgets(commit_info, sizeof(commit_info), info_output) != NULL) {
                    commit_info[strcspn(commit_info, "\n")] = 0;
                    log_info("提交信息: %s", commit_info);
                }
                pclose(info_output);
            }
        } else {
            log_error("切换到提交失败: %s", commit);
            log_info("错误详情: %s", output);
        }
        
        chdir(current_dir);
        return switch_result;
    }
    
    chdir(current_dir);
    return -1;
}

// 克隆源码仓库（带重试机制）
int clone_repository(const char *repo_url, const char *branch, const char *commit, const char *target_dir) {
    char cmd[1024];
    int result = -1;
    
    // 构建克隆命令
    if (strlen(branch) > 0) {
        snprintf(cmd, sizeof(cmd), "git clone -b %s --single-branch --depth 1 %s \"%s\"", 
                 branch, repo_url, target_dir);
    } else {
        snprintf(cmd, sizeof(cmd), "git clone --single-branch --depth 1 %s \"%s\"", 
                 repo_url, target_dir);
    }
    
    // 最多重试3次
    for (int attempt = 1; attempt <= 3; attempt++) {
        log_info("下载尝试 (%d/3): %s", attempt, basename((char*)target_dir));
        log_info("执行命令: %s", cmd);
        
        result = system(cmd);
        
        if (result == 0) {
            log_success("下载成功: %s", basename((char*)target_dir));
            
            // 如果指定了提交，切换到该提交
            if (strlen(commit) > 0) {
                if (switch_to_commit(target_dir, commit) == 0) {
                    log_success("成功切换到指定提交: %s", commit);
                } else {
                    log_error("切换到指定提交失败: %s", commit);
                    return -1;
                }
            }
            
            return 0;
        }
        
        log_warning("下载失败 (尝试: %d/3)", attempt);
        
        // 删除可能部分下载的目录
        if (dir_exists(target_dir)) {
            remove_file_or_dir(target_dir);
        }
        
        // 指数退避等待
        sleep(attempt * 2);
        
        // 最后一次尝试时，如果不指定分支失败，尝试默认分支
        if (attempt == 3 && strlen(branch) > 0) {
            log_info("尝试默认分支");
            snprintf(cmd, sizeof(cmd), "git clone --single-branch --depth 1 %s \"%s\"", 
                     repo_url, target_dir);
            result = system(cmd);
            if (result == 0) {
                log_success("下载成功（默认分支）: %s", basename((char*)target_dir));
                
                // 如果指定了提交，切换到该提交
                if (strlen(commit) > 0) {
                    if (switch_to_commit(target_dir, commit) == 0) {
                        log_success("成功切换到指定提交: %s", commit);
                    } else {
                        log_error("切换到指定提交失败: %s", commit);
                        return -1;
                    }
                }
                
                return 0;
            }
        }
    }
    
    log_error("下载失败: %s", basename((char*)target_dir));
    return -1;
}

// 更新源码仓库
int update_repository(const char *target_dir, const char *branch, const char *commit) {
    char current_dir[PATH_MAX];
    if (getcwd(current_dir, sizeof(current_dir)) == NULL) {
        log_error("获取当前目录失败: %s", strerror(errno));
        return -1;
    }
    
    // 切换到目标目录
    if (chdir(target_dir) != 0) {
        log_error("无法进入目录: %s", target_dir);
        return -1;
    }
    
    // 检查是否为git仓库
    if (!dir_exists(".git")) {
        log_warning("非git仓库: %s", target_dir);
        chdir(current_dir);
        return 0;
    }
    
    // 获取当前提交ID
    FILE *git_cmd = popen("git rev-parse --short HEAD 2>/dev/null", "r");
    char current_commit[64] = "unknown";
    if (git_cmd != NULL) {
        if (fgets(current_commit, sizeof(current_commit), git_cmd) != NULL) {
            current_commit[strcspn(current_commit, "\n")] = 0;
        }
        pclose(git_cmd);
    }
    
    log_info("开始更新源码: %s", basename((char*)target_dir));
    log_info("当前提交: %s", current_commit);
    
    // 如果指定了提交，直接切换到该提交
    if (strlen(commit) > 0) {
        chdir(current_dir);
        return switch_to_commit(target_dir, commit);
    }
    
    // 否则执行常规更新流程
    // 执行git fetch
    int fetch_result = system("git fetch --all 2>&1");
    if (fetch_result != 0) {
        log_error("git fetch 失败");
        chdir(current_dir);
        return -1;
    }
    
    // 重置到远程分支
    char reset_cmd[256];
    snprintf(reset_cmd, sizeof(reset_cmd), "git reset --hard origin/%s 2>&1", branch);
    
    FILE *reset_output = popen(reset_cmd, "r");
    char output[1024] = {0};
    if (reset_output != NULL) {
        while (fgets(output, sizeof(output), reset_output) != NULL) {
            // 可以记录输出，但为了简洁这里不显示
        }
        int reset_result = pclose(reset_output);
        
        // 获取新提交ID
        git_cmd = popen("git rev-parse --short HEAD 2>/dev/null", "r");
        char new_commit[64] = "unknown";
        if (git_cmd != NULL) {
            if (fgets(new_commit, sizeof(new_commit), git_cmd) != NULL) {
                new_commit[strcspn(new_commit, "\n")] = 0;
            }
            pclose(git_cmd);
        }
        
        if (reset_result == 0) {
            if (strcmp(current_commit, new_commit) != 0) {
                log_success("更新成功: %s (%s → %s)", 
                           basename((char*)target_dir), current_commit, new_commit);
            } else {
                log_info("已是最新: %s (%s)", basename((char*)target_dir), current_commit);
            }
        } else {
            log_error("更新失败: %s", basename((char*)target_dir));
            log_info("错误详情: %s", output);
        }
        
        chdir(current_dir);
        return reset_result;
    }
    
    chdir(current_dir);
    return -1;
}

// 初始化目标源码
int init_target_source(const char *model, const char *repo_url, const char *branch, 
                       const char *commit, bool force, bool update) {
    char target_dir[PATH_MAX];
    snprintf(target_dir, sizeof(target_dir), "srcs/%s", model);
    
    // 检查目标目录是否已存在
    if (dir_exists(target_dir)) {
        if (force) {
            log_info("强制重新下载源码，删除现有目录: %s", target_dir);
            if (remove_file_or_dir(target_dir) != 0) {
                log_error("删除目录失败: %s", target_dir);
                return -1;
            }
        } else if (update) {
            log_info("更新已存在的源码: %s", target_dir);
            return update_repository(target_dir, branch, commit);
        } else {
            log_info("源码目录已存在: %s", target_dir);
            return 0;
        }
    }
    
    // 创建目标目录的父目录
    char parent_dir[PATH_MAX];
    strncpy(parent_dir, target_dir, sizeof(parent_dir));
    char *parent = dirname(parent_dir);
    
    if (!dir_exists(parent)) {
        log_info("创建目录: %s", parent);
        if (create_dir(parent) != 0) {
            log_error("创建目录失败: %s", parent);
            return -1;
        }
    }
    
    // 克隆源码（带重试机制）
    int result = clone_repository(repo_url, branch, commit, target_dir);
    
    if (result == 0) {
        log_success("成功初始化源码: %s", model);
        if (strlen(commit) > 0) {
            log_success("使用提交: %s", commit);
        }
    } else {
        log_error("初始化源码失败: %s", model);
    }
    
    return result;
}

int main(int argc, char *argv[]) {
    char *model = NULL;
    char *custom_repo_url = NULL;
    char *custom_branch = NULL;
    char *custom_commit = NULL;
    bool force = false;
    bool update = false;
    
    // 解析命令行参数
    static struct option long_options[] = {
        {"help", no_argument, 0, 'h'},
        {"force", no_argument, 0, 'f'},
        {"update", no_argument, 0, 'u'},
        {"branch", required_argument, 0, 'b'},
        {"source", required_argument, 0, 's'},
        {"commit", required_argument, 0, 'c'},
        {0, 0, 0, 0}
    };
    
    int opt;
    while ((opt = getopt_long(argc, argv, "hfub:s:c:", long_options, NULL)) != -1) {
        switch (opt) {
            case 'h':
                print_usage(argv[0]);
                return 0;
                
            case 'f':
                force = true;
                break;
                
            case 'u':
                update = true;
                break;
                
            case 'b':
                custom_branch = optarg;
                break;
                
            case 's':
                custom_repo_url = optarg;
                break;
                
            case 'c':
                custom_commit = optarg;
                break;
                
            default:
                print_usage(argv[0]);
                return 1;
        }
    }
    
    if (optind >= argc) {
        fprintf(stderr, "错误: 需要指定目标型号\n");
        print_usage(argv[0]);
        return 1;
    }
    
    model = argv[optind];
    
    char repo_url[PATH_MAX] = {0};
    char branch[PATH_MAX] = {0};
    char commit[PATH_MAX] = {0};
    
    // 如果未通过命令行指定仓库URL，则尝试从配置文件读取
    if (custom_repo_url == NULL) {
        if (read_source_config(model, repo_url, branch, commit) != 0) {
            log_error("无法获取源码配置信息");
            return 1;
        }
    } else {
        strncpy(repo_url, custom_repo_url, PATH_MAX - 1);
    }
    
    // 如果通过命令行指定了分支，则覆盖配置文件中的分支
    if (custom_branch != NULL) {
        strncpy(branch, custom_branch, PATH_MAX - 1);
    }
    
    // 如果通过命令行指定了提交，则覆盖配置文件中的提交
    if (custom_commit != NULL) {
        strncpy(commit, custom_commit, PATH_MAX - 1);
    }
    
    log_info("目标型号: %s", model);
    log_info("源码仓库: %s", repo_url);
    log_info("分支: %s", branch);
    if (strlen(commit) > 0) {
        log_info("提交: %s", commit);
    }
    
    // 初始化源码
    return init_target_source(model, repo_url, branch, commit, force, update);
}