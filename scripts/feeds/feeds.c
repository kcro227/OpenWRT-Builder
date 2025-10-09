#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <sys/stat.h>
#include <libgen.h>
#include <errno.h>
#include <linux/limits.h>

// 如果 PATH_MAX 仍然未定义，则手动定义它
#ifndef PATH_MAX
#define PATH_MAX 4096
#endif

#include "feeds.h"
#include "../utils/utils.h"
#include "../utils/color.h"

// 打印使用说明
void print_usage(const char *program_name) {
    printf("%s用法: %s [选项] <命令> [feed名称]%s\n", STYLE_BOLD, program_name, COLOR_RESET);
    printf("选项:\n");
    printf("  -f <文件>  指定feeds配置文件 (默认: %s)\n", DEFAULT_FEEDS_FILE);
    printf("  -d <目录>  指定feeds安装目录 (默认: %s)\n", DEFAULT_FEEDS_DIR);
    printf("  -h         显示此帮助信息\n");
    printf("命令:\n");
    printf("  install    安装指定的feed或所有feeds\n");
    printf("  update     更新指定的feed或所有feeds\n");
    printf("  list       列出所有可用的feeds\n");
}

// 解析feeds配置文件
int parse_feeds_file(const char *filename, Feed feeds[], int *feed_count) {
    FILE *file = fopen(filename, "r");
    if (file == NULL) {
        log_error("无法打开文件 %s: %s", filename, strerror(errno));
        return -1;
    }
    
    char line[MAX_LINE_LENGTH];
    *feed_count = 0;
    int line_num = 0;
    
    while (fgets(line, sizeof(line), file) != NULL && *feed_count < MAX_FEEDS) {
        line_num++;
        
        // 跳过注释行和空行
        if (line[0] == '#' || line[0] == '\n') {
            continue;
        }
        
        // 移除行尾的换行符
        line[strcspn(line, "\n")] = 0;
        
        // 解析行
        char *saveptr;
        char *token = strtok_r(line, " ", &saveptr);
        if (token == NULL) continue;
        
        // 初始化feed结构体
        Feed feed = {0};
        strncpy(feed.type, token, sizeof(feed.type) - 1);
        
        token = strtok_r(NULL, " ", &saveptr);
        if (token == NULL) {
            log_warning("第 %d 行格式错误，缺少名称字段", line_num);
            continue;
        }
        strncpy(feed.name, token, sizeof(feed.name) - 1);
        
        // 获取URL和分支
        char *url_and_branch = strtok_r(NULL, "", &saveptr);
        if (url_and_branch == NULL) {
            log_warning("第 %d 行格式错误，缺少URL字段", line_num);
            continue;
        }
        
        // 查找分号分隔符
        char *semicolon = strchr(url_and_branch, ';');
        if (semicolon != NULL) {
            // 有分支指定
            *semicolon = '\0'; // 分割URL和分支
            strncpy(feed.url, url_and_branch, sizeof(feed.url) - 1);
            
            // 获取分支，跳过可能的分号后的空格
            char *branch_start = semicolon + 1;
            while (*branch_start == ' ') branch_start++;
            
            if (*branch_start != '\0') {
                strncpy(feed.branch, branch_start, sizeof(feed.branch) - 1);
            } else {
                // 分支为空，使用默认分支
                strncpy(feed.branch, "master", sizeof(feed.branch) - 1);
            }
        } else {
            // 没有分支指定，使用默认分支
            strncpy(feed.url, url_and_branch, sizeof(feed.url) - 1);
            strncpy(feed.branch, "master", sizeof(feed.branch) - 1);
        }
        
        feeds[(*feed_count)++] = feed;
    }
    
    fclose(file);
    return 0;
}

