#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <sys/stat.h>
#include <signal.h>
#include <time.h>
#include "../ubus_client.h"

extern int debug_mode ;

/**
 * 解析AT指令响应，提取温度值 
 */
int parse_temperature_response_T99W373(const char* response) {
    if (!response) return -1;
    
    char* copy = strdup(response);
    char* line = strtok(copy, "\n");
    int temperature = -1;
    
    while (line != NULL) {
        // 查找TSENS行
        if (strstr(line, "TSENS:") != NULL) {
            // 提取温度值（去掉'C'字符）
            char* temp_start = strchr(line, ':');
            if (temp_start != NULL) {
                temp_start++; // 跳过冒号
                // 移除可能的前导空格
                while (*temp_start == ' ') temp_start++;
                
                // 提取数字部分
                char temp_str[10] = {0};
                int i = 0;
                while (*temp_start != '\0' && *temp_start != 'C' && i < sizeof(temp_str) - 1) {
                    temp_str[i++] = *temp_start++;
                }
                
                // 转换为整数
                temperature = atoi(temp_str);
                break; // 找到TSENS温度后即可退出循环
            }
        }
        line = strtok(NULL, "\n");
    }
    
    free(copy);
    return temperature;
}

/**
 * 通过AT指令获取温度
 */
int get_temperature_from_modem_T99W373(char *at_port) {
    ubus_client_t* client = get_global_ubus_client();
    if (!client || !client->connected) {
        fprintf(stderr, "Ubus client not connected\n");
        return -1;
    }
    
    ubus_at_response_t response;
    memset(&response, 0, sizeof(response));
    
    // 发送AT指令获取温度
    int result = ubus_send_at_command(client, at_port, 
                                     "AT^TEMP?", 10, "OK", 0, &response);
    
    int temperature = -1;
    if (result == 0 && response.response) {
        if (debug_mode) {
            printf("AT Response: %s\n", response.response);
        }
        temperature = parse_temperature_response_T99W373(response.response);
    } else {
        fprintf(stderr, "Failed to get temperature from modem\n");
    }
    
    ubus_at_response_free(&response);
    return temperature;
}
