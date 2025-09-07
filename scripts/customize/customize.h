#ifndef CUSTOMIZE_H
#define CUSTOMIZE_H

#include <stdbool.h>
#include <regex.h>

// 操作类型枚举
typedef enum {
    OP_REPLACE,
    OP_INSERT_AFTER,
    OP_INSERT_BEFORE,
    OP_APPEND,
    OP_DELETE,
    OP_EXEC,
    OP_COPY,
    OP_UNKNOWN
} OperationType;

// 上下文枚举
typedef enum {
    CTX_INIT,
    CTX_BUILD,
    CTX_ALL,
    CTX_UNKNOWN
} ContextType;

// 规则结构体
typedef struct {
    ContextType context;
    OperationType operation;
    char *target_file;
    char *param1;
    char *param2;
} Rule;

#ifndef PATH_MAX
#define PATH_MAX 1024
#endif

// 函数声明
int parse_customize_config(const char *filename, Rule **rules, int *rule_count, 
                          char ***variables, int *var_count);
void free_rules_and_vars(Rule *rules, int rule_count, char **variables, int var_count);
int execute_rules(Rule *rules, int rule_count, ContextType current_context, 
                  const char *src_dir, const char *res_dir, const char *author,
                  char **variables, int var_count);
ContextType parse_context(const char *context_str);
OperationType parse_operation(const char *operation_str);
char* replace_variables(const char *str, const char *src_dir, const char *res_dir, 
                       const char *author, const char *build_time,
                       char **variables, int var_count);
char* get_current_time_str(void);

#endif // CUSTOMIZE_H