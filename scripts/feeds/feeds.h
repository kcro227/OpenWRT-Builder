#ifndef FEEDS_H
#define FEEDS_H

#define MAX_LINE_LENGTH 256
#define MAX_FEEDS 100
#define DEFAULT_FEEDS_DIR "packages"
#define DEFAULT_FEEDS_FILE "packages/feeds.conf"

// Feed 结构体
typedef struct {
    char type[20];
    char name[50];
    char url[256];
    char branch[50];
} Feed;

// 函数声明
void print_usage(const char *program_name);
int parse_feeds_file(const char *filename, Feed feeds[], int *feed_count);
int install_feed(const Feed *feed, const char *base_dir);
int update_feed(const Feed *feed, const char *base_dir);
int list_feeds(Feed feeds[], int feed_count);
int run_git_command(const char *command, const char *path);

#endif // FEEDS_H