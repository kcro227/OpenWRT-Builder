#ifndef _MODULES_H_
#define _MODULES_H_

typedef enum modem_t
{
    MODEM_NONE,
    MODEM_FM350,
    MODEM_T99W373,
}modem_t;

// FM350获取温度
int get_temperature_from_modem_FM350(char *at_port);

// T99W373
int get_temperature_from_modem_T99W373(char *at_port);

#endif
