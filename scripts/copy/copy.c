#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <dirent.h>
#include <sys/stat.h>
#include <unistd.h>
#include <time.h>
#include <glob.h>
#include <errno.h>
#include <fcntl.h>
#include <ctype.h>
#include <getopt.h>
#include "../utils/utils.h"

#define MAX_LINE_LENGTH 1024
#define MAX_PATH_LENGTH 4096
#define MAX_VARIABLES 100
#define MAX_RULES 1000

// 日志级别
typedef enum {
    LOG_ERROR,
    LOG_WARNING,
    LOG_INFO,
    LOG_SUCCESS
} LogLevel;

// 变量结构
typedef struct {
    char name[50];
    char value[MAX_PATH_LENGTH];
} Variable;

// 复制规则结构
typedef struct {
    int id;
    char source[MAX_PATH_LENGTH];
    char target[MAX_PATH_LENGTH];
} CopyRule;

// 全局变量
Variable variables[MAX_VARIABLES];
int var_count = 0;
CopyRule rules[MAX_RULES];
int rule_count = 0;
int total_files = 0;
int copied_files = 0;

// 日志函数
void log_message(LogLevel level, const char* message, const char* module) {
    const char* level_str[] = {"ERROR", "WARNING", "INFO", "SUCCESS"};
    time_t now = time(NULL);
    char timestr[20];
    strftime(timestr, sizeof(timestr), "%Y-%m-%d %H:%M:%S", localtime(&now));
    
    printf("[%s] [%s] [%s] %s\n", timestr, level_str[level], module, message);
}

// 去除字符串首尾空白字符
// char* trim_whitespace(char* str) {
//     char* end;
    
//     // 去除前导空白
//     while(isspace((unsigned char)*str)) str++;
    
//     if(*str == 0) return str;
    
//     // 去除尾部空白
//     end = str + strlen(str) - 1;
//     while(end > str && isspace((unsigned char)*end)) end--;
    
//     // 写入新的空字符终止符
//     *(end+1) = 0;
    
//     return str;
// }

// 检查文件是否存在
// int file_exists(const char* path) {
//     struct stat st;
//     return stat(path, &st) == 0;
// }

// 检查是否是目录
int is_directory(const char* path) {
    struct stat st;
    if (stat(path, &st) != 0) return 0;
    return S_ISDIR(st.st_mode);
}

// 创建目录（包括父目录）
int create_directory(const char* path) {
    char tmp[MAX_PATH_LENGTH];
    char *p = NULL;
    size_t len;
    
    snprintf(tmp, sizeof(tmp), "%s", path);
    len = strlen(tmp);
    
    if (tmp[len - 1] == '/') {
        tmp[len - 1] = 0;
    }
    
    for (p = tmp + 1; *p; p++) {
        if (*p == '/') {
            *p = 0;
            if (mkdir(tmp, 0755) != 0 && errno != EEXIST) {
                return -1;
            }
            *p = '/';
        }
    }
    
    if (mkdir(tmp, 0755) != 0 && errno != EEXIST) {
        return -1;
    }
    
    return 0;
}

// 递归删除目录
int remove_directory(const char* path) {
    char command[MAX_PATH_LENGTH + 10];
    snprintf(command, sizeof(command), "rm -rf \"%s\"", path);
    
    log_message(LOG_INFO, command, "删除目录");
    
    int result = system(command);
    if (result != 0) {
        log_message(LOG_ERROR, "删除目录失败", "删除操作");
        return -1;
    }
    
    return 0;
}

// 执行系统命令并返回结果
int execute_command(const char* command) {
    return system(command);
}

