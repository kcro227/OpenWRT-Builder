#ifndef COLOR_H
#define COLOR_H

// 文本颜色代码
#define COLOR_RESET   "\033[0m"
#define COLOR_RED     "\033[31m"
#define COLOR_GREEN   "\033[32m"
#define COLOR_YELLOW  "\033[33m"
#define COLOR_BLUE    "\033[34m"
#define COLOR_MAGENTA "\033[35m"
#define COLOR_CYAN    "\033[36m"
#define COLOR_WHITE   "\033[37m"

// 文本样式
#define STYLE_BOLD      "\033[1m"
#define STYLE_UNDERLINE "\033[4m"

// 日志级别颜色
#define LOG_ERROR COLOR_RED STYLE_BOLD
#define LOG_WARNING COLOR_YELLOW
#define LOG_INFO COLOR_CYAN
#define LOG_SUCCESS COLOR_GREEN STYLE_BOLD

#endif // COLOR_H