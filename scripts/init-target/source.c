#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdbool.h>
#include <unistd.h>
#include <sys/stat.h>
#include <errno.h>
#include <libgen.h>
#include <linux/limits.h>

#include "../utils/utils.h"
#include "../utils/color.h"

// 检查源码目录是否需要更新
bool source_needs_update(const char *target_dir) {
    char cmd[1024];
    snprintf(cmd, sizeof(cmd), "cd \"%s\" && git fetch --dry-run", target_dir);
    
    int result = system(cmd);
    // git fetch --dry-run 有输出表示有更新
    return result != 0;
}

// 获取当前源码分支
int get_current_branch(const char *target_dir, char *branch, size_t size) {
    char cmd[1024];
    snprintf(cmd, sizeof(cmd), "cd \"%s\" && git rev-parse --abbrev-ref HEAD", target_dir);
    
    FILE *fp = popen(cmd, "r");
    if (fp == NULL) {
        return -1;
    }
    
    if (fgets(branch, size, fp) == NULL) {
        pclose(fp);
        return -1;
    }
    
    // 移除换行符
    branch[strcspn(branch, "\n")] = 0;
    
    pclose(fp);
    return 0;
}

// 切换源码分支
int switch_branch(const char *target_dir, const char *branch) {
    char current_branch[256];
    if (get_current_branch(target_dir, current_branch, sizeof(current_branch)) == 0) {
        if (strcmp(current_branch, branch) == 0) {
            log_info("已经在目标分支: %s", branch);
            return 0;
        }
    }
    
    char cmd[1024];
    snprintf(cmd, sizeof(cmd), "cd \"%s\" && git checkout %s", target_dir, branch);
    
    log_info("切换分支: %s", cmd);
    return system(cmd);
}