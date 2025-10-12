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

// 获取当前源码提交哈希
int get_current_commit(const char *target_dir, char *commit, size_t size) {
    char cmd[1024];
    snprintf(cmd, sizeof(cmd), "cd \"%s\" && git rev-parse HEAD", target_dir);
    
    FILE *fp = popen(cmd, "r");
    if (fp == NULL) {
        return -1;
    }
    
    if (fgets(commit, size, fp) == NULL) {
        pclose(fp);
        return -1;
    }
    
    // 移除换行符
    commit[strcspn(commit, "\n")] = 0;
    
    pclose(fp);
    return 0;
}

// 检查是否为有效的提交哈希
bool is_valid_commit(const char *target_dir, const char *commit) {
    char cmd[1024];
    snprintf(cmd, sizeof(cmd), "cd \"%s\" && git cat-file -t %s", target_dir, commit);
    
    int result = system(cmd);
    return result == 0;
}

// 切换到指定的分支或提交
int switch_to_reference(const char *target_dir, const char *reference) {
    char current_commit[256];
    char current_branch[256];
    
    // 获取当前状态
    bool has_current_commit = (get_current_commit(target_dir, current_commit, sizeof(current_commit)) == 0);
    bool has_current_branch = (get_current_branch(target_dir, current_branch, sizeof(current_branch)) == 0);
    
    // 检查是否已经在目标引用上
    if (has_current_branch && strcmp(current_branch, reference) == 0) {
        log_info("已经在目标分支: %s", reference);
        return 0;
    }
    
    if (has_current_commit && strcmp(current_commit, reference) == 0) {
        log_info("已经在目标提交: %s", reference);
        return 0;
    }
    
    // 首先检查是否是有效的提交哈希
    if (is_valid_commit(target_dir, reference)) {
        char cmd[1024];
        snprintf(cmd, sizeof(cmd), "cd \"%s\" && git checkout %s", target_dir, reference);
        log_info("切换到提交: %s", reference);
        return system(cmd);
    }
    // 否则当作分支处理
    else {
        char cmd[1024];
        snprintf(cmd, sizeof(cmd), "cd \"%s\" && git checkout %s", target_dir, reference);
        log_info("切换到分支: %s", reference);
        return system(cmd);
    }
}

// 拉取最新代码
int pull_latest_changes(const char *target_dir, const char *reference) {
    char cmd[1024];
    
    // 如果是提交哈希，不需要拉取，直接切换到该提交
    if (is_valid_commit(target_dir, reference)) {
        log_info("检测到提交哈希，跳过拉取操作");
        return 0;
    }
    
    // 如果是分支，拉取最新代码
    snprintf(cmd, sizeof(cmd), "cd \"%s\" && git pull origin %s", target_dir, reference);
    log_info("拉取最新代码: %s", cmd);
    return system(cmd);
}