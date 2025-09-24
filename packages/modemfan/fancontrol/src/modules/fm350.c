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
int parse_temperature_response_FM350(const char* response) {
    if (!response) return -1;
    
    char* copy = strdup(response);
    char* line = strtok(copy, "\n");
    int total_temp = 0;
    int valid_sensors = 0;
    
    while (line != NULL) {
        // 查找+GTSENRDTEMP行
        if (strstr(line, "+GTSENRDTEMP:") != NULL) {
            // 找到逗号位置
            char* comma = strchr(line, ',');
            if (comma != NULL) {
                int sensor_id, temp_value;
                if (sscanf(line, "+GTSENRDTEMP: %d,%d", &sensor_id, &temp_value) == 2) {
                    // 忽略值为0的传感器
                    if (temp_value > 0) {
                        total_temp += temp_value;
                        valid_sensors++;
                    }
                }
            }
        }
        line = strtok(NULL, "\n");
    }
    
    free(copy);
    
    if (valid_sensors > 0) {
        // 计算平均温度（转换为摄氏度，假设原始值是千分之一摄氏度）
        return (total_temp / valid_sensors) / 1000;
    }
    
    return -1;
}

/**
 * 通过AT指令获取温度
 */
int get_temperature_from_modem_FM350(char * at_port) {
    ubus_client_t* client = get_global_ubus_client();
    if (!client || !client->connected) {
        fprintf(stderr, "Ubus client not connected\n");
        return -1;
    }
    
    ubus_at_response_t response;
    memset(&response, 0, sizeof(response));
    
    // 发送AT指令获取温度
    int result = ubus_send_at_command(client, at_port, 
                                     "AT+GTSENRDTEMP=0", 10, "OK", 0, &response);
    
    int temperature = -1;
    if (result == 0 && response.response) {
        if (debug_mode) {
            printf("AT Response: %s\n", response.response);
        }
        temperature = parse_temperature_response_FM350(response.response);
    } else {
        fprintf(stderr, "Failed to get temperature from modem\n");
    }
    
    ubus_at_response_free(&response);
    return temperature;
}