// 使用系统命令复制文件或目录（先删除目标，再复制）
int copy_with_system_command(const char* src, const char* dst) {
    char copy_command[MAX_PATH_LENGTH * 2 + 50];
    
    // 确保目标目录的父目录存在
    char* last_slash = strrchr(dst, '/');
    if (last_slash) {
        *last_slash = 0;
        if (create_directory(dst) != 0) {
            log_message(LOG_ERROR, "创建目标目录失败", "复制操作");
            return -1;
        }
        *last_slash = '/';
    }
    
    // 如果目标存在，先删除
    if (file_exists(dst)) {
        log_message(LOG_WARNING, "目标已存在，正在删除...", "复制操作");
        if (remove_directory(dst) != 0) {
            log_message(LOG_ERROR, "删除已存在目标失败", "复制操作");
            return -1;
        }
    }
    
    // 构建复制命令
    if (is_directory(src)) {
        // 复制目录
        snprintf(copy_command, sizeof(copy_command), "cp -r \"%s\" \"%s\"", src, dst);
    } else {
        // 复制文件
        snprintf(copy_command, sizeof(copy_command), "cp \"%s\" \"%s\"", src, dst);
    }
    
    log_message(LOG_INFO, copy_command, "执行复制命令");
    
    // 执行复制命令
    int result = execute_command(copy_command);
    if (result != 0) {
        log_message(LOG_ERROR, "复制命令执行失败", "复制操作");
        return -1;
    }
    
    return 0;
}

// 变量替换函数
void replace_variables(char* str) {
    for (int i = 0; i < var_count; i++) {
        char pattern[60];
        snprintf(pattern, sizeof(pattern), "${%s}", variables[i].name);
        
        char* pos = strstr(str, pattern);
        while (pos != NULL) {
            // 计算新字符串长度
            size_t new_len = strlen(str) - strlen(pattern) + strlen(variables[i].value) + 1;
            if (new_len > MAX_PATH_LENGTH) {
                log_message(LOG_ERROR, "变量替换后字符串过长", "变量替换");
                return;
            }
            
            // 创建新字符串
            char new_str[MAX_PATH_LENGTH];
            size_t prefix_len = pos - str;
            
            strncpy(new_str, str, prefix_len);
            new_str[prefix_len] = 0;
            
            strcat(new_str, variables[i].value);
            strcat(new_str, pos + strlen(pattern));
            
            // 复制回原字符串
            strncpy(str, new_str, MAX_PATH_LENGTH);
            
            // 查找下一个匹配
            pos = strstr(str, pattern);
        }
    }
}

// 解析配置文件
int parse_config_file(const char* config_path) {
    FILE* fp = fopen(config_path, "r");
    if (!fp) {
        log_message(LOG_ERROR, "无法打开配置文件", "配置解析");
        return -1;
    }
    
    char line[MAX_LINE_LENGTH];
    
    while (fgets(line, sizeof(line), fp)) {
        // 移除换行符
        line[strcspn(line, "\n")] = 0;
        
        // 跳过空行和注释
        if (strlen(trim_whitespace(line)) == 0 || line[0] == '#') {
            continue;
        }
        
        // 检查是否是变量定义
        char* equals = strchr(line, '=');
        if (equals != NULL) {
            // 提取变量名和值
            char* name_start = line;
            char* value_start = equals + 1;
            
            // 变量名在等号前
            *equals = 0;
            char* name = trim_whitespace(name_start);
            
            // 值在等号后，可能被引号包围
            char* value = trim_whitespace(value_start);
            
            // 去除值周围的引号
            if (value[0] == '"' && value[strlen(value)-1] == '"') {
                value[strlen(value)-1] = 0;
                value++;
            }
            
            // 保存变量
            if (var_count < MAX_VARIABLES) {
                strncpy(variables[var_count].name, name, sizeof(variables[var_count].name));
                strncpy(variables[var_count].value, value, sizeof(variables[var_count].value));
                var_count++;
                
                log_message(LOG_INFO, name, "变量定义");
                log_message(LOG_INFO, value, "变量值");
            } else {
                log_message(LOG_WARNING, "变量数量超过最大值", "配置解析");
            }
            
            continue;
        }
        
        // 检查是否是复制规则
        char* first_semicolon = strchr(line, ';');
        if (first_semicolon != NULL) {
            char* second_semicolon = strchr(first_semicolon + 1, ';');
            if (second_semicolon != NULL) {
                // 提取序号、源路径和目标路径
                *first_semicolon = 0;
                *second_semicolon = 0;
                
                int id = atoi(trim_whitespace(line));
                char* source = trim_whitespace(first_semicolon + 1);
                char* target = trim_whitespace(second_semicolon + 1);
                
                // 保存规则
                if (rule_count < MAX_RULES) {
                    rules[rule_count].id = id;
                    strncpy(rules[rule_count].source, source, sizeof(rules[rule_count].source));
                    strncpy(rules[rule_count].target, target, sizeof(rules[rule_count].target));
                    rule_count++;
                    
                    log_message(LOG_INFO, source, "源路径");
                    log_message(LOG_INFO, target, "目标路径");
                } else {
                    log_message(LOG_WARNING, "规则数量超过最大值", "配置解析");
                }
            }
        }
    }
    
    fclose(fp);
    
    // 对所有规则进行变量替换
    for (int i = 0; i < rule_count; i++) {
        replace_variables(rules[i].source);
        replace_variables(rules[i].target);
        
        log_message(LOG_INFO, rules[i].source, "替换后源路径");
        log_message(LOG_INFO, rules[i].target, "替换后目标路径");
    }
    
    return 0;
}

