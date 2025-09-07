#ifndef UTILS_H
#define UTILS_H

#include <stdbool.h>

void log_error(const char *format, ...);
void log_warning(const char *format, ...);
void log_info(const char *format, ...);
void log_success(const char *format, ...);
bool file_exists(const char *path);
bool dir_exists(const char *path);
int create_dir(const char *path);
int copy_file(const char *src, const char *dst);
int copy_dir(const char *src, const char *dst);
int remove_file_or_dir(const char *path);
char* trim_whitespace(char *str);
int get_terminal_width(void);
char* get_project_root(void);
int ensure_directory_exists(const char *path);
#endif // UTILS_H