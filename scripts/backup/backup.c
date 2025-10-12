#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdbool.h>
#include <time.h>
#include <unistd.h>
#include <sys/stat.h>
#include <dirent.h>
#include <libgen.h>
#include <errno.h>

#include "../utils/utils.h"

// 函数声明
void print_usage(const char *program_name);
int backup_critical_files(const char *model, const char *backup_list_path);
int clean_build_environment(const char *model, const char *backup_list_path);
char* get_backup_dir(const char *model);
char* get_source_dir(const char *model);
int confirm_action(const char *message);
void log_message(const char *level, const char *message, const char *module);
void debug_print_paths(const char *model);

int main(int argc, char *argv[]) {
    if (argc != 3) {
        print_usage(argv[0]);
        return 1;
    }

    const char *model = argv[1];
    const char *action = argv[2];

    // 调试：打印路径信息
    debug_print_paths(model);

    // 获取项目根目录
    char *project_root = get_project_root();
    if (project_root == NULL) {
        log_error("错误: 无法确定项目根目录\n");
        return 1;
    }

    // 构建备份列表文件路径
    char backup_list_path[1024];
    snprintf(backup_list_path, sizeof(backup_list_path), 
             "%s/configs/%s/backup_list.conf", project_root, model);

    // 执行请求的操作
    int result = 0;
    if (strcmp(action, "backup") == 0) {
        result = backup_critical_files(model, backup_list_path);
    } else if (strcmp(action, "clean") == 0) {
        result = clean_build_environment(model, backup_list_path);
    } else {
        log_error("错误: 未知的操作 '%s'\n", action);
        print_usage(argv[0]);
        result = 1;
    }

    free(project_root);
    return result;
}

void print_usage(const char *program_name) {
    printf("用法: %s <型号> <操作>\n", program_name);
    printf("操作:\n");
    printf("  backup - 备份关键文件\n");
    printf("  clean  - 清理构建环境\n");
    printf("示例:\n");
    printf("  %s m28c backup\n", program_name);
    printf("  %s m28c clean\n", program_name);
}

// 调试函数：打印所有路径信息
void debug_print_paths(const char *model) {
    
    char *project_root = get_project_root();
    if (project_root) {
        log_info("项目根目录: %s", project_root);
        free(project_root);
    }
    
    char *backup_dir = get_backup_dir(model);
    if (backup_dir) {
        log_info("备份目录: %s", backup_dir);
        free(backup_dir);
    }
    
    char *source_dir = get_source_dir(model);
    if (source_dir) {
        log_info("源码目录: %s", source_dir);
        free(source_dir);
    }
    
    char *backup_list_path = malloc(1024);
    project_root = get_project_root();
    if (project_root) {
        snprintf(backup_list_path, 1024, "%s/configs/%s/backup_list.conf", project_root, model);
        log_info("备份列表文件: %s", backup_list_path);
        free(project_root);
    }
    free(backup_list_path);
    
    char cwd[1024];
    if (getcwd(cwd, sizeof(cwd)) != NULL) {
        log_info("当前工作目录: %s", cwd);
    } else {
        log_error("无法获取当前工作目录");
    }
    
    char path[1024];
    ssize_t len = readlink("/proc/self/exe", path, sizeof(path) - 1);
    if (len != -1) {
        path[len] = '\0';
        log_info("程序路径: %s", path);
    } else {
        log_error("无法获取程序路径");
    }
}

// 获取备份目录
char* get_backup_dir(const char *model) {
    char *project_root = get_project_root();
    if (project_root == NULL) {
        return NULL;
    }

    char *backup_dir = malloc(1024);
    snprintf(backup_dir, 1024, "%s/configs/%s/resource", project_root, model);
    free(project_root);
    
    return backup_dir;
}

// 获取源码目录
char* get_source_dir(const char *model) {
    char *project_root = get_project_root();
    if (project_root == NULL) {
        return NULL;
    }

    char *source_dir = malloc(1024);
    snprintf(source_dir, 1024, "%s/srcs/%s", project_root, model);
    free(project_root);
    
    return source_dir;
}

// 确认操作
int confirm_action(const char *message) {
    log_info("%s (y/N): ", message);
    fflush(stdout);
    
    char response[10];
    if (fgets(response, sizeof(response), stdin) == NULL) {
        return 0;
    }
    
    return (response[0] == 'y' || response[0] == 'Y');
}