// 更新进度显示
void update_progress(int current, int total, const char* message) {
    int width = 50;
    float percentage = (float)current / total;
    int pos = width * percentage;
    
    printf("\r%s [", message);
    for (int i = 0; i < width; i++) {
        if (i < pos) printf("=");
        else if (i == pos) printf(">");
        else printf(" ");
    }
    printf("] %d/%d", current, total);
    fflush(stdout);
    
    if (current == total) printf("\n");
}

// 执行复制操作
int execute_copy_rule(const CopyRule* rule, const char* marker, const char* date) {
    int files_copied = 0;
    
    // 使用glob扩展源路径
    glob_t glob_result;
    if (glob(rule->source, GLOB_TILDE, NULL, &glob_result) == 0) {
        for (size_t i = 0; i < glob_result.gl_pathc; i++) {
            const char* source_path = glob_result.gl_pathv[i];
            
            // 确定目标路径
            char target_path[MAX_PATH_LENGTH];
            
            // 添加日期目录
            char dated_target[MAX_PATH_LENGTH];
            snprintf(dated_target, sizeof(dated_target), "%s/%s", rule->target, date);
            
            // 如果指定了标记，添加到目标路径
            if (marker && marker[0] != '\0') {
                snprintf(target_path, sizeof(target_path), "%s/%s", dated_target, marker);
            } else {
                // 修复：不要添加额外的斜杠
                strncpy(target_path, dated_target, sizeof(target_path));
            }
            
            // 确定最终的目标路径
            char final_target_path[MAX_PATH_LENGTH];
            const char* filename = strrchr(source_path, '/');
            if (filename) filename++;
            else filename = source_path;
            
            // 检查目标路径是否以斜杠结尾
            size_t target_len = strlen(target_path);
            if (target_len > 0 && target_path[target_len - 1] == '/') {
                snprintf(final_target_path, sizeof(final_target_path), "%s%s", target_path, filename);
            } else {
                snprintf(final_target_path, sizeof(final_target_path), "%s/%s", target_path, filename);
            }
            
            // 使用系统命令复制
            if (copy_with_system_command(source_path, final_target_path) == 0) {
                char success_msg[MAX_PATH_LENGTH + 50];
                snprintf(success_msg, sizeof(success_msg), "复制成功: %s -> %s", 
                        source_path, final_target_path);
                log_message(LOG_SUCCESS, success_msg, "复制操作");
                files_copied++;
            } else {
                char error_msg[MAX_PATH_LENGTH + 50];
                snprintf(error_msg, sizeof(error_msg), "复制失败: %s -> %s", 
                        source_path, final_target_path);
                log_message(LOG_ERROR, error_msg, "复制操作");
            }
            
            total_files++;
        }
        globfree(&glob_result);
    } else {
        log_message(LOG_ERROR, "无法扩展源路径", "复制操作");
    }
    
    copied_files += files_copied;
    return files_copied;
}

