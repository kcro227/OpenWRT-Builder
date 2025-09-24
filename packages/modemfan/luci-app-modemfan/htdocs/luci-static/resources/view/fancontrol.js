'use strict';
'require view';
'require fs';
'require form';
'require uci';
'require rpc';

const FAN_FILE_PLACEHOLDER = '/sys/devices/platform/pwm-fan/hwmon/hwmon0/pwm1';
const AT_PORT = '/dev/ttyUSB1';
const DEVICES_JSON = '/usr/share/luci/applications/luci-app-modemfan/devices.json';

// 创建RPC调用方法
var callFileRead = rpc.declare({
    object: 'file',
    method: 'read',
    params: ['path'],
    expect: { data: '' }
});

// 读取设备列表
async function loadDevices() {
    try {
        // 使用RPC调用读取文件
        const response = await callFileRead('/usr/share/luci/applications/luci-app-modemfan/devices.json');
        if (response && response.data) {
            return JSON.parse(response.data);
        }
    } catch (err) {
        console.error('Failed to load devices:', err);
    }
    
    // 返回默认设备列表作为后备
    return [
        {value: "FM350", name: "Fibocom FM350"},
        {value: "T99W373", name: "Foxconn T99W373"}
    ];
}

async function readFile(filePath) {
    try {
        const rawData = await fs.read_direct(filePath);
        return parseInt(rawData);
    } catch (err) {
        return null; // 返回null表示读取失败
    }
}

return view.extend({
    load: function() {
        return Promise.all([uci.load('fancontrol')]);
    },
    render: async function(data) {
        const m = new form.Map('fancontrol', _('Fan General Control'));
        
        const s = m.section(form.TypedSection, 'fancontrol', _('Settings'));
        s.anonymous = true;

        // 加载设备列表
        const devices = await loadDevices();
        
        // Enabled option
        let o = s.option(form.Flag, 'enable', _('Enable'), _('Enable'));
        o.rmempty = false;

        // 设备选择框
        o = s.option(form.ListValue, 'modem_device', _('Modem Device'), _('Select your modem device'));
        for (const device of devices) {
            o.value(device.value, device.name);
        }
        
        o = s.option(form.Value, 'at_port', _('AT Port'), _('AT Port'));
        o.placeholder = AT_PORT;
        
        // Fan file option
        o = s.option(form.Value, 'fan_file', _('Fan Speed File'), _('Fan Speed File'));
        o.placeholder = FAN_FILE_PLACEHOLDER;

        // 获取风扇文件路径
        const fanFile = uci.get('fancontrol', '@fancontrol[0]', 'fan_file') || 
                       uci.get('fancontrol', 'settings', 'fan_file') || 
                       FAN_FILE_PLACEHOLDER;
        
        // 读取风扇速度
        const speed = await readFile(fanFile);
        if (speed !== null && !isNaN(speed)) {
            o.description = _('Current speed:') + ` <b>${(speed / 255 * 100).toFixed(2)}%</b> (${speed})`;
        } else {
            o.description = _('Cannot read fan speed file');
        }

        
        o = s.option(form.Value, 'start_speed', _('Initial Speed'), _('Please enter the initial speed for fan startup.'));
        o.placeholder = '35';
        o.datatype = 'range(0, 255)';
        
        o = s.option(form.Value, 'max_speed', _('Max Speed'), _('Please enter maximum fan speed (0-255).'));
        o.placeholder = '255';
        o.datatype = 'range(0, 255)';
        
        o = s.option(form.Value, 'start_temp', _('Start Temperature'), _('Please enter the fan start temperature.'));
        o.placeholder = '45';
        o.datatype = 'ufloat';

        return m.render();
    }
});