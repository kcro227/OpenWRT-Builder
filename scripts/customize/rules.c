#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdbool.h>
#include <time.h>
#include <unistd.h>
#include <sys/stat.h>
#include <errno.h>
#include <ctype.h>

#include "customize.h"

int parse_customize_config(const char *filename, Rule **rules, int *rule_count, 
                          char ***variables, int *var_count) {
    FILE *file = fopen(filename, "r");
    if (file == NULL) {
        fprintf(stderr, "错误: 无法打开文件 %s\n", filename);
        return -1;
    }
    
    char line[1024];
    *rule_count = 0;
    *var_count = 0;
    int max_rules = 100;
    int max_vars = 20;
    *rules = malloc(max_rules * sizeof(Rule));
    *variables = malloc(max_vars * sizeof(char*));
    
    if (*rules == NULL || *variables == NULL) {
        fclose(file);
        return -1;
    }
    
    while (fgets(line, sizeof(line), file) != NULL) {
        // 跳过注释行和空行
        if (line[0] == '#' || line[0] == '\n') {
            continue;
        }
        
        // 移除行尾的换行符
        line[strcspn(line, "\n")] = 0;
        
        // 检查是否是变量定义 (格式: 变量名=值)
        // 变量定义不能包含分号，且等号前必须是有效的变量名
        char *equals = strchr(line, '=');
        if (equals != NULL && line[0] != ' ' && line[0] != '\t') {
            // 检查等号前的内容是否是有效的变量名
            bool is_valid_var = true;
            for (char *p = line; p < equals; p++) {
                if (!isalnum(*p) && *p != '_') {
                    is_valid_var = false;
                    break;
                }
            }
            
            // 检查行中是否包含分号 (规则行特征)
            bool has_semicolon = strchr(line, ';') != NULL;
            
            if (is_valid_var && !has_semicolon) {
                // 这是一个变量定义
                if (*var_count >= max_vars) {
                    max_vars *= 2;
                    *variables = realloc(*variables, max_vars * sizeof(char*));
                    if (*variables == NULL) {
                        fclose(file);
                        return -1;
                    }
                }
                
                *equals = '\0';
                char *name = line;
                char *value = equals + 1;
                
                // 去除值中的引号
                if (value[0] == '"' && value[strlen(value)-1] == '"') {
                    value[strlen(value)-1] = '\0';
                    value++;
                }
                
                // 保存变量
                char *var_def = malloc(strlen(name) + strlen(value) + 2);
                sprintf(var_def, "%s=%s", name, value);
                (*variables)[(*var_count)++] = var_def;
                printf("解析到变量: %s=%s\n", name, value);
                continue;
            }
        }
        
        // 解析规则行
        char *saveptr;
        char *token = strtok_r(line, ";", &saveptr);
        if (token == NULL) continue;
        
        ContextType context = parse_context(token);
        if (context == CTX_UNKNOWN) continue;
        
        token = strtok_r(NULL, ";", &saveptr);
        if (token == NULL) continue;
        
        OperationType operation = parse_operation(token);
        if (operation == OP_UNKNOWN) continue;
        
        token = strtok_r(NULL, ";", &saveptr);
        if (token == NULL) continue;
        
        char *target_file = strdup(token);
        
        token = strtok_r(NULL, ";", &saveptr);
        char *param1 = token ? strdup(token) : NULL;
        
        token = strtok_r(NULL, ";", &saveptr);
        char *param2 = token ? strdup(token) : NULL;
        
        // 保存规则
        if (*rule_count >= max_rules) {
            max_rules *= 2;
            *rules = realloc(*rules, max_rules * sizeof(Rule));
            if (*rules == NULL) {
                fclose(file);
                return -1;
            }
        }
        
        Rule *rule = &(*rules)[(*rule_count)++];
        rule->context = context;
        rule->operation = operation;
        rule->target_file = target_file;
        rule->param1 = param1;
        rule->param2 = param2;

        // 添加调试输出
        printf("解析到规则: %s;%s;%s;%s;%s\n",
           context == CTX_INIT ? "init" : 
           context == CTX_BUILD ? "build" : "all",
           operation == OP_REPLACE ? "replace" :
           operation == OP_INSERT_AFTER ? "insert-after" :
           operation == OP_INSERT_BEFORE ? "insert-before" :
           operation == OP_APPEND ? "append" :
           operation == OP_DELETE ? "delete" :
           operation == OP_EXEC ? "exec" :
           operation == OP_COPY ? "copy" : "unknown",
           target_file,
           param1 ? param1 : "",
           param2 ? param2 : "");
    }
    
    fclose(file);
    return 0;
}