// 解析规则ID参数
int parse_rule_ids(const char* rule_str, int* rule_ids, int max_ids) {
    if (strcmp(rule_str, "all") == 0) {
        // 特殊处理"all"
        return -1;
    }
    
    char* token;
    char* rest = (char*)rule_str;
    int count = 0;
    
    while ((token = strtok_r(rest, ",", &rest)) && count < max_ids) {
        // 检查是否是范围
        char* dash = strchr(token, '-');
        if (dash) {
            *dash = 0;
            int start = atoi(token);
            int end = atoi(dash + 1);
            
            for (int i = start; i <= end; i++) {
                if (count < max_ids) {
                    rule_ids[count++] = i;
                }
            }
        } else {
            rule_ids[count++] = atoi(token);
        }
    }
    
    return count;
}

// 主复制函数
int copy_build_artifacts(const char* config_path, const char* rule_str, const char* marker, const char* date) {
    log_message(LOG_INFO, "开始复制构建产物", "构建产物");
    
    if (date && date[0] != '\0') {
        char date_msg[100];
        snprintf(date_msg, sizeof(date_msg), "使用日期目录: %s", date);
        log_message(LOG_INFO, date_msg, "构建产物");
    }
    
    if (marker && marker[0] != '\0') {
        char marker_msg[100];
        snprintf(marker_msg, sizeof(marker_msg), "使用标记目录: %s", marker);
        log_message(LOG_INFO, marker_msg, "构建产物");
    }
    
    time_t start_time = time(NULL);
    
    if (!file_exists(config_path)) {
        log_message(LOG_ERROR, "复制配置文件不存在", "构建产物");
        return 1;
    }
    
    // 解析配置文件
    if (parse_config_file(config_path) != 0) {
        log_message(LOG_ERROR, "解析配置文件失败", "构建产物");
        return 1;
    }
    
    if (rule_count == 0) {
        log_message(LOG_WARNING, "配置文件中没有找到复制规则", "构建产物");
        return 1;
    }
    
    // 解析规则ID
    int rule_ids[100];
    int rule_id_count = 0;
    int execute_all = 0;
    
    if (rule_str == NULL || strlen(rule_str) == 0) {
        // 默认执行规则0
        rule_ids[0] = 0;
        rule_id_count = 1;
        log_message(LOG_INFO, "执行默认规则 (ID: 0)", "构建产物");
    } else {
        rule_id_count = parse_rule_ids(rule_str, rule_ids, 100);
        
        if (rule_id_count == -1) {
            execute_all = 1;
            log_message(LOG_INFO, "执行所有规则", "构建产物");
        } else if (rule_id_count == 0) {
            log_message(LOG_WARNING, "未指定有效的规则ID", "构建产物");
            return 1;
        } else {
            char rule_msg[100];
            snprintf(rule_msg, sizeof(rule_msg), "执行规则: %s", rule_str);
            log_message(LOG_INFO, rule_msg, "构建产物");
        }
    }
    
    // 执行复制操作
    if (execute_all) {
        // 执行所有规则
        for (int i = 0; i < rule_count; i++) {
            char rule_msg[50];
            snprintf(rule_msg, sizeof(rule_msg), "执行规则 %d", rules[i].id);
            log_message(LOG_INFO, rule_msg, "构建产物");
            
            execute_copy_rule(&rules[i], marker, date);
        }
    } else {
        // 执行指定规则
        for (int i = 0; i < rule_id_count; i++) {
            int rule_found = 0;
            
            for (int j = 0; j < rule_count; j++) {
                if (rules[j].id == rule_ids[i]) {
                    char rule_msg[50];
                    snprintf(rule_msg, sizeof(rule_msg), "执行规则 %d", rules[j].id);
                    log_message(LOG_INFO, rule_msg, "构建产物");
                    
                    execute_copy_rule(&rules[j], marker, date);
                    rule_found = 1;
                    break;
                }
            }
            
            if (!rule_found) {
                char warn_msg[50];
                snprintf(warn_msg, sizeof(warn_msg), "未找到规则 ID: %d", rule_ids[i]);
                log_message(LOG_WARNING, warn_msg, "构建产物");
            }
        }
    }
    
    time_t end_time = time(NULL);
    int duration = (int)(end_time - start_time);
    
    // 最终进度更新
    update_progress(total_files, total_files, "复制完成");
    
    if (copied_files > 0) {
        char success_msg[100];
        snprintf(success_msg, sizeof(success_msg), 
                "构建产物复制完成 (总计: %d/%d, 耗时: %d秒)", 
                copied_files, total_files, duration);
        log_message(LOG_SUCCESS, success_msg, "构建产物");
    } else {
        char warning_msg[100];
        snprintf(warning_msg, sizeof(warning_msg), 
                "没有复制任何文件 (耗时: %d秒)", duration);
        log_message(LOG_WARNING, warning_msg, "构建产物");
    }
    
    return copied_files > 0 ? 0 : 1;
}

