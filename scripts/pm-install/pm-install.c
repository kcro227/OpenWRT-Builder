#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdbool.h>
#include <unistd.h>
#include <sys/stat.h>
#include <dirent.h>
#include <errno.h>
#include <libgen.h>
#include <limits.h>

#include "../utils/utils.h"
#include "../utils/color.h"

#define MAX_LINE_LENGTH 256
#define MAX_PACKAGES 100

// 打印使用说明
void print_usage(const char *program_name) {
    printf("%s用法: %s [选项] <型号> <作者名>%s\n", STYLE_BOLD, program_name, COLOR_RESET);
    printf("选项:\n");
    printf("  -h, --help     显示此帮助信息\n");
    printf("  -l, --list     列出指定型号的所有软件包\n");
    printf("  -c, --clean    清除已安装的软件包\n");
    printf("  -i, --install  安装软件包（默认操作）\n");
    printf("参数:\n");
    printf("  型号:   指定要安装软件包的型号名称 (如: m28c, xr30)\n");
    printf("  作者名: 软件包作者名称，用于定位 packages/作者名/ 目录\n");
}

// 读取packages.list文件
int read_package_list(const char *filename, char packages[][PATH_MAX], int *package_count) {
    FILE *file = fopen(filename, "r");
    if (file == NULL) {
        log_error("无法打开文件 %s: %s", filename, strerror(errno));
        return -1;
    }
    
    char line[MAX_LINE_LENGTH];
    *package_count = 0;
    int line_num = 0;
    
    while (fgets(line, sizeof(line), file) != NULL && *package_count < MAX_PACKAGES) {
        line_num++;
        
        // 跳过注释行和空行
        if (line[0] == '#' || line[0] == '\n') {
            continue;
        }
        
        // 移除行尾的换行符并去除空白字符
        line[strcspn(line, "\n")] = 0;
        char *trimmed_line = trim_whitespace(line);
        
        if (strlen(trimmed_line) > 0) {
            strncpy(packages[*package_count], trimmed_line, PATH_MAX - 1);
            (*package_count)++;
        }
    }
    
    fclose(file);
    return 0;
}

// 列出指定型号的所有软件包
int list_packages(const char *model, const char *author) {
    char list_path[PATH_MAX];
    snprintf(list_path, sizeof(list_path), "configs/%s/packages.list", model);
    
    if (!file_exists(list_path)) {
        log_error("型号 %s 的 packages.list 文件不存在: %s", model, list_path);
        return -1;
    }
    
    char packages[MAX_PACKAGES][PATH_MAX];
    int package_count = 0;
    
    if (read_package_list(list_path, packages, &package_count) != 0) {
        return -1;
    }
    
    if (package_count == 0) {
        log_info("型号 %s 没有定义任何软件包", model);
        return 0;
    }
    
    // 获取终端宽度
    int terminal_width = get_terminal_width();
    int name_width = terminal_width * 2 / 5;
    int path_width = terminal_width - name_width - 5;
    
    printf("%s型号 %s (作者: %s) 的软件包列表:%s\n", STYLE_BOLD, model, author, COLOR_RESET);
    printf("%s%-*s %-*s%s\n", STYLE_UNDERLINE, 
           name_width, "软件包名称", 
           path_width, "目标路径", 
           COLOR_RESET);
    
    for (int i = 0; i < package_count; i++) {
        char dst_path[PATH_MAX];
        snprintf(dst_path, sizeof(dst_path), "srcs/%s/%s", model, packages[i]);
        
        printf("%-*s %-*s\n", 
               name_width, packages[i], 
               path_width, dst_path);
    }
    
    return 0;
}

// 安装指定型号的软件包
int install_packages(const char *model, const char *author) {
    char list_path[PATH_MAX];
    snprintf(list_path, sizeof(list_path), "configs/%s/packages.list", model);
    
    if (!file_exists(list_path)) {
        log_error("型号 %s 的 packages.list 文件不存在: %s", model, list_path);
        return -1;
    }
    
    char packages[MAX_PACKAGES][PATH_MAX];
    int package_count = 0;
    
    if (read_package_list(list_path, packages, &package_count) != 0) {
        return -1;
    }
    
    if (package_count == 0) {
        log_info("型号 %s 没有定义任何软件包", model);
        return 0;
    }
    
    // 创建目标目录
    char target_dir[PATH_MAX];
    snprintf(target_dir, sizeof(target_dir), "srcs/%s/package", model);
    
    if (!dir_exists(target_dir)) {
        log_info("创建目标目录: %s", target_dir);
        if (create_dir(target_dir) != 0) {
            log_error("创建目录失败: %s", target_dir);
            return -1;
        }
    }
    
    int success_count = 0;
    int fail_count = 0;
    
    for (int i = 0; i < package_count; i++) {
        char src_path[PATH_MAX];
        char dst_path[PATH_MAX];
        
        // 源路径不包含作者名，目标路径包含作者名
        snprintf(src_path, sizeof(src_path), "packages/%s", packages[i]);
        snprintf(dst_path, sizeof(dst_path), "%s/%s/%s", target_dir, author, packages[i]);
        
        // 获取目标目录的父目录
        char dst_parent[PATH_MAX];
        strncpy(dst_parent, dst_path, sizeof(dst_parent));
        char *parent_dir = dirname(dst_parent);
        
        // 创建目标父目录
        if (!dir_exists(parent_dir)) {
            if (create_dir(parent_dir) != 0) {
                log_error("创建目录失败: %s", parent_dir);
                fail_count++;
                continue;
            }
        }
        
        if (dir_exists(src_path)) {
            // 复制目录
            log_info("复制目录: %s -> %s", src_path, dst_path);
            if (copy_dir(src_path, dst_path) == 0) {
                log_success("成功复制目录: %s", packages[i]);
                success_count++;
            } else {
                log_error("复制目录失败: %s", packages[i]);
                fail_count++;
            }
        } else if (file_exists(src_path)) {
            // 复制文件
            log_info("复制文件: %s -> %s", src_path, dst_path);
            if (copy_file(src_path, dst_path) == 0) {
                log_success("成功复制文件: %s", packages[i]);
                success_count++;
            } else {
                log_error("复制文件失败: %s", packages[i]);
                fail_count++;
            }
        } else {
            log_error("软件包不存在: %s", src_path);
            fail_count++;
        }
    }
    
    if (fail_count == 0) {
        log_success("所有软件包安装成功 (%d 个)", success_count);
        return 0;
    } else {
        log_error("软件包安装完成，成功 %d 个，失败 %d 个", success_count, fail_count);
        return 1;
    }
}