// 克隆feed仓库（带重试机制）
int clone_feed_repository(const Feed *feed, const char *path) {
    char command[1024];
    int result = -1;
    
    // 构建克隆命令
    snprintf(command, sizeof(command), "git clone -b %s --single-branch --depth 1 %s \"%s\"", 
             feed->branch, feed->url, path);
    
    // 最多重试3次
    for (int attempt = 1; attempt <= 3; attempt++) {
        log_info("下载尝试 (%d/3): %s", attempt, feed->name);
        log_info("执行命令: %s", command);
        
        result = system(command);
        
        if (result == 0) {
            log_success("下载成功: %s", feed->name);
            return 0;
        }
        
        log_warning("下载失败 (尝试: %d/3)", attempt);
        
        // 删除可能部分下载的目录
        if (dir_exists(path)) {
            remove_file_or_dir(path);
        }
        
        // 指数退避等待
        sleep(attempt * 2);
        
        // 最后一次尝试时，如果不指定分支失败，尝试默认分支
        if (attempt == 3 && strlen(feed->branch) > 0) {
            log_info("尝试默认分支");
            snprintf(command, sizeof(command), "git clone --single-branch --depth 1 %s \"%s\"", 
                     feed->url, path);
            result = system(command);
            if (result == 0) {
                log_success("下载成功（默认分支）: %s", feed->name);
                return 0;
            }
        }
    }
    
    log_error("下载失败: %s", feed->name);
    return -1;
}

// 更新feed仓库
int update_feed_repository(const Feed *feed, const char *path) {
    char current_dir[PATH_MAX];
    if (getcwd(current_dir, sizeof(current_dir)) == NULL) {
        log_error("获取当前目录失败: %s", strerror(errno));
        return -1;
    }
    
    // 切换到目标目录
    if (chdir(path) != 0) {
        log_error("无法进入目录: %s", path);
        return -1;
    }
    
    // 检查是否为git仓库
    if (!dir_exists(".git")) {
        log_warning("非git仓库: %s", feed->name);
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
    
    log_info("开始更新feed: %s", feed->name);
    log_info("当前提交: %s", current_commit);
    
    // 执行git fetch
    int fetch_result = system("git fetch --all 2>&1");
    if (fetch_result != 0) {
        log_error("git fetch 失败: %s", feed->name);
        chdir(current_dir);
        return -1;
    }
    
    // 重置到远程分支
    char reset_cmd[256];
    snprintf(reset_cmd, sizeof(reset_cmd), "git reset --hard origin/%s 2>&1", feed->branch);
    
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
                           feed->name, current_commit, new_commit);
            } else {
                log_info("已是最新: %s (%s)", feed->name, current_commit);
            }
        } else {
            log_error("更新失败: %s", feed->name);
            log_info("错误详情: %s", output);
        }
        
        chdir(current_dir);
        return reset_result;
    }
    
    chdir(current_dir);
    return -1;
}

// 安装feed
int install_feed(const Feed *feed, const char *base_dir) {
    char path[PATH_MAX];
    snprintf(path, sizeof(path), "%s/%s", base_dir, feed->name);
    
    struct stat st = {0};
    if (stat(path, &st) == 0) {
        log_info("Feed %s 已存在，跳过安装", feed->name);
        return 0;
    }
    
    log_info("开始安装feed: %s", feed->name);
    log_info("仓库: %s", feed->url);
    log_info("分支: %s", feed->branch);
    log_info("目标路径: %s", path);
    
    // 创建目标目录的父目录
    char parent_dir[PATH_MAX];
    strncpy(parent_dir, path, sizeof(parent_dir));
    char *parent = dirname(parent_dir);
    
    if (!dir_exists(parent)) {
        log_info("创建目录: %s", parent);
        if (create_dir(parent) != 0) {
            log_error("创建目录失败: %s", parent);
            return -1;
        }
    }
    
    // 克隆feed（带重试机制）
    int result = clone_feed_repository(feed, path);
    
    if (result == 0) {
        log_success("成功安装 feed: %s", feed->name);
    } else {
        log_error("安装 feed %s 失败", feed->name);
    }
    
    return result;
}

