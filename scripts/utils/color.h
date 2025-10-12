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
#define COLOR_GRAY    "\033[90m"

// 亮色 - 在暗色背景上更清晰
#define COLOR_BRIGHT_RED     "\033[91m"
#define COLOR_BRIGHT_GREEN   "\033[92m"
#define COLOR_BRIGHT_YELLOW  "\033[93m"
#define COLOR_BRIGHT_BLUE    "\033[94m"
#define COLOR_BRIGHT_MAGENTA "\033[95m"
#define COLOR_BRIGHT_CYAN    "\033[96m"
#define COLOR_BRIGHT_WHITE   "\033[97m"

// 背景颜色
#define BG_BLACK   "\033[40m"
#define BG_RED     "\033[41m"
#define BG_GREEN   "\033[42m"
#define BG_YELLOW  "\033[43m"
#define BG_BLUE    "\033[44m"
#define BG_MAGENTA "\033[45m"
#define BG_CYAN    "\033[46m"
#define BG_WHITE   "\033[47m"

// 文本样式
#define STYLE_BOLD       "\033[1m"
#define STYLE_DIM        "\033[2m"
#define STYLE_ITALIC     "\033[3m"
#define STYLE_UNDERLINE  "\033[4m"
#define STYLE_BLINK      "\033[5m"
#define STYLE_REVERSE    "\033[7m"
#define STYLE_HIDDEN     "\033[8m"
#define STYLE_STRIKE     "\033[9m"

// 日志级别颜色 - 为暗色背景优化
#define LOG_ERROR COLOR_BRIGHT_RED STYLE_BOLD
#define LOG_WARNING COLOR_BRIGHT_YELLOW
#define LOG_INFO COLOR_BRIGHT_CYAN
#define LOG_DEBUG COLOR_BRIGHT_MAGENTA
#define LOG_SUCCESS COLOR_BRIGHT_GREEN STYLE_BOLD

// 特殊用途颜色 - 为暗色背景优化
#define COLOR_TIMESTAMP COLOR_BRIGHT_WHITE STYLE_DIM      // 时间戳颜色
#define COLOR_BRACKETS COLOR_BRIGHT_WHITE STYLE_DIM       // 中括号颜色

#endif // COLOR_H