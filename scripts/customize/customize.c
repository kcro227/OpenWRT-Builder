#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdbool.h>
#include <unistd.h>
#include <getopt.h>
#include <libgen.h>
#include <linux/limits.h>

#include "customize.h"

// 打印使用说明
void print_usage(const char *program_name) {
    printf("用法: %s [选项] <配置文件>\n", program_name);
    printf("选项:\n");
    printf("  -h, --help          显示此帮助信息\n");
    printf("  -c, --context <ctx>  指定执行上下文 (init|build)\n");
    printf("  -s, --src-dir <dir>  指定源码目录 (默认: 项目根目录/srcs)\n");
    printf("  -r, --res-dir <dir>  指定资源目录 (默认: 配置文件所在目录/res)\n");
    printf("  -a, --author <name>  指定作者名称 (默认从配置文件读取)\n");
}

// 获取项目根目录
// char* get_project_root(const char *config_path) {
//     char config_dir[PATH_MAX];
//     strncpy(config_dir, config_path, sizeof(config_dir));
//     char *dir = dirname(config_dir);
    
//     // 向上查找包含Makefile的目录
//     for (int i = 0; i < 3; i++) {
//         char makefile_path[PATH_MAX];
//         snprintf(makefile_path, sizeof(makefile_path), "%s/Makefile", dir);
        
//         if (access(makefile_path, F_OK) == 0) {
//             return strdup(dir);
//         }
        
//         // 移动到父目录
//         char *parent = dirname(dir);
//         if (strcmp(parent, dir) == 0) {
//             break; // 已经到达根目录
//         }
//         strncpy(config_dir, parent, sizeof(config_dir));
//         dir = config_dir;
//     }
    
//     // 如果没找到Makefile，返回配置文件所在目录的上两级目录
//     strncpy(config_dir, config_path, sizeof(config_dir));
//     dir = dirname(config_dir); // configs/m28c
//     dir = dirname(dir);        // configs
//     dir = dirname(dir);        // 项目根目录
    
//     return strdup(dir);
// }

// 从配置文件中提取作者信息
char* extract_author_from_config(const char *config_path) {
    FILE *file = fopen(config_path, "r");
    if (file == NULL) {
        return NULL;
    }
    
    char line[1024];
    char *author = NULL;
    
    while (fgets(line, sizeof(line), file) != NULL) {
        // 查找AUTHOR定义
        if (strstr(line, "AUTHOR=") != NULL) {
            char *start = strchr(line, '"');
            if (start != NULL) {
                start++; // 跳过引号
                char *end = strchr(start, '"');
                if (end != NULL) {
                    *end = '\0';
                    author = strdup(start);
                    break;
                }
            }
            
            // 如果没有找到引号，尝试等号后面的内容
            start = strchr(line, '=');
            if (start != NULL) {
                start++; // 跳过等号
                // 跳过空格
                while (*start == ' ' || *start == '\t') start++;
                
                // 复制直到行尾或注释
                char *end = start;
                while (*end && *end != ' ' && *end != '\t' && *end != '#') end++;
                
                if (end > start) {
                    author = malloc(end - start + 1);
                    strncpy(author, start, end - start);
                    author[end - start] = '\0';
                    break;
                }
            }
        }
    }
    
    fclose(file);
    return author;
}

// 获取源码目录 - 默认为项目根目录下的srcs目录
char* get_source_dir(const char *project_root) {
    char *src_dir = malloc(PATH_MAX);
    snprintf(src_dir, PATH_MAX, "%s/srcs", project_root);
    return src_dir;
}

// 获取资源目录
char* get_resource_dir(const char *config_path) {
    char config_dir[PATH_MAX];
    strncpy(config_dir, config_path, sizeof(config_dir));
    char *dir = dirname(config_dir);
    
    // 检查是否存在res子目录
    char res_path[PATH_MAX];
    snprintf(res_path, sizeof(res_path), "%s/res", dir);
    
    if (access(res_path, F_OK) == 0) {
        return strdup(res_path);
    }
    
    // 如果没有res子目录，使用配置文件所在目录
    return strdup(dir);
}