// 释放规则和变量内存
void free_rules_and_vars(Rule *rules, int rule_count, char **variables, int var_count) {
    for (int i = 0; i < rule_count; i++) {
        free(rules[i].target_file);
        free(rules[i].param1);
        free(rules[i].param2);
    }
    free(rules);
    
    for (int i = 0; i < var_count; i++) {
        free(variables[i]);
    }
    free(variables);
}

// 从变量列表中获取变量值
char* get_variable_value(char **variables, int var_count, const char *var_name) {
    for (int i = 0; i < var_count; i++) {
        char *var_def = variables[i];
        char *equals = strchr(var_def, '=');
        if (equals != NULL) {
            *equals = '\0';
            if (strcmp(var_def, var_name) == 0) {
                *equals = '=';
                return equals + 1;
            }
            *equals = '=';
        }
    }
    return NULL;
}

// 解析上下文字符串
ContextType parse_context(const char *context_str) {
    if (strcmp(context_str, "init") == 0) return CTX_INIT;
    if (strcmp(context_str, "build") == 0) return CTX_BUILD;
    if (strcmp(context_str, "all") == 0) return CTX_ALL;
    return CTX_UNKNOWN;
}

// 解析操作类型字符串
OperationType parse_operation(const char *operation_str) {
    if (strcmp(operation_str, "replace") == 0) return OP_REPLACE;
    if (strcmp(operation_str, "insert-after") == 0) return OP_INSERT_AFTER;
    if (strcmp(operation_str, "insert-before") == 0) return OP_INSERT_BEFORE;
    if (strcmp(operation_str, "append") == 0) return OP_APPEND;
    if (strcmp(operation_str, "delete") == 0) return OP_DELETE;
    if (strcmp(operation_str, "exec") == 0) return OP_EXEC;
    if (strcmp(operation_str, "copy") == 0) return OP_COPY;
    return OP_UNKNOWN;
}

// 获取当前时间字符串
char* get_current_time_str(void) {
    time_t now = time(NULL);
    struct tm *t = localtime(&now);
    char *time_str = malloc(20);
    if (time_str == NULL) return NULL;
    
    // 使用 strftime 格式化时间，确保不包含换行符
    strftime(time_str, 20, "%Y-%m-%d %H:%M:%S", t);
    
    // 确保字符串以 null 结尾
    time_str[19] = '\0';
    
    return time_str;
}

// 清理字符串中的换行符和前后空白
char* clean_string(const char *str) {
    if (str == NULL) return NULL;
    
    // 计算新长度（不包括换行符和前后空白）
    size_t len = strlen(str);
    const char *start = str;
    const char *end = str + len - 1;
    
    // 跳过前导空白
    while (*start && (*start == ' ' || *start == '\t' || *start == '\n' || *start == '\r')) {
        start++;
    }
    
    // 跳过尾随空白
    while (end > start && (*end == ' ' || *end == '\t' || *end == '\n' || *end == '\r')) {
        end--;
    }
    
    // 计算新长度
    size_t new_len = end - start + 1;
    
    // 分配内存并复制清理后的字符串
    char *result = malloc(new_len + 1);
    if (result == NULL) return NULL;
    
    strncpy(result, start, new_len);
    result[new_len] = '\0';
    
    return result;
}

