#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdarg.h>
#include <sys/stat.h>
#include <dirent.h>
#include <unistd.h>
#include <errno.h>
#include <libgen.h>
#include <limits.h>
#include <sys/ioctl.h>

#include "utils.h"
#include "color.h"

// 错误日志
void log_error(const char *format, ...) {
    va_list args;
    va_start(args, format);
    
    printf("%s错误: " LOG_ERROR, COLOR_RESET);
    vprintf(format, args);
    printf("%s\n", COLOR_RESET);
    
    va_end(args);
}

// 警告日志
void log_warning(const char *format, ...) {
    va_list args;
    va_start(args, format);
    
    printf("%s警告: " LOG_WARNING, COLOR_RESET);
    vprintf(format, args);
    printf("%s\n", COLOR_RESET);
    
    va_end(args);
}

// 信息日志
void log_info(const char *format, ...) {
    va_list args;
    va_start(args, format);
    
    printf("%s信息: " LOG_INFO, COLOR_RESET);
    vprintf(format, args);
    printf("%s\n", COLOR_RESET);
    
    va_end(args);
}

// 成功日志
void log_success(const char *format, ...) {
    va_list args;
    va_start(args, format);
    
    printf("%s" LOG_SUCCESS, COLOR_RESET);
    vprintf(format, args);
    printf("%s\n", COLOR_RESET);
    
    va_end(args);
}

// 检查文件是否存在
bool file_exists(const char *path) {
    struct stat st;
    return (stat(path, &st) == 0 && S_ISREG(st.st_mode));
}

// 检查目录是否存在
bool dir_exists(const char *path) {
    struct stat st;
    return (stat(path, &st) == 0 && S_ISDIR(st.st_mode));
}

// 创建目录
int create_dir(const char *path) {
    char cmd[PATH_MAX];
    snprintf(cmd, sizeof(cmd), "mkdir -p \"%s\"", path);
    return system(cmd);
}

// 复制文件
int copy_file(const char *src, const char *dst) {
    char cmd[PATH_MAX * 2];
    snprintf(cmd, sizeof(cmd), "cp -f \"%s\" \"%s\"", src, dst);
    return system(cmd);
}

// 复制目录
int copy_dir(const char *src, const char *dst) {
    char cmd[PATH_MAX * 2];
    snprintf(cmd, sizeof(cmd), "cp -rf \"%s\" \"%s\"", src, dst);
    return system(cmd);
}

// 删除文件或目录
int remove_file_or_dir(const char *path) {
    char cmd[PATH_MAX];
    if (dir_exists(path)) {
        snprintf(cmd, sizeof(cmd), "rm -rf \"%s\"", path);
    } else if (file_exists(path)) {
        snprintf(cmd, sizeof(cmd), "rm -f \"%s\"", path);
    } else {
        return 0; // 不存在，无需删除
    }
    return system(cmd);
}

// 去除字符串首尾的空白字符
char* trim_whitespace(char *str) {
    if (str == NULL) return NULL;
    
    char *end;
    
    // 去除前导空白字符
    while (*str && (*str == ' ' || *str == '\t' || *str == '\n' || *str == '\r')) {
        str++;
    }
    
    if (*str == 0) return str;
    
    // 去除尾部空白字符
    end = str + strlen(str) - 1;
    while (end > str && (*end == ' ' || *end == '\t' || *end == '\n' || *end == '\r')) {
        end--;
    }
    
    // 写入新的终止符
    *(end + 1) = '\0';
    
    return str;
}

int ensure_directory_exists(const char *path) {
    struct stat st = {0};
    if (stat(path, &st) == 0) {
        return 0; // 目录已存在
    }
    
    // 创建目录（包括父目录）
    char cmd[512];
    snprintf(cmd, sizeof(cmd), "mkdir -p \"%s\"", path);
    int result = system(cmd);
    
    if (result == 0) {
        log_success("创建目录: %s", path);
    } else {
        log_error("创建目录失败: %s", path);
    }
    
    return result;
}


// 获取终端宽度
int get_terminal_width(void) {
    struct winsize w;
    if (ioctl(STDOUT_FILENO, TIOCGWINSZ, &w) == -1) {
        // 如果无法获取终端宽度，返回默认值
        return 80;
    }
    return w.ws_col;
}

// 获取项目根目录
char* get_project_root(void) {
    char cwd[PATH_MAX];
    if (getcwd(cwd, sizeof(cwd)) == NULL) {
        perror("getcwd() error");
        return NULL;
    }
    
    // 检查当前目录或父目录中是否有Makefile文件
    char current_dir[PATH_MAX];
    strncpy(current_dir, cwd, sizeof(current_dir));
    
    for (int depth = 0; depth < 10; depth++) {
        char path[PATH_MAX];
        snprintf(path, sizeof(path), "%s/Makefile", current_dir);
        
        if (access(path, F_OK) == 0) {
            return strdup(current_dir);
        }
        
        // 移动到父目录
        char *parent_dir = dirname(current_dir);
        if (strcmp(parent_dir, current_dir) == 0) {
            break; // 已经到达根目录
        }
        strncpy(current_dir, parent_dir, sizeof(current_dir));
    }
    
    return strdup("."); // 默认返回当前目录
}