int main(int argc, char *argv[]) {
    char *config_file = NULL;
    ContextType context = CTX_UNKNOWN;
    char *src_dir = NULL;
    char *res_dir = NULL;
    char *author = NULL;
    char *project_root = NULL;
    
    // 标记哪些指针是动态分配的
    bool src_dir_allocated = false;
    bool res_dir_allocated = false;
    bool author_allocated = false;
    
    // 解析命令行参数
    static struct option long_options[] = {
        {"help", no_argument, 0, 'h'},
        {"context", required_argument, 0, 'c'},
        {"src-dir", required_argument, 0, 's'},
        {"res-dir", required_argument, 0, 'r'},
        {"author", required_argument, 0, 'a'},
        {0, 0, 0, 0}
    };
    
    int opt;
    while ((opt = getopt_long(argc, argv, "hc:s:r:a:", long_options, NULL)) != -1) {
        switch (opt) {
            case 'h':
                print_usage(argv[0]);
                return 0;
                
            case 'c':
                context = parse_context(optarg);
                if (context == CTX_UNKNOWN) {
                    log_error("错误: 无效的上下文 %s", optarg);
                    return 1;
                }
                break;
                
            case 's':
                src_dir = optarg;
                src_dir_allocated = false;
                break;
                
            case 'r':
                res_dir = optarg;
                res_dir_allocated = false;
                break;
                
            case 'a':
                author = optarg;
                author_allocated = false;
                break;
                
            default:
                print_usage(argv[0]);
                return 1;
        }
    }
    
    if (optind >= argc) {
        log_error("错误: 需要指定配置文件");
        print_usage(argv[0]);
        return 1;
    }
    
    config_file = argv[optind];
    
    if (context == CTX_UNKNOWN) {
        log_error("错误: 需要指定执行上下文");
        print_usage(argv[0]);
        return 1;
    }
    
    // 自动推断目录路径
    // project_root = get_project_root(config_file);
    project_root = get_project_root();
    
    if (src_dir == NULL) {
        src_dir = get_source_dir(project_root);
        src_dir_allocated = true;
    }
    
    if (res_dir == NULL) {
        res_dir = get_resource_dir(config_file);
        res_dir_allocated = true;
    }
    
    if (author == NULL) {
        author = extract_author_from_config(config_file);
        if (author == NULL) {
            author = "Unknown";
            author_allocated = false;
        } else {
            author_allocated = true;
        }
    }
    
    log_info("项目根目录: %s", project_root);
    log_info("源码目录: %s", src_dir);
    log_info("资源目录: %s", res_dir);
    log_info("作者: %s", author);
    
    // 解析配置文件和变量
    Rule *rules = NULL;
    char **variables = NULL;
    int rule_count = 0;
    int var_count = 0;
    
    if (parse_customize_config(config_file, &rules, &rule_count, &variables, &var_count) != 0) {
        log_error("错误: 解析配置文件失败");
        free(project_root);
        if (src_dir_allocated) free(src_dir);
        if (res_dir_allocated) free(res_dir);
        if (author_allocated) free(author);
        return 1;
    }
    
    if (rule_count == 0) {
        log_info("没有找到任何规则");
        free_rules_and_vars(rules, rule_count, variables, var_count);
        free(project_root);
        if (src_dir_allocated) free(src_dir);
        if (res_dir_allocated) free(res_dir);
        if (author_allocated) free(author);
        return 0;
    }
    
    // 执行规则
    int result = execute_rules(rules, rule_count, context, src_dir, res_dir, author, variables, var_count);
    
    // 释放内存
    free_rules_and_vars(rules, rule_count, variables, var_count);
    free(project_root);
    if (src_dir_allocated) free(src_dir);
    if (res_dir_allocated) free(res_dir);
    if (author_allocated) free(author);
    
    return result;
}