// 替换变量（确保不包含不必要的换行符）
char* replace_variables(const char *str, const char *src_dir, const char *res_dir, 
                       const char *author, const char *build_time, 
                       char **variables, int var_count) {
    if (str == NULL) return NULL;
    
    // 清理输入字符串
    char *clean_str = clean_string(str);
    if (clean_str == NULL) return NULL;
    
    // 第一次扫描：计算需要的缓冲区大小
    size_t len = strlen(clean_str);
    size_t new_len = len;
    const char *s = clean_str;
    
    while (*s) {
        if (strncmp(s, "${SRC_DIR}", 10) == 0 && src_dir) {
            new_len += strlen(src_dir) - 10;
            s += 10;
        } else if (strncmp(s, "${RES_DIR}", 10) == 0 && res_dir) {
            new_len += strlen(res_dir) - 10;
            s += 10;
        } else if (strncmp(s, "${AUTHOR}", 9) == 0 && author) {
            new_len += strlen(author) - 9;
            s += 9;
        } else if (strncmp(s, "__BUILD_TIME__", 14) == 0 && build_time) {
            new_len += strlen(build_time) - 14;
            s += 14;
        } else if (s[0] == '$' && s[1] == '{') {
            // 查找自定义变量
            const char *end = strchr(s + 2, '}');
            if (end != NULL) {
                int var_len = end - s + 1;
                char *var_name = malloc(var_len - 2);
                strncpy(var_name, s + 2, var_len - 3);
                var_name[var_len - 3] = '\0';
                
                char *var_value = get_variable_value(variables, var_count, var_name);
                if (var_value != NULL) {
                    // 清理变量值
                    char *clean_value = clean_string(var_value);
                    if (clean_value != NULL) {
                        // 递归替换变量值中的变量
                        char *expanded_value = replace_variables(clean_value, src_dir, res_dir, 
                                                               author, build_time, 
                                                               variables, var_count);
                        if (expanded_value != NULL) {
                            new_len += strlen(expanded_value) - var_len;
                            free(expanded_value);
                        } else {
                            new_len += strlen(clean_value) - var_len;
                        }
                        
                        free(clean_value);
                    }
                }
                
                free(var_name);
                s += var_len;
            } else {
                s++;
            }
        } else {
            s++;
        }
    }
    
    // 分配缓冲区
    char *result = malloc(new_len + 1);
    if (result == NULL) {
        free(clean_str);
        return NULL;
    }
    
    // 第二次扫描：实际替换变量
    char *p_result = result;
    s = clean_str;
    
    while (*s) {
        if (strncmp(s, "${SRC_DIR}", 10) == 0 && src_dir) {
            strcpy(p_result, src_dir);
            p_result += strlen(src_dir);
            s += 10;
        } else if (strncmp(s, "${RES_DIR}", 10) == 0 && res_dir) {
            strcpy(p_result, res_dir);
            p_result += strlen(res_dir);
            s += 10;
        } else if (strncmp(s, "${AUTHOR}", 9) == 0 && author) {
            strcpy(p_result, author);
            p_result += strlen(author);
            s += 9;
        } else if (strncmp(s, "__BUILD_TIME__", 14) == 0 && build_time) {
            strcpy(p_result, build_time);
            p_result += strlen(build_time);
            s += 14;
        } else if (s[0] == '$' && s[1] == '{') {
            // 处理自定义变量
            const char *end = strchr(s + 2, '}');
            if (end != NULL) {
                int var_len = end - s + 1;
                char *var_name = malloc(var_len - 2);
                strncpy(var_name, s + 2, var_len - 3);
                var_name[var_len - 3] = '\0';
                
                char *var_value = get_variable_value(variables, var_count, var_name);
                if (var_value != NULL) {
                    // 清理变量值
                    char *clean_value = clean_string(var_value);
                    if (clean_value != NULL) {
                        // 递归替换变量值中的变量
                        char *expanded_value = replace_variables(clean_value, src_dir, res_dir, 
                                                               author, build_time, 
                                                               variables, var_count);
                        if (expanded_value != NULL) {
                            strcpy(p_result, expanded_value);
                            p_result += strlen(expanded_value);
                            free(expanded_value);
                        } else {
                            strcpy(p_result, clean_value);
                            p_result += strlen(clean_value);
                        }
                        
                        free(clean_value);
                    }
                } else {
                    // 变量未定义，保留原样
                    strncpy(p_result, s, var_len);
                    p_result += var_len;
                }
                
                free(var_name);
                s += var_len;
            } else {
                *p_result++ = *s++;
            }
        } else {
            *p_result++ = *s++;
        }
    }
    
    *p_result = '\0';
    free(clean_str);
    
    return result;
}

