#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
#include "ubus_client.h"

int main(int argc, char *argv[]) {
    // 初始化全局ubus客户端
    if (init_global_ubus_client() != 0) {
        fprintf(stderr, "Failed to initialize ubus client\n");
        return -1;
    }
    printf("Ubus client initialized successfully\n");

    // 打开AT设备（假设设备路径为/dev/ttyUSB2）
    const char *device_path = "/dev/ttyUSB1";
    if (ubus_at_open_device(get_global_ubus_client(), device_path, 115200, 8, 0, 1) != 0) {
        fprintf(stderr, "Failed to open AT device: %s\n", device_path);
        cleanup_global_ubus_client();
        return -1;
    }
    printf("AT device opened: %s\n", device_path);

    // 发送ATI命令并等待响应
    const char *at_cmd = "ATI";
    ubus_at_response_t response;
    
    printf("Sending AT command: %s\n", at_cmd);
    int result = ubus_send_at_command(get_global_ubus_client(), device_path, 
                                     at_cmd, 5, "OK", 0, &response);
    
    // 处理响应
    if (result == 0) {
        printf("Command executed successfully\n");
        printf("Response: %s\n", response.response ? response.response : "(null)");
        printf("End flag matched: %s\n", response.end_flag_matched ? response.end_flag_matched : "(null)");
        printf("Response time: %ld ms\n", response.response_time_ms);
    } else {
        printf("Command failed or timed out\n");
        if (response.response) {
            printf("Partial response: %s\n", response.response);
        }
    }
    
    // 释放响应资源
    ubus_at_response_free(&response);
    
    // 关闭设备
    if (ubus_at_close_device(get_global_ubus_client(), device_path) != 0) {
        fprintf(stderr, "Warning: Failed to close AT device: %s\n", device_path);
    } else {
        printf("AT device closed: %s\n", device_path);
    }
    
    // 清理ubus客户端
    cleanup_global_ubus_client();
    printf("Ubus client cleaned up\n");
    
    return result;
}