// 清除已安装的软件包
int clean_packages(const char *model, const char *author) {
    char list_path[PATH_MAX];
    snprintf(list_path, sizeof(list_path), "configs/%s/packages.list", model);
    
    if (!file_exists(list_path)) {
        log_error("型号 %s 的 packages.list 文件不存在: %s", model, list_path);
        return -1;
    }
    
    char packages[MAX_PACKAGES][PATH_MAX];
    int package_count = 0;
    
    if (read_package_list(list_path, packages, &package_count) != 0) {
        return -1;
    }
    
    if (package_count == 0) {
        log_info("型号 %s 没有定义任何软件包", model);
        return 0;
    }
    
    int success_count = 0;
    int fail_count = 0;
    
    for (int i = 0; i < package_count; i++) {
        char dst_path[PATH_MAX];
        snprintf(dst_path, sizeof(dst_path), "srcs/%s/%s/%s", model, author, packages[i]);
        
        if (file_exists(dst_path) || dir_exists(dst_path)) {
            log_info("删除: %s", dst_path);
            if (remove_file_or_dir(dst_path) == 0) {
                log_success("成功删除: %s", packages[i]);
                success_count++;
            } else {
                log_error("删除失败: %s", packages[i]);
                fail_count++;
            }
        } else {
            log_info("软件包不存在，跳过: %s", dst_path);
        }
    }
    
    // 检查目标目录是否为空，如果为空则删除
    char target_dir[PATH_MAX];
    snprintf(target_dir, sizeof(target_dir), "srcs/%s/%s", model, author);
    
    if (dir_exists(target_dir)) {
        DIR *dir = opendir(target_dir);
        if (dir) {
            struct dirent *entry;
            int file_count = 0;
            
            while ((entry = readdir(dir)) != NULL) {
                if (strcmp(entry->d_name, ".") != 0 && strcmp(entry->d_name, "..") != 0) {
                    file_count++;
                    break;
                }
            }
            closedir(dir);
            
            if (file_count == 0) {
                log_info("目录为空，删除: %s", target_dir);
                remove_file_or_dir(target_dir);
            }
        }
    }
    
    // 检查型号目录是否为空，如果为空则删除
    char model_dir[PATH_MAX];
    snprintf(model_dir, sizeof(model_dir), "srcs/%s", model);
    
    if (dir_exists(model_dir)) {
        DIR *dir = opendir(model_dir);
        if (dir) {
            struct dirent *entry;
            int file_count = 0;
            
            while ((entry = readdir(dir)) != NULL) {
                if (strcmp(entry->d_name, ".") != 0 && strcmp(entry->d_name, "..") != 0) {
                    file_count++;
                    break;
                }
            }
            closedir(dir);
            
            if (file_count == 0) {
                log_info("型号目录为空，删除: %s", model_dir);
                remove_file_or_dir(model_dir);
            }
        }
    }
    
    if (fail_count == 0) {
        log_success("所有软件包清除成功 (%d 个)", success_count);
        return 0;
    } else {
        log_error("软件包清除完成，成功 %d 个，失败 %d 个", success_count, fail_count);
        return 1;
    }
}

int main(int argc, char *argv[]) {
    char *model = NULL;
    char *author = NULL;
    bool list_mode = false;
    bool clean_mode = false;
    bool install_mode = false;
    
    // 解析命令行参数
    for (int i = 1; i < argc; i++) {
        if (strcmp(argv[i], "-h") == 0 || strcmp(argv[i], "--help") == 0) {
            print_usage(argv[0]);
            return 0;
        } else if (strcmp(argv[i], "-l") == 0 || strcmp(argv[i], "--list") == 0) {
            list_mode = true;
        } else if (strcmp(argv[i], "-c") == 0 || strcmp(argv[i], "--clean") == 0) {
            clean_mode = true;
        } else if (strcmp(argv[i], "-i") == 0 || strcmp(argv[i], "--install") == 0) {
            install_mode = true;
        } else if (argv[i][0] != '-') {
            if (model == NULL) {
                model = argv[i];
            } else if (author == NULL) {
                author = argv[i];
            } else {
                log_error("多余的参数: %s", argv[i]);
                print_usage(argv[0]);
                return 1;
            }
        } else {
            log_error("未知参数: %s", argv[i]);
            print_usage(argv[0]);
            return 1;
        }
    }
    
    // 默认操作为安装
    if (!list_mode && !clean_mode && !install_mode) {
        install_mode = true;
    }
    
    if (model == NULL) {
        log_error("需要指定型号名称");
        print_usage(argv[0]);
        return 1;
    }
    
    if (author == NULL) {
        log_error("需要指定作者名称");
        print_usage(argv[0]);
        return 1;
    }
    
    if (list_mode) {
        return list_packages(model, author);
    } else if (clean_mode) {
        return clean_packages(model, author);
    } else if (install_mode) {
        return install_packages(model, author);
    }
    
    return 0;
}