// 执行替换操作（支持正则表达式）
int execute_replace(const char *file_path, const char *search_pattern, const char *replace) {
    // 构建临时文件路径
    char tmp_path[PATH_MAX];
    snprintf(tmp_path, sizeof(tmp_path), "%s.tmp", file_path);
    
    FILE *src_file = fopen(file_path, "r");
    if (src_file == NULL) {
        fprintf(stderr, "错误: 无法打开源文件 %s\n", file_path);
        return -1;
    }
    
    FILE *dst_file = fopen(tmp_path, "w");
    if (dst_file == NULL) {
        fclose(src_file);
        fprintf(stderr, "错误: 无法创建临时文件 %s\n", tmp_path);
        return -1;
    }
    
    char line[4096];
    int changes = 0;
    
    // 编译正则表达式
    regex_t regex;
    int regex_result = regcomp(&regex, search_pattern, REG_EXTENDED);
    if (regex_result != 0) {
        fclose(src_file);
        fclose(dst_file);
        fprintf(stderr, "错误: 无效的正则表达式 '%s'\n", search_pattern);
        return -1;
    }

    
    while (fgets(line, sizeof(line), src_file) != NULL) {
        char *pos = line;
        regmatch_t matches[1];
        char result[8192] = {0};
        char *r = result;
        
        // 使用正则表达式查找所有匹配
        while (regexec(&regex, pos, 1, matches, 0) == 0) {
            // 复制匹配之前的部分
            size_t len = matches[0].rm_so;
            strncpy(r, pos, len);
            r += len;
            
            // 复制替换字符串
            strcpy(r, replace);

            r += strlen(replace);
            
            // 移动位置指针到匹配结束之后
            pos += matches[0].rm_eo;
            changes++;
        }
        
        // 复制剩余部分
        strcpy(r, pos);
        
        fputs(result, dst_file);
    }
    
    // 释放正则表达式
    regfree(&regex);
    
    fclose(src_file);
    fclose(dst_file);
    
    if (changes > 0) {
        // 替换原文件
        if (rename(tmp_path, file_path) != 0) {
            fprintf(stderr, "错误: 无法替换原文件 %s\n", file_path);
            remove(tmp_path);
            return -1;
        }
        printf("在文件 %s 中进行了 %d 处替换\n", file_path, changes);
        return 0;
    } else {
        // 没有进行任何替换，删除临时文件
        remove(tmp_path);
        printf("在文件 %s 中没有找到匹配的文本\n", file_path);
        return 0;
    }
}


// 检查替换操作是否已经应用
bool check_replace_applied(const char *file_path, const char *search, const char *replace) {
    FILE *file = fopen(file_path, "r");
    if (file == NULL) return false;
    
    char line[4096];
    bool found = false;
    
    // 编译正则表达式
    regex_t regex;
    if (regcomp(&regex, search, REG_EXTENDED) != 0) {
        fclose(file);
        return false;
    }
    
    while (fgets(line, sizeof(line), file) != NULL) {
        // 检查是否已经包含替换后的内容
        if (strstr(line, replace) != NULL) {
            found = true;
            break;
        }
        
        // 检查是否还需要替换
        regmatch_t matches[1];
        if (regexec(&regex, line, 1, matches, 0) == 0) {
            // 找到了需要替换的内容，说明替换尚未完成
            found = false;
            break;
        }
    }
    
    regfree(&regex);
    fclose(file);
    return found;
}

// 检查插入操作是否已经应用
bool check_insert_applied(const char *file_path, const char *pattern, const char *content, bool after) {
    FILE *file = fopen(file_path, "r");
    if (file == NULL) return false;
    
    char line[4096];
    bool pattern_found = false;
    bool content_found_after_pattern = false;
    
    // 编译正则表达式
    regex_t regex;
    if (regcomp(&regex, pattern, REG_EXTENDED) != 0) {
        fclose(file);
        return false;
    }
    
    while (fgets(line, sizeof(line), file) != NULL) {
        // 检查模式是否存在
        regmatch_t matches[1];
        if (regexec(&regex, line, 1, matches, 0) == 0) {
            pattern_found = true;
            
            // 如果是insert-after，检查下一行是否包含内容
            if (after) {
                char next_line[4096];
                if (fgets(next_line, sizeof(next_line), file) != NULL) {
                    if (strstr(next_line, content) != NULL) {
                        content_found_after_pattern = true;
                        break;
                    }
                    // 回退一行，因为我们已经读取了下一行
                    fseek(file, -strlen(next_line), SEEK_CUR);
                }
            }
        }
        
        // 检查内容是否已经存在
        if (strstr(line, content) != NULL) {
            // 如果是insert-before，检查前一行是否包含模式
            if (!after && pattern_found) {
                content_found_after_pattern = true;
                break;
            }
        }
        
        // 重置pattern_found，除非我们正在检查insert-before
        if (!after) {
            pattern_found = false;
        }
    }
    
    regfree(&regex);
    fclose(file);
    
    // 如果内容已经存在且在正确的位置，则认为已经应用
    return content_found_after_pattern;
}

