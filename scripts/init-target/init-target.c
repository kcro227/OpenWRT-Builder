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
    printf("参数:\n");
    printf("  目标型号: 指定要初始化源码的型号名称 (如: m28c, xr30)\n");
}

// 读取源码配置文件
int read_source_config(const char *model, char *repo_url, char *branch) {
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
    
    // 设置默认值
    strcpy(branch, "master");
    
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
    
    return 0;
}

// 初始化目标源码
int init_target_source(const char *model, const char *repo_url, const char *branch, 
                       bool force, bool update) {
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
            char cmd[1024];
            snprintf(cmd, sizeof(cmd), "cd \"%s\" && git pull", target_dir);
            return system(cmd);
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
    
    // 克隆源码
    char cmd[1024];
    if (strlen(branch) > 0) {
        snprintf(cmd, sizeof(cmd), "git clone -b %s --single-branch --depth 1 %s \"%s\"", 
                 branch, repo_url, target_dir);
    } else {
        snprintf(cmd, sizeof(cmd), "git clone --single-branch --depth 1 %s \"%s\"", 
                 repo_url, target_dir);
    }
    
    log_info("执行: %s", cmd);
    int result = system(cmd);
    
    if (result == 0) {
        log_success("成功初始化源码: %s", model);
    } else {
        log_error("初始化源码失败: %s", model);
    }
    
    return result;
}

int main(int argc, char *argv[]) {
    char *model = NULL;
    char *custom_repo_url = NULL;
    char *custom_branch = NULL;
    bool force = false;
    bool update = false;
    
    // 解析命令行参数
    static struct option long_options[] = {
        {"help", no_argument, 0, 'h'},
        {"force", no_argument, 0, 'f'},
        {"update", no_argument, 0, 'u'},
        {"branch", required_argument, 0, 'b'},
        {"source", required_argument, 0, 's'},
        {0, 0, 0, 0}
    };
    
    int opt;
    while ((opt = getopt_long(argc, argv, "hfub:s:", long_options, NULL)) != -1) {
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
    
    // 如果未通过命令行指定仓库URL，则尝试从配置文件读取
    if (custom_repo_url == NULL) {
        if (read_source_config(model, repo_url, branch) != 0) {
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
    
    log_info("目标型号: %s", model);
    log_info("源码仓库: %s", repo_url);
    log_info("分支: %s", branch);
    
    // 初始化源码
    return init_target_source(model, repo_url, branch, force, update);
}