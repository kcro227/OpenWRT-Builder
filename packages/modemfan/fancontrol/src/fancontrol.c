#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <sys/stat.h>
#include <signal.h>
#include <time.h>

// 包含ubus客户端头文件
#include "ubus_client.h"
#include "modules/modules.h"

#define MAX_LENGTH 200
#define MAX_TEMP 120

// 定义全局变量
char at_port[MAX_LENGTH] = "/dev/ttyUSB2";// AT端口路径
char modem_device[MAX_LENGTH] = "T99W373";  // 调制解调器名称
char fan_file[MAX_LENGTH] = "/sys/devices/platform/pwm-fan/hwmon/hwmon2/pwm1";   // -F
modem_t modem;

int start_speed = 35;   // -s
int start_temp = 40;    // -t
int max_speed = 255;    // -m
int debug_mode = 0;     // -D

// 温度传感器数量
time_t last_update = 0;
#define UPDATE_INTERVAL 30 // 每30秒更新一次传感器数据

/**
 * 底层写文件
 */
static size_t write_file(const char* path, char* buf, size_t len) {
    FILE* fp = NULL;
    size_t size = 0;
    fp = fopen(path, "w+");
    if (fp == NULL) {
        return 0;
    }
    size = fwrite(buf, len, 1, fp);
    fclose(fp);
    return size;
}

/**
 * 读取风扇速度
 */
static int get_fanspeed(char* fan_file) {
    char buf[8] = {0};
    FILE* fp = fopen(fan_file, "r");
    if (fp == NULL) {
        return -1;
    }
    
    if (fgets(buf, sizeof(buf), fp) != NULL) {
        fclose(fp);
        return atoi(buf);
    }
    
    fclose(fp);
    return -1;
}

/**
 * 设置风扇转速
 */
static int set_fanspeed(int fan_speed, char* fan_file) {
    char buf[8] = {0};
    sprintf(buf, "%d\n", fan_speed);
    return write_file(fan_file, buf, strlen(buf));
}

/**
 * 计算风扇转速
 */
static int calculate_speed(int current_temp, int max_temp, int min_temp, int max_speed, int min_speed) {
    if (current_temp < min_temp) {
        return 0;
    }
    int fan_speed = (current_temp - min_temp) * (max_speed - min_speed) / (max_temp - min_temp) + min_speed;
    if (fan_speed > max_speed) {
        fan_speed = max_speed;
    }
    return fan_speed;
}

/**
 * 判断文件是否存在方法
 */
static int file_exist(const char* name) {
    struct stat buffer;
    return stat(name, &buffer);
}

/**
 *  信号处理函数
 */
void handle_termination(int signum) {
    printf("Received signal %d, shutting down...\n", signum);
    // 设置风扇转速为 0
    set_fanspeed(0, fan_file);
    // 清理ubus客户端
    cleanup_global_ubus_client();
    exit(EXIT_SUCCESS); // 优雅地退出程序
}

/**
 * 注册信号处理函数
 */
void register_signal_handlers() {
    struct sigaction sa;
    memset(&sa, 0, sizeof(sa));
    sa.sa_handler = handle_termination;
    sigemptyset(&sa.sa_mask);
    sigaction(SIGINT, &sa, NULL);
    sigaction(SIGTERM, &sa, NULL);
}

static int get_current_temperature(){

    switch(modem)
    {
        case MODEM_FM350:
            return get_temperature_from_modem_FM350(at_port);
        break;
        case MODEM_T99W373:
            return get_temperature_from_modem_T99W373(at_port);
        break;
        default:
            return -1;
        break;
    }
    return -1;
}

/**
 * 主函数
 */
int main(int argc, char* argv[]) {
    // 解析命令行选项
    int opt;
    while ((opt = getopt(argc, argv, "a:D:F:s:t:m:M:v:")) != -1) {
        switch (opt) {
            case 'a':
                snprintf(at_port, sizeof(at_port), "%s", optarg);
                break;
            case 'D':
                snprintf(modem_device, sizeof(modem_device), "%s", optarg);
                // 根据device名称选择设备
                if(strcmp(modem_device,"FM350") == 0){
                    modem=MODEM_FM350;
                } else if(strcmp(modem_device,"T99W373") == 0){
                    modem=MODEM_T99W373;
                } else {
                    fprintf(stderr, "Unknown modem device: %s\n", modem_device);
                    exit(EXIT_FAILURE);
                }
                break;
            case 'F':
                snprintf(fan_file, sizeof(fan_file), "%s", optarg);
                break;
            case 's':
                start_speed = atoi(optarg);
                break;
            case 't':
                start_temp = atoi(optarg);
                break;
            case 'm':
                max_speed = atoi(optarg);
                break;
            case 'M':
                debug_mode = atoi(optarg);
                break;
            case 'v':
                debug_mode = 1;
                break;
            default:
                fprintf(stderr, "Usage: %s [option]\n"
                    "          -a AT port       # modem device's AT Port ,default is '%s'\n"
                    "          -D device        # modem device path, default is '%s'\n"
                    "          -F sysfs         # fan sysfs file, default is '%s'\n"
                    "          -s speed         # initial speed for fan startup, default is %d\n"
                    "          -t temperature   # fan start temperature, default is %d°C\n"
                    "          -m speed         # fan maximum speed, default is %d\n"
                    "          -M mode          # debug mode (0/1), default is %d\n"
                    "          -v               # verbose (same as -M 1)\n", 
                    argv[0],at_port, modem_device, fan_file, start_speed, start_temp, max_speed, debug_mode);
                exit(EXIT_FAILURE);
        }
    }
    
    // 检测风扇控制文件是否存在
    if (file_exist(fan_file) != 0) {
        fprintf(stderr, "Fan control file: '%s' does not exist\n", fan_file);
        exit(EXIT_FAILURE);
    }

    // 初始化ubus客户端
    if (init_global_ubus_client() != 0) {
        fprintf(stderr, "Failed to initialize ubus client\n");
        exit(EXIT_FAILURE);
    }
    printf("Ubus client initialized successfully\n");

    // 注册退出信号
    register_signal_handlers();

    printf("Starting fan control using modem temperature sensors\n");
    printf("AT Port: %s\n",at_port);
    printf("Modem device: %s\n", modem_device);
    printf("Fan control file: %s\n", fan_file);
    printf("Start temperature: %d°C\n", start_temp);
    printf("Start speed: %d\n", start_speed);
    printf("Max speed: %d\n", max_speed);

    // 开机默认设置为30度，以免风扇满速运行
    int fan_speed = calculate_speed(30, MAX_TEMP, start_temp, max_speed, start_speed);
    set_fanspeed(fan_speed, fan_file);

    // 监控风扇
    while (1) {
        
        // 获取当前温度
        int temperature = get_current_temperature();
        
        if (temperature > 0) {
            if (debug_mode) {
                printf("Current temperature: %d°C\n", temperature);
            }
            
            // 计算并设置风扇速度
            int fan_speed = calculate_speed(temperature, MAX_TEMP, start_temp, max_speed, start_speed);
            set_fanspeed(fan_speed, fan_file);
            
            if (debug_mode) {
                int current_speed = get_fanspeed(fan_file);
                printf("Setting fan speed: %d (current: %d)\n", fan_speed, current_speed);
            }
        } else if (debug_mode) {
            printf("Failed to get valid temperature data\n");
        }
        
        sleep(5);
    }
    
    return 0;
}