// 检查追加操作是否已经应用
bool check_append_applied(const char *file_path, const char *content) {
    FILE *file = fopen(file_path, "r");
    if (file == NULL) return false;
    
    char line[4096];
    bool found = false;
    
    // 检查文件末尾是否已经是该内容
    while (fgets(line, sizeof(line), file) != NULL) {
        if (strstr(line, content) != NULL) {
            found = true;
        }
    }
    
    fclose(file);
    return found;
}

// 检查删除操作是否已经应用
bool check_delete_applied(const char *file_path, const char *pattern) {
    FILE *file = fopen(file_path, "r");
    if (file == NULL) return true; // 如果文件不存在，认为删除已经应用
    
    char line[4096];
    bool found = false;
    
    // 编译正则表达式
    regex_t regex;
    if (regcomp(&regex, pattern, REG_EXTENDED) != 0) {
        fclose(file);
        return false;
    }
    
    while (fgets(line, sizeof(line), file) != NULL) {
        // 检查模式是否还存在
        regmatch_t matches[1];
        if (regexec(&regex, line, 1, matches, 0) == 0) {
            found = true;
            break;
        }
    }
    
    regfree(&regex);
    fclose(file);
    
    // 如果找不到模式，说明删除已经应用
    return !found;
}

// 检查复制操作是否已经应用
bool check_copy_applied(const char *src, const char *dest) {
    struct stat src_stat, dest_stat;
    
    // 检查源文件和目标文件是否存在
    if (stat(src, &src_stat) != 0 || stat(dest, &dest_stat) != 0) {
        return false;
    }
    
    // 检查修改时间，如果目标文件比源文件新，认为已经应用
    return dest_stat.st_mtime >= src_stat.st_mtime;
}

// 执行插入操作（支持正则表达式）
int execute_insert(const char *file_path, const char *pattern, const char *content, bool after) {
    // 构建临时文件路径
    char tmp_path[PATH_MAX];
    snprintf(tmp_path, sizeof(tmp_path), "%s.tmp", file_path);
    
    FILE *src_file = fopen(file_path, "r");
    if (src_file == NULL) {
        fprintf(stderr, "错误: 无法打开源文件 %s\n", file_path);
        return -1;
    }
    
    FILE *dst_file = fopen(tmp_path, "w");
    if (dst_file == NULL) {
        fclose(src_file);
        fprintf(stderr, "错误: 无法创建临时文件 %s\n", tmp_path);
        return -1;
    }
    
    char line[4096];
    int changes = 0;
    bool found_pattern = false;
    
    // 编译正则表达式
    regex_t regex;
    int regex_result = regcomp(&regex, pattern, REG_EXTENDED);
    if (regex_result != 0) {
        fclose(src_file);
        fclose(dst_file);
        fprintf(stderr, "错误: 无效的正则表达式 '%s'\n", pattern);
        return -1;
    }
    
    while (fgets(line, sizeof(line), src_file) != NULL) {
        // 检查是否匹配模式
        regmatch_t matches[1];
        if (regexec(&regex, line, 1, matches, 0) == 0) {
            found_pattern = true;
            
            if (!after) {
                // 在匹配行前插入
                fputs(content, dst_file);
                fputs("\n", dst_file);
                changes++;
            }
            
            // 写入原行
            fputs(line, dst_file);
            
            if (after) {
                // 在匹配行后插入
                fputs(content, dst_file);
                fputs("\n", dst_file);
                changes++;
            }
        } else {
            // 不匹配，直接写入
            fputs(line, dst_file);
        }
    }
    
    // 如果模式未找到但需要插入，则在文件末尾插入
    if (!found_pattern && after) {
        fputs(content, dst_file);
        fputs("\n", dst_file);
        changes++;
        printf("模式未找到，在文件末尾插入内容\n");
    }
    
    // 释放正则表达式
    regfree(&regex);
    
    fclose(src_file);
    fclose(dst_file);
    
    if (changes > 0) {
        // 替换原文件
        if (rename(tmp_path, file_path) != 0) {
            fprintf(stderr, "错误: 无法替换原文件 %s\n", file_path);
            remove(tmp_path);
            return -1;
        }
        printf("在文件 %s 中进行了 %d 处插入\n", file_path, changes);
        return 0;
    } else {
        // 没有进行任何插入，删除临时文件
        remove(tmp_path);
        printf("在文件 %s 中没有找到匹配的文本\n", file_path);
        return 0;
    }
}