// 备份关键文件
int backup_critical_files(const char *model, const char *backup_list_path) {
    log_info("开始备份关键文件");
    
    // 获取备份目录
    char *backup_dir = get_backup_dir(model);
    if (backup_dir == NULL) {
        log_error("无法获取备份目录");
        return 1;
    }
    
    // 获取源码目录
    char *source_dir = get_source_dir(model);
    if (source_dir == NULL) {
        free(backup_dir);
        log_error("无法获取源码目录");
        return 1;
    }
    
    // 创建备份目录（包括所有父目录）
    char mkdir_cmd[2048];
    snprintf(mkdir_cmd, sizeof(mkdir_cmd), "mkdir -p \"%s\"", backup_dir);
    
    log_info("执行命令: %s", mkdir_cmd);
    if (system(mkdir_cmd) != 0) {
        free(backup_dir);
        free(source_dir);
        log_error("无法创建备份目录");
        return 1;
    }
    
    // 检查目录是否成功创建
    if (access(backup_dir, F_OK) != 0) {
        free(backup_dir);
        free(source_dir);
        log_error("备份目录创建失败");
        return 1;
    }
    
    log_info("备份目录: %s", backup_dir);
    log_info("源码目录: %s", source_dir);
    
    // 读取备份列表文件
    FILE *backup_list = fopen(backup_list_path, "r");
    if (backup_list == NULL) {
        free(backup_dir);
        free(source_dir);
        log_error("无法打开备份列表文件");
        return 1;
    }
    
    char line[1024];
    int backup_count = 0;
    
    while (fgets(line, sizeof(line), backup_list) != NULL) {
        // 跳过注释行和空行
        if (line[0] == '#' || line[0] == '\n') {
            continue;
        }
        
        // 移除行尾的换行符
        line[strcspn(line, "\n")] = 0;
        
        // 构建源文件路径
        char source_path[2048];
        snprintf(source_path, sizeof(source_path), "%s/%s", source_dir, line);
        
        // 检查源文件是否存在
        if (access(source_path, F_OK) != 0) {
            char warning_msg[1024];
            snprintf(warning_msg, sizeof(warning_msg), "跳过不存在的文件: %s", line);
            log_warning(warning_msg);
            continue;
        }
        
        // 构建备份文件路径
        time_t now = time(NULL);
        struct tm *t = localtime(&now);
        char time_str[20];
        strftime(time_str, sizeof(time_str), "%Y%m%d-%H%M%S", t);
        
        char *dup_line = strdup(line);
        char *base_name = basename(dup_line);
        char backup_path[2048];
        snprintf(backup_path, sizeof(backup_path), "%s/%s.%s.bak", backup_dir, base_name, time_str);
        free(dup_line);
        
        // 执行备份
        char cmd[4096];
        snprintf(cmd, sizeof(cmd), "cp -v \"%s\" \"%s\"", source_path, backup_path);
        
        log_info("执行备份命令: %s", cmd);
        if (system(cmd) == 0) {
            char success_msg[1024];
            snprintf(success_msg, sizeof(success_msg), "备份成功: %s", backup_path);
            log_success(success_msg);
            backup_count++;
        } else {
            char error_msg[1024];
            snprintf(error_msg, sizeof(error_msg), "备份失败: %s", line);
            log_error(error_msg);
            fclose(backup_list);
            free(backup_dir);
            free(source_dir);
            return 1;
        }
    }
    
    fclose(backup_list);
    free(backup_dir);
    free(source_dir);
    
    if (backup_count > 0) {
        char success_msg[1024];
        snprintf(success_msg, sizeof(success_msg), "关键文件备份完成 (共备份 %d 个文件)", backup_count);
        log_success(success_msg);
    } else {
        log_warning("没有需要备份的文件");
    }
    
    return 0;
}

// 清理构建环境
int clean_build_environment(const char *model, const char *backup_list_path) {
    // 确认操作
    if (!confirm_action("您确定要清理构建环境吗? 这将删除所有自定义包并恢复配置文件")) {
        log_info("清理操作已取消");
        return 0;
    }
    
    log_info("开始清理构建环境");
    
    // 获取备份目录
    char *backup_dir = get_backup_dir(model);
    if (backup_dir == NULL) {
        log_error("无法获取备份目录");
        return 1;
    }
    
    // 获取源码目录
    char *source_dir = get_source_dir(model);
    if (source_dir == NULL) {
        free(backup_dir);
        log_error("无法获取源码目录");
        return 1;
    }
    
    int restored_files = 0;
    
    // 读取备份列表文件
    FILE *backup_list = fopen(backup_list_path, "r");
    if (backup_list == NULL) {
        free(backup_dir);
        free(source_dir);
        log_error("无法打开备份列表文件");
        return 1;
    }
    
    char line[1024];
    
    while (fgets(line, sizeof(line), backup_list) != NULL) {
        // 跳过注释行和空行
        if (line[0] == '#' || line[0] == '\n') {
            continue;
        }
        
        // 移除行尾的换行符
        line[strcspn(line, "\n")] = 0;
        
        // 构建目标文件路径
        char target_path[2048];
        snprintf(target_path, sizeof(target_path), "%s/%s", source_dir, line);
        
        // 查找最新的备份文件
        char backup_pattern[1024];
        char *dup_line = strdup(line);
        char *base_name = basename(dup_line);
        snprintf(backup_pattern, sizeof(backup_pattern), "%s/%s.*.bak", backup_dir, base_name);
        free(dup_line);
        
        // 使用ls命令查找最新的备份文件
        char cmd[4096];
        snprintf(cmd, sizeof(cmd), "ls -t %s 2>/dev/null | head -1", backup_pattern);
        
        FILE *ls_output = popen(cmd, "r");
        if (ls_output == NULL) {
            continue;
        }
        
        char latest_backup[1024];
        if (fgets(latest_backup, sizeof(latest_backup), ls_output) != NULL) {
            // 移除换行符
            latest_backup[strcspn(latest_backup, "\n")] = 0;
            
            // 恢复文件
            char restore_cmd[4096];
            snprintf(restore_cmd, sizeof(restore_cmd), "cp -f \"%s\" \"%s\"", latest_backup, target_path);
            
            printf("执行恢复命令: %s\n", restore_cmd);
            if (system(restore_cmd) == 0) {
                char success_msg[1024];
                snprintf(success_msg, sizeof(success_msg), "已恢复: %s", line);
                log_success(success_msg);
                restored_files++;
            } else {
                char error_msg[1024];
                snprintf(error_msg, sizeof(error_msg), "恢复失败: %s", line);
                log_error(error_msg);
            }
        }
        
        pclose(ls_output);
    }
    
    fclose(backup_list);
    free(backup_dir);
    free(source_dir);
    
    log_success("构建环境清理完成");
    
    char info_msg[1024];
    snprintf(info_msg, sizeof(info_msg), "已恢复 %d 个文件", restored_files);
    log_info(info_msg);
    
    return 0;
}