// 更新feed
int update_feed(const Feed *feed, const char *base_dir) {
    char path[PATH_MAX];
    snprintf(path, sizeof(path), "%s/%s", base_dir, feed->name);
    
    struct stat st = {0};
    if (stat(path, &st) == -1) {
        log_info("Feed %s 不存在，尝试安装", feed->name);
        return install_feed(feed, base_dir);
    }
    
    log_info("开始更新feed: %s", feed->name);
    log_info("仓库: %s", feed->url);
    log_info("分支: %s", feed->branch);
    log_info("目标路径: %s", path);
    
    // 更新feed仓库
    int result = update_feed_repository(feed, path);
    
    if (result == 0) {
        log_success("成功更新 feed: %s", feed->name);
    } else {
        log_error("更新 feed %s 失败", feed->name);
    }
    
    return result;
}

// 截断字符串并在末尾添加省略号
char* truncate_string(const char* str, int max_len) {
    if (str == NULL) return NULL;
    
    int len = strlen(str);
    if (len <= max_len) {
        return strdup(str);
    }
    
    char* truncated = malloc(max_len + 4); // 为省略号留出空间
    if (truncated == NULL) return NULL;
    
    strncpy(truncated, str, max_len);
    strcpy(truncated + max_len, "...");
    
    return truncated;
}

// 列出所有feeds
int list_feeds(Feed feeds[], int feed_count) {
    if (feed_count == 0) {
        log_info("没有找到任何feeds");
        return 0;
    }
    
    // 获取终端宽度
    int terminal_width = get_terminal_width();
    
    // 定义列宽（根据终端宽度自适应调整）
    int type_width = 20;
    int name_width = 30;
    int branch_width = 15;
    int url_width;
    
    // 计算URL列的可用宽度
    int min_url_width = 20; // URL列的最小宽度
    int available_width = terminal_width - (type_width + name_width + branch_width + 6); // 6是列之间的间隔
    
    if (available_width < min_url_width) {
        // 如果终端太窄，调整其他列的宽度
        type_width = 10;
        name_width = 20;
        branch_width = 10;
        available_width = terminal_width - (type_width + name_width + branch_width + 6);
        
        if (available_width < min_url_width) {
            // 如果仍然太窄，使用最小宽度
            url_width = min_url_width;
        } else {
            url_width = available_width;
        }
    } else {
        url_width = available_width;
    }
    
    // 打印表头
    printf("%s%-*s %-*s %-*s %-*s%s\n", STYLE_BOLD, 
           type_width, "类型", 
           name_width, "名称", 
           url_width, "URL", 
           branch_width, "分支", 
           COLOR_RESET);
    
    // 打印分隔线
    for (int i = 0; i < terminal_width; i++) {
        printf("-");
    }
    printf("\n");
    
    // 打印feed列表
    for (int i = 0; i < feed_count; i++) {
        // 截断URL以适应列宽
        char* truncated_url = truncate_string(feeds[i].url, url_width);
        
        printf("%-*s %-*s %-*s %-*s\n", 
               type_width, feeds[i].type, 
               name_width, feeds[i].name, 
               url_width, truncated_url ? truncated_url : "", 
               branch_width, feeds[i].branch);
        
        if (truncated_url) free(truncated_url);
    }
    
    return 0;
}

// 执行git命令（保留原函数，但主要逻辑已移到新函数中）
int run_git_command(const char *command, const char *path) {
    int result;
    
    if (path != NULL) {
        // 保存当前目录
        char cwd[PATH_MAX];
        if (getcwd(cwd, sizeof(cwd)) == NULL) {
            log_error("获取当前工作目录失败: %s", strerror(errno));
            return -1;
        }
        
        // 切换到目标目录
        if (chdir(path) != 0) {
            log_error("切换目录失败 %s: %s", path, strerror(errno));
            return -1;
        }
        
        // 执行命令
        result = system(command);
        
        // 切换回原目录
        chdir(cwd);
    } else {
        // 执行命令
        result = system(command);
    }
    
    return result;
}