// 执行追加操作
int execute_append(const char *file_path, const char *content) {
    // 清理内容字符串
    char *clean_content = clean_string(content);
    if (clean_content == NULL) {
        fprintf(stderr, "错误: 无法清理内容字符串\n");
        return -1;
    }
    
    FILE *file = fopen(file_path, "a");
    if (file == NULL) {
        fprintf(stderr, "错误: 无法打开文件 %s\n", file_path);
        free(clean_content);
        return -1;
    }
    
    // 直接写入清理后的内容
    fprintf(file, "%s", clean_content);
    fclose(file);
    
    free(clean_content);
    return 0;
}

// 执行删除操作（支持正则表达式）
int execute_delete(const char *file_path, const char *pattern) {
    // 构建临时文件路径
    char tmp_path[PATH_MAX];
    snprintf(tmp_path, sizeof(tmp_path), "%s.tmp", file_path);
    
    FILE *src_file = fopen(file_path, "r");
    if (src_file == NULL) {
        fprintf(stderr, "错误: 无法打开源文件 %s\n", file_path);
        return -1;
    }
    
    FILE *dst_file = fopen(tmp_path, "w");
    if (dst_file == NULL) {
        fclose(src_file);
        fprintf(stderr, "错误: 无法创建临时文件 %s\n", tmp_path);
        return -1;
    }
    
    char line[4096];
    int changes = 0;
    
    // 编译正则表达式
    regex_t regex;
    int regex_result = regcomp(&regex, pattern, REG_EXTENDED);
    if (regex_result != 0) {
        fclose(src_file);
        fclose(dst_file);
        fprintf(stderr, "错误: 无效的正则表达式 '%s'\n", pattern);
        return -1;
    }
    
    while (fgets(line, sizeof(line), src_file) != NULL) {
        // 检查是否匹配模式
        regmatch_t matches[1];
        if (regexec(&regex, line, 1, matches, 0) == 0) {
            // 匹配，跳过这行（删除）
            changes++;
        } else {
            // 不匹配，保留这行
            fputs(line, dst_file);
        }
    }
    
    // 释放正则表达式
    regfree(&regex);
    
    fclose(src_file);
    fclose(dst_file);
    
    if (changes > 0) {
        // 替换原文件
        if (rename(tmp_path, file_path) != 0) {
            fprintf(stderr, "错误: 无法替换原文件 %s\n", file_path);
            remove(tmp_path);
            return -1;
        }
        printf("在文件 %s 中删除了 %d 行\n", file_path, changes);
        return 0;
    } else {
        // 没有进行任何删除，删除临时文件
        remove(tmp_path);
        printf("在文件 %s 中没有找到匹配的文本\n", file_path);
        return 0;
    }
}

// 执行命令操作
int execute_exec(const char *command) {
    return system(command);
}

// 执行复制操作
int execute_copy(const char *src, const char *dest) {
    char cmd[4096];
    snprintf(cmd, sizeof(cmd), "cp -r \"%s\" \"%s\"", src, dest);
    return system(cmd);
}