// 打印帮助信息
void print_help(const char* program_name) {
    printf("用法: %s -c <配置文件> [选项]\n", program_name);
    printf("选项:\n");
    printf("  -r, --rules <规则ID>  指定要执行的规则ID（逗号分隔或范围，如1,3,5或1-3，或'all'执行所有规则）\n");
    printf("  -m, --marker <标识>   在目标路径中添加标识目录\n");
    printf("  -d, --date <日期>     在目标路径中添加日期目录（格式: YYYY-MM-DD）\n");
    printf("  -h, --help           显示此帮助信息\n");
    printf("\n");
    printf("如果不指定 -r 选项，默认执行规则0\n");
    printf("如果不指定 -d 选项，默认使用当前日期\n");
    printf("\n");
    printf("配置文件格式:\n");
    printf("  变量定义: <变量名>=\"值\"\n");
    printf("  复制规则: <序号>;<源路径>;<目标路径>\n");
    printf("\n");
    printf("示例:\n");
    printf("  %s -c copy.conf              # 执行规则0，使用当前日期\n", program_name);
    printf("  %s -c copy.conf -r 1         # 执行规则1，使用当前日期\n", program_name);
    printf("  %s -c copy.conf -r 1,3,5     # 执行规则1,3,5，使用当前日期\n", program_name);
    printf("  %s -c copy.conf -r 1-3       # 执行规则1,2,3，使用当前日期\n", program_name);
    printf("  %s -c copy.conf -r all       # 执行所有规则，使用当前日期\n", program_name);
    printf("  %s -c copy.conf -r 1 -m release  # 执行规则1并添加release目录，使用当前日期\n", program_name);
    printf("  %s -c copy.conf -d 2025-09-07    # 执行规则0，使用指定日期\n", program_name);
}

// 主函数
int main(int argc, char* argv[]) {
    const char* config_path = NULL;
    const char* rule_str = NULL;
    const char* marker = NULL;
    const char* date = NULL;
    
    // 定义长选项
    static struct option long_options[] = {
        {"config", required_argument, 0, 'c'},
        {"rules", required_argument, 0, 'r'},
        {"marker", required_argument, 0, 'm'},
        {"date", required_argument, 0, 'd'},
        {"help", no_argument, 0, 'h'},
        {0, 0, 0, 0}
    };
    
    // 解析命令行参数
    int opt;
    int option_index = 0;
    
    while ((opt = getopt_long(argc, argv, "c:r:m:d:h", long_options, &option_index)) != -1) {
        switch (opt) {
            case 'c':
                config_path = optarg;
                break;
            case 'r':
                rule_str = optarg;
                break;
            case 'm':
                marker = optarg;
                break;
            case 'd':
                date = optarg;
                break;
            case 'h':
                print_help(argv[0]);
                return 0;
            default:
                fprintf(stderr, "未知选项\n");
                print_help(argv[0]);
                return 1;
        }
    }
    
    if (!config_path) {
        fprintf(stderr, "错误: 必须指定配置文件 (-c)\n");
        print_help(argv[0]);
        return 1;
    }
    
    // 如果没有指定日期，使用当前日期
    if (!date) {
        time_t now = time(NULL);
        struct tm* t = localtime(&now);
        static char current_date[11];
        strftime(current_date, sizeof(current_date), "%Y-%m-%d", t);
        date = current_date;
    }
    
    return copy_build_artifacts(config_path, rule_str, marker, date);
}