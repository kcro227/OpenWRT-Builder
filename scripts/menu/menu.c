#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <termios.h>
#include <sys/ioctl.h>

#define MAX_TARGETS 20
#define MAX_NAME_LENGTH 50

// 保存选择的target到文件
void save_target(const char *target) {
    FILE *fp = fopen(".selected_target", "w");
    if (fp) {
        fprintf(fp, "%s", target);
        fclose(fp);
    }
}

// 获取终端大小
void get_terminal_size(int *rows, int *cols) {
    struct winsize w;
    ioctl(STDOUT_FILENO, TIOCGWINSZ, &w);
    *rows = w.ws_row;
    *cols = w.ws_col;
}

// 清除屏幕
void clear_screen() {
    printf("\033[2J\033[H");
}

// 设置文本颜色
void set_color(int color) {
    printf("\033[%dm", color);
}

// 重置文本属性
void reset_attributes() {
    printf("\033[0m");
}

// 显示菜单并让用户选择
int show_menu(char targets[][MAX_NAME_LENGTH], int count) {
    int selected = 0;
    int key;
    int rows, cols;
    
    get_terminal_size(&rows, &cols);
    
    // 禁用行缓冲和回显
    struct termios oldt, newt;
    tcgetattr(STDIN_FILENO, &oldt);
    newt = oldt;
    newt.c_lflag &= ~(ICANON | ECHO);
    tcsetattr(STDIN_FILENO, TCSANOW, &newt);
    
    while(1) {
        clear_screen();
        
        // 显示标题
        set_color(1); // 蓝色
        printf("OpenWRT 项目构建系统 - 选择目标型号\n");
        printf("===================================\n");
        reset_attributes();
        
        // 显示选项
        for (int i = 0; i < count; i++) {
            if (i == selected) {
                set_color(42); // 绿色背景
                printf("> %s\n", targets[i]);
                reset_attributes();
            } else {
                printf("  %s\n", targets[i]);
            }
        }
        
        // 显示说明
        printf("\n");
        set_color(33); // 黄色
        printf("使用上下箭头选择，回车确认，q退出\n");
        reset_attributes();
        
        // 读取按键
        key = getchar();
        
        if (key == 27) { // ESC序列
            getchar(); // 跳过[
            key = getchar();
            
            if (key == 'A' && selected > 0) { // 上箭头
                selected--;
            } else if (key == 'B' && selected < count - 1) { // 下箭头
                selected++;
            }
        } else if (key == 10 || key == 13) { // 回车
            break;
        } else if (key == 'q' || key == 'Q') { // q退出
            selected = -1;
            break;
        }
    }
    
    // 恢复终端设置
    tcsetattr(STDIN_FILENO, TCSANOW, &oldt);
    
    return selected;
}

int main(int argc, char *argv[]) {
    if (argc < 2) {
        printf("错误: 需要指定目标型号列表\n");
        return 1;
    }
    
    char targets[MAX_TARGETS][MAX_NAME_LENGTH];
    int count = argc - 1;
    
    if (count > MAX_TARGETS) {
        printf("错误: 目标型号数量超过最大值 %d\n", MAX_TARGETS);
        return 1;
    }
    
    // 复制目标型号到数组
    for (int i = 0; i < count; i++) {
        strncpy(targets[i], argv[i+1], MAX_NAME_LENGTH - 1);
        targets[i][MAX_NAME_LENGTH - 1] = '\0';
    }
    
    // 显示菜单并获取选择
    int selected = show_menu(targets, count);
    
    if (selected >= 0 && selected < count) {
        save_target(targets[selected]);
        printf("已选择: %s\n", targets[selected]);
        return 0;
    } else {
        printf("未选择目标\n");
        return 1;
    }
}