int main(int argc, char *argv[]) {
    Feed feeds[MAX_FEEDS] = {0};
    int feed_count = 0;
    char feeds_file_path[PATH_MAX] = {0};
    char feeds_dir_path[PATH_MAX] = {0};
    char *action = NULL;
    char *feed_name = NULL;
    char *custom_feeds_file = NULL;
    char *custom_feeds_dir = NULL;
    
    // 解析命令行参数
    for (int i = 1; i < argc; i++) {
        if (strcmp(argv[i], "-f") == 0 && i + 1 < argc) {
            custom_feeds_file = argv[++i];
        } else if (strcmp(argv[i], "-d") == 0 && i + 1 < argc) {
            custom_feeds_dir = argv[++i];
        } else if (strcmp(argv[i], "install") == 0 || 
                   strcmp(argv[i], "update") == 0 ||
                   strcmp(argv[i], "list") == 0) {
            action = argv[i];
            if (i + 1 < argc && argv[i + 1][0] != '-') {
                feed_name = argv[++i];
            }
        } else if (strcmp(argv[i], "-h") == 0 || strcmp(argv[i], "--help") == 0) {
            print_usage(argv[0]);
            return 0;
        } else {
            log_error("未知参数: %s", argv[i]);
            print_usage(argv[0]);
            return 1;
        }
    }
    
    if (action == NULL) {
        log_error("需要指定操作 (install, update 或 list)");
        print_usage(argv[0]);
        return 1;
    }
    
    // 获取项目根目录
    char *project_root = get_project_root();
    if (project_root == NULL) {
        log_error("无法确定项目根目录");
        return 1;
    }
    
    // 确定feeds配置文件和目录路径
    if (custom_feeds_file != NULL) {
        snprintf(feeds_file_path, sizeof(feeds_file_path), "%s", custom_feeds_file);
    } else {
        snprintf(feeds_file_path, sizeof(feeds_file_path), "%s/%s", project_root, DEFAULT_FEEDS_FILE);
    }
    
    if (custom_feeds_dir != NULL) {
        snprintf(feeds_dir_path, sizeof(feeds_dir_path), "%s", custom_feeds_dir);
    } else {
        snprintf(feeds_dir_path, sizeof(feeds_dir_path), "%s/%s", project_root, DEFAULT_FEEDS_DIR);
    }
    
    log_info("使用配置文件: %s", feeds_file_path);
    log_info("Feeds目录: %s", feeds_dir_path);
    
    // 解析feeds文件
    if (parse_feeds_file(feeds_file_path, feeds, &feed_count) != 0) {
        log_error("无法解析feeds文件 %s", feeds_file_path);
        free(project_root);
        return 1;
    }
    
    // 如果是list命令，直接列出feeds并退出
    if (strcmp(action, "list") == 0) {
        list_feeds(feeds, feed_count);
        free(project_root);
        return 0;
    }
    
    // 创建feeds目录（如果不存在）
    if (ensure_directory_exists(feeds_dir_path) != 0) {
        log_error("无法创建feeds目录 %s", feeds_dir_path);
        free(project_root);
        return 1;
    }
    
    // 执行操作
    int result = 0;
    int processed = 0;
    int success = 0;
    
    for (int i = 0; i < feed_count; i++) {
        if (feed_name == NULL || strcmp(feeds[i].name, feed_name) == 0) {
            processed++;
            
            if (strcmp(action, "install") == 0) {
                if (install_feed(&feeds[i], feeds_dir_path) == 0) {
                    success++;
                } else {
                    log_error("安装feed %s 失败", feeds[i].name);
                    result = 1;
                }
            } else if (strcmp(action, "update") == 0) {
                if (update_feed(&feeds[i], feeds_dir_path) == 0) {
                    success++;
                } else {
                    log_error("更新feed %s 失败", feeds[i].name);
                    result = 1;
                }
            }
            
            // 如果指定了特定的feed名称，处理完就退出
            if (feed_name != NULL) {
                break;
            }
        }
    }
    
    // 检查是否找到了指定的feed
    if (feed_name != NULL && processed == 0) {
        log_error("未找到指定的feed: %s", feed_name);
        result = 1;
    }
    
    // 输出统计信息
    if (processed > 0) {
        if (success == processed) {
            log_success("操作完成 (%d/%d 全部成功)", success, processed);
        } else {
            log_error("操作完成 (成功: %d/%d, 失败: %d)", success, processed, processed - success);
        }
    }
    
    free(project_root);
    return result;
}