// 执行规则
int execute_rule(const Rule *rule, const char *src_dir, const char *res_dir, 
                const char *author, const char *build_time, 
                char **variables, int var_count) {
    // 替换变量
    char *target_file = replace_variables(rule->target_file, src_dir, res_dir, 
                                        author, build_time, variables, var_count);
    char *param1 = replace_variables(rule->param1, src_dir, res_dir, 
                                   author, build_time, variables, var_count);
    char *param2 = replace_variables(rule->param2, src_dir, res_dir, 
                                   author, build_time, variables, var_count);
    
    if (!target_file) {
        fprintf(stderr, "错误: 无法替换目标文件变量\n");
        return -1;
    }
    
    int result = 0;
    bool already_applied = false;
    
    // 检查规则是否已经应用
    switch (rule->operation) {
        case OP_REPLACE:
            if (param1 && param2) {
                already_applied = check_replace_applied(target_file, param1, param2);
            }
            break;
            
        case OP_INSERT_AFTER:
            if (param1 && param2) {
                already_applied = check_insert_applied(target_file, param1, param2, true);
            }
            break;
            
        case OP_INSERT_BEFORE:
            if (param1 && param2) {
                already_applied = check_insert_applied(target_file, param1, param2, false);
            }
            break;
            
        case OP_APPEND:
            if (param1) {
                already_applied = check_append_applied(target_file, param1);
            }
            break;
            
        case OP_DELETE:
            if (param1) {
                already_applied = check_delete_applied(target_file, param1);
            }
            break;
            
        case OP_COPY:
            if (param1) {
                already_applied = check_copy_applied(target_file, param1);
            }
            break;
            
        case OP_EXEC:
            // 执行操作总是执行，不检查是否已经应用
            already_applied = false;
            break;
            
        default:
            break;
    }
    
    if (already_applied) {
        printf("规则已经应用，跳过执行\n");
        result = 0; // 跳过执行，返回成功
    } else {
        // 执行规则
        switch (rule->operation) {
            case OP_REPLACE:
                if (!param1 || !param2) {
                    fprintf(stderr, "错误: 替换操作需要两个参数\n");
                    result = -1;
                } else {
                    result = execute_replace(target_file, param1, param2);
                }
                break;
                
            case OP_INSERT_AFTER:
                if (!param1 || !param2) {
                    fprintf(stderr, "错误: 插入操作需要两个参数\n");
                    result = -1;
                } else {
                    result = execute_insert(target_file, param1, param2, true);
                }
                break;
                
            case OP_INSERT_BEFORE:
                if (!param1 || !param2) {
                    fprintf(stderr, "错误: 插入操作需要两个参数\n");
                    result = -1;
                } else {
                    result = execute_insert(target_file, param1, param2, false);
                }
                break;
                
            case OP_APPEND:
                if (!param1) {
                    fprintf(stderr, "错误: 追加操作需要一个参数\n");
                    result = -1;
                } else {
                    result = execute_append(target_file, param1);
                }
                break;
                
            case OP_DELETE:
                if (!param1) {
                    fprintf(stderr, "错误: 删除操作需要一个参数\n");
                    result = -1;
                } else {
                    result = execute_delete(target_file, param1);
                }
                break;
                
            case OP_EXEC:
                if (!param1) {
                    fprintf(stderr, "错误: 执行操作需要一个参数\n");
                    result = -1;
                } else {
                    result = execute_exec(param1);
                }
                break;
                
            case OP_COPY:
                if (!param1) {
                    fprintf(stderr, "错误: 复制操作需要目标路径参数\n");
                    result = -1;
                } else {
                    result = execute_copy(target_file, param1);
                }
                break;
                
            default:
                fprintf(stderr, "错误: 未知的操作类型\n");
                result = -1;
                break;
        }
    }
    
    free(target_file);
    free(param1);
    free(param2);
    
    return result;
}

// 执行所有规则
int execute_rules(Rule *rules, int rule_count, ContextType current_context, 
                  const char *src_dir, const char *res_dir, const char *author,
                  char **variables, int var_count) {
    char *build_time = get_current_time_str();
    int success_count = 0;
    int fail_count = 0;
    
    for (int i = 0; i < rule_count; i++) {
        Rule *rule = &rules[i];
        
        // 检查上下文是否匹配
        if (rule->context != current_context && rule->context != CTX_ALL) {
            continue;
        }
        
        printf("执行规则: %s;%s;%s;%s;%s\n",
               rule->context == CTX_INIT ? "init" : 
               rule->context == CTX_BUILD ? "build" : "all",
               rule->operation == OP_REPLACE ? "replace" :
               rule->operation == OP_INSERT_AFTER ? "insert-after" :
               rule->operation == OP_INSERT_BEFORE ? "insert-before" :
               rule->operation == OP_APPEND ? "append" :
               rule->operation == OP_DELETE ? "delete" :
               rule->operation == OP_EXEC ? "exec" :
               rule->operation == OP_COPY ? "copy" : "unknown",
               rule->target_file,
               rule->param1 ? rule->param1 : "",
               rule->param2 ? rule->param2 : "");
        
        if (execute_rule(rule, src_dir, res_dir, author, build_time, variables, var_count) == 0) {
            printf("规则执行成功\n");
            success_count++;
        } else {
            fprintf(stderr, "规则执行失败\n");
            fail_count++;
        }
    }
    
    free(build_time);
    
    if (fail_count == 0) {
        printf("所有规则执行成功 (%d 个)\n", success_count);
        return 0;
    } else {
        fprintf(stderr, "规则执行完成，成功 %d 个，失败 %d 个\n", success_count, fail_count);
        return 1;
    }
}