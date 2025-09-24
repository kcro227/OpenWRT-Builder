# Fancontrol
Openwrt简易通用风扇控制，原理是读取系统温度，然后根据不同温度进行插值线性无级别调节风扇速度，测速使用bpi-R4正常。
修改于https://github.com/JiaY-shi/fancontrol

## 安装步骤
###  Add this repo as an OpenWrt feed

1. Add new feed:
    ```bash
    echo "src-git fancontrol https://github.com/rockjake/luci-app-fancontrol.git" >> "feeds.conf"
    ```
2. Pull upstream commits:
    ```bash
    ./scripts/feeds update fancontrol && ./scripts/feeds install -a -f -p fancontrol
    ```
- Remove
    ```bash
    sed -i "/fancontrol/d" "feeds.conf"
    ./scripts/feeds clean && ./scripts/feeds update -a && ./scripts/feeds install -a
    ```
## 预览
![图片](./images/0.png)
