import asyncio
import socket
import re
import aiohttp
import time
from abc import ABC, abstractmethod
from dataclasses import dataclass, asdict
from typing import Dict, List, Optional
import websockets
import json
from io import StringIO
import sys
import serial
import os
from datetime import datetime
import http.server
import socketserver
import threading
import shutil
import atexit

DEFAULT_CONFIG = {
    "AT_CONFIG": {
        "TYPE": "NETWORK",  # 可选值: "NETWORK" 或 "SERIAL"
        "NETWORK": {
            "HOST": "192.168.8.1",
            "PORT": 20249,
            "TIMEOUT": 10
        },
        "SERIAL": {
            "PORT": "COM6",  # 串口设备路径
            "BAUDRATE": 115200,  # 波特率
            "TIMEOUT": 10
        }
    },
    "NOTIFICATION_CONFIG": {
        "WECHAT_WEBHOOK": "", # 企业微信webhook地址 不填写代表不启用
        "LOG_FILE": "notifications.log", # 短信通知日志文件路径 不填写代表不启用
        "NOTIFICATION_TYPES": {
            "SMS": True,          # 是否推送短信通知
            "CALL": True,         # 是否推送来电通知
            "MEMORY_FULL": True,  # 是否推送存储空间满通知
            "SIGNAL": True        # 是否推送信号变化通知
        }
    },
    # WebSocket 配置
    "WEBSOCKET_CONFIG": {
        "IPV4": {
            "HOST": "0.0.0.0",
            "PORT": 8765
        },
        "IPV6": {
            "HOST": "::",
            "PORT": 8765
        }
    },
    # HTTP 服务器配置
    "HTTP_SERVER": {
        "PORT": 8001
    }
}

def load_config():
    """加载配置文件"""
    if getattr(sys, 'frozen', False):
        config_path = os.path.join(os.path.dirname(sys.executable), 'config.json')
    else:
        config_path = os.path.join(os.path.dirname(os.path.abspath(__file__)), 'config.json')
    
    try:
        with open(config_path, 'r', encoding='utf-8') as f:
            config = json.load(f)
            # 验证配置文件格式
            if validate_and_fix_config(config, DEFAULT_CONFIG):
                print("配置文件验证通过")
                return config
            else:
                print("配置文件格式不完整，已自动修复")
                # 保存修复后的配置
                with open(config_path, 'w', encoding='utf-8') as f:
                    json.dump(config, f, indent=4, ensure_ascii=False)
                return config
    except FileNotFoundError:
        print(f"配置文件不存在，将在 {config_path} 创建默认配置文件")
        try:
            with open(config_path, 'w', encoding='utf-8') as f:
                json.dump(DEFAULT_CONFIG, f, indent=4, ensure_ascii=False)
            print("默认配置文件已创建")
            return DEFAULT_CONFIG
        except Exception as e:
            print(f"创建配置文件失败: {e}")
            return DEFAULT_CONFIG
    except Exception as e:
        print(f"加载配置文件失败: {e}，将使用默认配置")
        return DEFAULT_CONFIG

def validate_and_fix_config(config, default_config):
    """验证并修复配置文件，确保所有必要的配置项都存在"""
    all_valid = True
    
    # 递归检查并修复字典
    def check_and_fix_dict(config_dict, default_dict):
        nonlocal all_valid
        fixed = False
        
        # 确保所有默认配置中的键都存在于当前配置中
        for key, default_value in default_dict.items():
            if key not in config_dict:
                print(f"配置缺失项: {key}，使用默认值")
                config_dict[key] = default_value
                all_valid = False
                fixed = True
            elif isinstance(default_value, dict) and isinstance(config_dict[key], dict):
                # 递归检查子字典
                if check_and_fix_dict(config_dict[key], default_value):
                    fixed = True
        
        return fixed
    
    # 开始验证和修复
    check_and_fix_dict(config, default_config)
    
    return all_valid

# 加载配置
config = load_config()
AT_CONFIG = config['AT_CONFIG']
NOTIFICATION_CONFIG = config['NOTIFICATION_CONFIG']
HTTP_SERVER = config['HTTP_SERVER']


# GSM 7-bit 默认字母表
GSM_7BIT_ALPHABET = (
    "@£$¥èéùìòÇ\nØø\rÅåΔ_ΦΓΛΩΠΨΣΘΞ\x1bÆæßÉ !\"#¤%&'()*+,-./0123456789:;<=>?"
    "¡ABCDEFGHIJKLMNOPQRSTUVWXYZÄÖÑÜ§¿abcdefghijklmnopqrstuvwxyzäöñüà"
)

def decode_7bit(encoded_bytes, length):
    """解码7位GSM编码"""
    result = []
    shift = 0
    tmp = 0

    for byte in encoded_bytes:
        tmp |= byte << shift
        shift += 8

        while shift >= 7:
            result.append(tmp & 0x7F)
            tmp >>= 7
            shift -= 7

    if shift > 0 and len(result) < length:
        result.append(tmp & 0x7F)

    return ''.join(GSM_7BIT_ALPHABET[b] if b < len(GSM_7BIT_ALPHABET) else '?' for b in result[:length])

def decode_ucs2(encoded_bytes):
    """解码UCS2编码"""
    try:
        return encoded_bytes.decode('utf-16-be')
    except:
        return '?' * (len(encoded_bytes) // 2)

def decode_timestamp(timestamp_bytes):
    """解码时间戳"""
    try:
        year = f"20{((timestamp_bytes[0] & 0x0F) * 10) + (timestamp_bytes[0] >> 4)}"
        month = f"{((timestamp_bytes[1] & 0x0F) * 10) + (timestamp_bytes[1] >> 4):02d}"
        day = f"{((timestamp_bytes[2] & 0x0F) * 10) + (timestamp_bytes[2] >> 4):02d}"
        hour = f"{((timestamp_bytes[3] & 0x0F) * 10) + (timestamp_bytes[3] >> 4):02d}"
        minute = f"{((timestamp_bytes[4] & 0x0F) * 10) + (timestamp_bytes[4] >> 4):02d}"
        second = f"{((timestamp_bytes[5] & 0x0F) * 10) + (timestamp_bytes[5] >> 4):02d}"
        
        return datetime.strptime(f"{year}-{month}-{day} {hour}:{minute}:{second}", 
                               "%Y-%m-%d %H:%M:%S")
    except:
        return datetime.now()

def decode_number(number_bytes, number_length):
    """解码电话号码"""
    number = ''
    for byte in number_bytes:
        digit1 = byte & 0x0F
        digit2 = byte >> 4
        if digit1 <= 9:
            number += str(digit1)
        if len(number) < number_length and digit2 <= 9:
            number += str(digit2)
    return number

def read_incoming_sms(pdu_hex):
    """解析收到的短信PDU"""
    try:
        # 转换PDU为字节数组
        pdu_bytes = bytes.fromhex(pdu_hex)
        pos = 0

        # 跳过SMSC信息
        smsc_length = pdu_bytes[pos]
        pos += 1 + smsc_length

        # PDU类型
        pdu_type = pdu_bytes[pos]
        pos += 1

        # 发送者号码长度和类型
        sender_length = pdu_bytes[pos]
        pos += 1
        sender_type = pdu_bytes[pos]
        pos += 1

        # 解码发送者号码
        sender_bytes = pdu_bytes[pos:pos + (sender_length + 1) // 2]
        sender = decode_number(sender_bytes, sender_length)
        pos += (sender_length + 1) // 2

        # 跳过协议标识符
        pos += 1

        # 数据编码方案
        dcs = pdu_bytes[pos]
        is_ucs2 = (dcs & 0x0F) == 0x08
        pos += 1

        # 时间戳
        timestamp = decode_timestamp(pdu_bytes[pos:pos + 7])
        pos += 7

        # 用户数据长度和内容
        data_length = pdu_bytes[pos]
        pos += 1
        data_bytes = pdu_bytes[pos:]

        # 检查是否是分段短信
        udh_length = 0
        partial_info = None
        
        if pdu_type & 0x40:  # 有用户数据头
            udh_length = data_bytes[0] + 1
            if udh_length >= 6:  # 最小的分段短信UDH长度
                iei = data_bytes[1]
                if iei == 0x00 or iei == 0x08:  # 分段短信标识
                    ref = data_bytes[3]
                    total = data_bytes[4]
                    seq = data_bytes[5]
                    partial_info = {
                        "reference": ref,
                        "parts_count": total,
                        "part_number": seq
                    }

        # 解码短信内容
        content_bytes = data_bytes[udh_length:]
        if is_ucs2:
            content = decode_ucs2(content_bytes)
        else:
            # 对于7位编码，需要调整实际长度
            actual_length = (data_length * 7) // 8
            if data_length * 7 % 8 != 0:
                actual_length += 1
            content = decode_7bit(content_bytes, data_length)

        return {
            'sender': sender,
            'content': content,
            'date': timestamp,
            'partial': partial_info
        }

    except Exception as e:
        print(f"PDU解码错误: {e}")
        return {
            'sender': 'unknown',
            'content': f'PDU解码失败: {pdu_hex}',
            'date': datetime.now(),
            'partial': None
        }



@dataclass
class SMS:
    """短信数据模型"""
    index: str
    sender: str
    content: str
    timestamp: str
    partial: Optional[dict] = None


@dataclass
class ATResponse:
    """AT命令响应数据模型"""
    success: bool
    data: str = None
    error: str = None

    def to_dict(self) -> dict:
        return asdict(self)


class NotificationChannel(ABC):
    """通知渠道基类"""

    @abstractmethod
    async def send(self, sender: str, content: str, is_memory_full: bool = False) -> bool:
        """发送通知"""
        pass


class WeChatNotification(NotificationChannel):
    """企业微信通知实现"""

    def __init__(self, webhook_url: str):
        if not webhook_url:
            raise ValueError("webhook URL 不能为空")
        self.webhook_url = webhook_url
        self.max_retries = 3
        self.retry_delay = 1
        self.send_interval = 60
        self._queue = asyncio.Queue()
        self._background_task = None
        self._running = False
        self._last_send_time = 0
        self._pending_messages = []

    async def start(self):
        """启动后台处理任务"""
        if not self._running:
            self._running = True
            self._background_task = asyncio.create_task(self._process_queue())

    async def stop(self):
        """停止后台处理任务"""
        self._running = False
        if self._background_task:
            self._background_task.cancel()
            try:
                await self._background_task
            except asyncio.CancelledError:
                pass
            self._background_task = None

    async def send(self, sender: str, content: str, is_memory_full: bool = False) -> bool:
        """将消息加入队列"""
        if not self._running:
            await self.start()
        await self._queue.put((sender, content, is_memory_full))
        return True

    async def _process_queue(self):
        """后台处理消息队列"""
        while self._running:
            try:
                try:
                    sender, content, is_memory_full = await asyncio.wait_for(
                        self._queue.get(), 
                        timeout=1.0
                    )
                    # 将消息添加到待发送列表
                    self._pending_messages.append((sender, content, is_memory_full))
                    self._queue.task_done()
                except asyncio.TimeoutError:
                    pass

                current_time = time.time()
                if (self._pending_messages and 
                    current_time - self._last_send_time >= self.send_interval):
                    combined_message = self._combine_messages(self._pending_messages)
                    asyncio.create_task(self._do_send("批量通知", combined_message, False))
                    self._last_send_time = current_time
                    self._pending_messages.clear()

                await asyncio.sleep(1)  

            except Exception as e:
                print(f"处理通知队列出错: {e}")
                await asyncio.sleep(1)

    def _combine_messages(self, messages) -> str:
        """合并多条消息"""
        if not messages:
            return ""
        if len(messages) == 1:
            sender, content, is_memory_full = messages[0]
            if is_memory_full:
                return "⚠️ 警告：短信存储空间已满\n请及时处理，否则可能无法接收新短信"
            elif sender == "来电提醒":
                return f"📞 来电提醒\n{content}"
            elif sender == "信号监控":
                return content
            else:
                return f"📱 新短信通知\n发送者: {sender}\n内容: {content}"

        combined = "📑 批量通知汇总\n" + "=" * 20 + "\n"
        for i, (sender, content, is_memory_full) in enumerate(messages, 1):
            if is_memory_full:
                combined += f"\n{i}. ⚠️ 存储空间已满警告"
            elif sender == "来电提醒":
                combined += f"\n{i}. 📞 {content}"
            elif sender == "信号监控":
                combined += f"\n{i}. 📶 {content}"
            else:
                combined += f"\n{i}. 📱 来自 {sender} 的短信:\n{content}"
            combined += "\n" + "-" * 20

        return combined

    async def _do_send(self, sender: str, content: str, is_memory_full: bool = False):
        """实际发送消息的方法"""
        retries = 0
        while retries < self.max_retries:
            try:
                timeout = aiohttp.ClientTimeout(total=5)
                connector = aiohttp.TCPConnector(
                    force_close=True,
                    enable_cleanup_closed=True,
                    ssl=False  # 添加 ssl=False 尝试解决可能的 SSL 问题
                )
                
                async with aiohttp.ClientSession(
                    timeout=timeout, 
                    connector=connector
                ) as session:
                    message = {
                        "msgtype": "text",
                        "text": {"content": content}
                    }
                    
                    async with session.post(
                        self.webhook_url,
                        json=message,
                        headers={
                            'Content-Type': 'application/json',
                            'User-Agent': 'Mozilla/5.0'
                        }
                    ) as response:
                        response_text = await response.text()
                        
                        if response.status == 200:
                            try:
                                result = await response.json()
                                if result.get('errcode') == 0:
                                    print(f"企业微信通知发送成功: {sender}")
                                    return
                                else:
                                    raise Exception(f"企业微信API错误: {result}")
                            except json.JSONDecodeError as je:
                                raise Exception(f"响应解析失败: {je}")
                        
                        raise Exception(f"HTTP错误 {response.status}: {response_text}")

            except Exception as e:
                if isinstance(e, (asyncio.TimeoutError, asyncio.CancelledError)):
                    print(f"请求被取消或超时: {str(e)}")
                    return
                    
                retries += 1
                print(f"发送失败 (尝试 {retries}/{self.max_retries}): {str(e)}")
                
                if retries < self.max_retries:
                    wait_time = self.retry_delay * retries
                    await asyncio.sleep(wait_time)
                else:
                    print(f"达到最大重试次数，放弃发送")
                    return


class LogNotification(NotificationChannel):
    """日志通知实现"""

    def __init__(self, log_file: str):
        self.log_file = log_file

    async def send(self, sender: str, content: str, is_memory_full: bool = False) -> bool:
        try:
            timestamp = time.strftime("%Y-%m-%d %H:%M:%S")
            if is_memory_full:
                log_content = f"[{timestamp}] 存储空间已满警告\n"
            else:
                log_content = f"[{timestamp}] 发送者: {sender}\n内容: {content}\n"

            with open(self.log_file, "a", encoding="utf-8") as f:
                f.write(log_content + "-" * 50 + "\n")
            return True
        except Exception as e:
            print(f"日志记录失败: {e}")
            return False


class NotificationManager:
    """通知管理器"""

    def __init__(self):        
        self.channels: List[NotificationChannel] = []
        self.notification_types = NOTIFICATION_CONFIG.get("NOTIFICATION_TYPES", {
            "SMS": True,
            "CALL": True,
            "MEMORY_FULL": True,
            "SIGNAL": True
        })
        
        # 检查企业微信 webhook 配置
        if NOTIFICATION_CONFIG.get("WECHAT_WEBHOOK"):
            self.channels.append(WeChatNotification(webhook_url=NOTIFICATION_CONFIG["WECHAT_WEBHOOK"]))
            
        # 检查日志文件配置
        if NOTIFICATION_CONFIG.get("LOG_FILE"):
            self.channels.append(LogNotification(NOTIFICATION_CONFIG["LOG_FILE"]))

    async def start(self):
        """启动所有通知渠道"""
        for channel in self.channels:
            if isinstance(channel, WeChatNotification):
                await channel.start()

    async def stop(self):
        """停止所有通知渠道"""
        for channel in self.channels:
            if isinstance(channel, WeChatNotification):
                await channel.stop()

    async def notify_all(self, sender: str, content: str, notification_type: str = "SMS", is_memory_full: bool = False):
        """向所有通知渠道发送消息
        
        Args:
            sender: 发送者
            content: 内容
            notification_type: 通知类型 ("SMS", "CALL", "MEMORY_FULL", "SIGNAL")
            is_memory_full: 是否是存储空间满通知
        """
        # 检查该类型的通知是否启用
        if not self.notification_types.get(notification_type, True):
            print(f"通知类型 {notification_type} 已禁用，跳过推送")
            return

        for channel in self.channels:
            await channel.send(sender, content, is_memory_full)


class MessageHandler(ABC):
    """消息处理器基类"""
    async def can_handle(self, line: str) -> bool:
        """判断是否可以处理该消息"""
        return False

    @abstractmethod
    async def handle(self, line: str, client: 'ATClient') -> None:
        """处理消息"""
        pass
class CallHandler(MessageHandler):
    """来电处理器"""

    def __init__(self):
        self.last_call_number = None
        self.last_call_time = 0
        self.call_timeout = 30  # 30秒内的重复来电不再通知
        self.ring_received = False  # 添加RING信号标志
        self.current_call_state = "idle"  # 添加通话状态跟踪

    async def can_handle(self, line: str) -> bool:
        return ("RING" in line or
                "IRING" in line or
                line.startswith("+CLIP:") or
                "^CEND:" in line or
                "NO CARRIER" in line)

    async def handle(self, line: str, client: 'ATClient') -> None:
        try:
            if "RING" in line or "IRING" in line:
                self.ring_received = True
                self.current_call_state = "ringing"

            elif line.startswith("+CLIP:"):
                if not self.ring_received:
                    
                    self.current_call_state = "ringing"

                match = re.search(r'\+CLIP: *"([^"]+)"', line)
                if match:
                    phone_number = match.group(1)
                    current_time = time.time()


                    should_notify = (
                            phone_number != self.last_call_number or
                            current_time - self.last_call_time > self.call_timeout or
                            self.current_call_state == "idle"
                    )

                    if should_notify:
                        self.last_call_number = phone_number
                        self.last_call_time = current_time
                        self.current_call_state = "ringing"

                        time_str = time.strftime("%Y-%m-%d %H:%M:%S")
                        content = f"时间：{time_str}\n号码：{phone_number}\n状态：来电振铃"

                        # 发送通知
                        await client.notification_manager.notify_all("来电提醒", content, "CALL")

                        # WebSocket推送
                        await client.websocket_server.broadcast({
                            "type": "incoming_call",
                            "data": {
                                "time": time_str,
                                "number": phone_number,
                                "state": "ringing"
                            }
                        })

            elif "^CEND:" in line or "NO CARRIER" in line:

                if self.last_call_number:
                    time_str = time.strftime("%Y-%m-%d %H:%M:%S")
                    content = f"时间：{time_str}\n号码：{self.last_call_number}\n状态：通话结束"

                    # 发送通话结束通知
                    await client.notification_manager.notify_all("来电提醒", content, "CALL")

                    # WebSocket推送通话结束状态
                    await client.websocket_server.broadcast({
                        "type": "incoming_call",
                        "data": {
                            "time": time_str,
                            "number": self.last_call_number,
                            "state": "ended"
                        }
                    })

                # 重置所有状态
                self.last_call_number = None
                self.last_call_time = 0
                self.ring_received = False
                self.current_call_state = "idle"

        except Exception as e:
            print(f"来电处理错误: {e}")


class MemoryFullHandler(MessageHandler):
    """存储空间满处理器"""

    def __init__(self):
        self.notified = False

    async def can_handle(self, line: str) -> bool:
        return ("CMS ERROR: 322" in line or
                "MEMORY FULL" in line or
                "^SMMEMFULL" in line)

    async def handle(self, line: str, client: 'ATClient') -> None:
        if not self.notified:
            await client.notification_manager.notify_all("", "", "MEMORY_FULL", is_memory_full=True)
            self.notified = True


class NewSMSHandler(MessageHandler):
    """新短信处理器"""

    async def can_handle(self, line: str) -> bool:
        return bool(re.match(r"\+CMTI: \"(ME|SM)\",(\d+)", line))

    async def handle(self, line: str, client: 'ATClient') -> None:
        match = re.match(r"\+CMTI: \"(ME|SM)\",(\d+)", line)
        if match:
            storage = match.group(1)
            index = match.group(2)
            print(f"收到新短信，存储区: {storage}，索引: {index}")

            # 处理短信
            command = f"AT+CMGR={index}\r\n"
            response = await client.send_command(command)
            sms_list = client._parse_sms(response)

            for sms in sms_list:
                # 发送通知
                if sms.partial:
                    await client._handle_partial_sms(sms)
                else:
                    await client.notification_manager.notify_all(sms.sender, sms.content, "SMS")

                    # WebSocket推送
                    await client.websocket_server.broadcast({
                        "type": "new_sms",
                        "data": {
                            "sender": sms.sender,
                            "content": sms.content,
                            "time": sms.timestamp
                        }
                    })


class PDCPDataHandler(MessageHandler):
    """PDCP数据信息处理器"""

    def __init__(self):
        self.enabled = False
        self.interval = 0

    async def can_handle(self, line: str) -> bool:
        return line.startswith("^PDCPDATAINFO:")

    async def handle(self, line: str, client: 'ATClient') -> None:
        try:
            # 解析PDCP数据信息
            parts = line.replace("^PDCPDATAINFO:", "").strip().split(",")
            if len(parts) >= 14:
                pdcp_data = {
                    "id": int(parts[0]),
                    "pduSessionId": int(parts[1]),
                    "discardTimerLen": int(parts[2]),
                    "avgDelay": float(parts[3]) / 10,  # 转换为毫秒
                    "minDelay": float(parts[4]) / 10,  # 转换为毫秒
                    "maxDelay": float(parts[5]) / 10,  # 转换为毫秒
                    "highPriQueMaxBuffTime": float(parts[6]) / 10,  # 转换为毫秒
                    "lowPriQueMaxBuffTime": float(parts[7]) / 10,  # 转换为毫秒
                    "highPriQueBuffPktNums": int(parts[8]),
                    "lowPriQueBuffPktNums": int(parts[9]),
                    "ulPdcpRate": int(parts[10]),
                    "dlPdcpRate": int(parts[11]),
                    "ulDiscardCnt": int(parts[12]),
                    "dlDiscardCnt": int(parts[13])
                }

                # WebSocket推送
                await client.websocket_server.broadcast({
                    "type": "pdcp_data",
                    "data": pdcp_data
                })

        except Exception as e:
            print(f"PDCP数据处理错误: {e}")


class NetworkSignalHandler(MessageHandler):
    """网络信号监控处理器"""

    def __init__(self):
        self.last_signal_data = None
        self.last_sys_mode = None
        self.signal_change_threshold = 1
        self.debug = True

    async def _get_monsc_info(self, client: 'ATClient') -> dict:
        """获取并解析MONSC信息"""
        try:
            response = await client.send_command("AT^MONSC\r\n")
            if response:
                text = response.decode('ascii', errors='ignore')
                for line in text.split('\n'):
                    if line.startswith('^MONSC:'):
                        parts = line.replace('^MONSC:', '').strip().split(',')
                        if len(parts) < 2:
                            return {}
                            
                        rat = parts[0].strip('"')
                        result = {"rat": rat}
                        
                        if rat == "NONE":
                            return result
                            
                        if rat == "NR":
                            if len(parts) >= 11:
                                result.update({
                                    "mcc": parts[1],
                                    "mnc": parts[2],
                                    "arfcn": parts[3],
                                    "cell_id": parts[5],
                                    "pci": int(parts[6], 16), 
                                    "tac": parts[7],
                                    "rsrp": int(parts[8]),
                                    "rsrq": float(parts[9]),
                                    "sinr": float(parts[10]) if parts[10] else None
                                })
                        elif rat == "LTE":
                            if len(parts) >= 10:
                                result.update({
                                    "mcc": parts[1],
                                    "mnc": parts[2],
                                    "arfcn": parts[3],
                                    "cell_id": parts[4],
                                    "pci": int(parts[5], 16),  
                                    "tac": parts[6],
                                    "rsrp": int(parts[7]),
                                    "rsrq": int(parts[8]),
                                    "rssi": int(parts[9])
                                })
                        return result
            return {}
        except Exception as e:
            print(f"解析MONSC信息错误: {e}")
            return {}


        return scs_map.get(scs_value, "未知")

    async def _send_notification(self, signal_data, current_sys_mode, client):
        """发送信号变动通知"""
        try:
            monsc_info = await self._get_monsc_info(client)
            
            rsrp = signal_data.get("rsrp", 0)
            signal_level = "优秀" if rsrp >= -85 else \
                         "良好" if rsrp >= -95 else \
                         "一般" if rsrp >= -105 else \
                         "较差"

            message = (
                f"📶 信号变动通知\n"
                f"时间: {time.strftime('%Y-%m-%d %H:%M:%S')}\n"
                f"制式: {monsc_info.get('rat', '未知')}\n"
                f"信号: {signal_level}\n"
            )

            if monsc_info.get("rat") == "NR":
                message += (
                    f"RSRP: {monsc_info.get('rsrp', 0)} dBm\n"
                    f"RSRQ: {monsc_info.get('rsrq', 0)} dB\n"
                    f"SINR: {monsc_info.get('sinr', 0)} dB\n"
                    f"\n📡 小区信息:\n"
                    f"频点: {monsc_info.get('arfcn', '未知')}\n"
                    f"PCI: {monsc_info.get('pci', '未知')}\n"
                    f"TAC: {monsc_info.get('tac', '未知')}\n"
                    f"小区ID: {monsc_info.get('cell_id', '未知')}"
                )
            elif monsc_info.get("rat") == "LTE":
                message += (
                    f"RSRP: {monsc_info.get('rsrp', 0)} dBm\n"
                    f"RSRQ: {monsc_info.get('rsrq', 0)} dB\n"
                    f"RSSI: {monsc_info.get('rssi', 0)} dBm\n"
                    f"\n📡 小区信息:\n"
                    f"频点: {monsc_info.get('arfcn', '未知')}\n"
                    f"PCI: {monsc_info.get('pci', '未知')}\n"
                    f"TAC: {monsc_info.get('tac', '未知')}\n"
                    f"小区ID: {monsc_info.get('cell_id', '未知')}"
                )

            if current_sys_mode != self.last_sys_mode:
                message = f"⚡ 网络切换提醒\n{message}"

            await client.notification_manager.notify_all("信号监控", message, "SIGNAL")

        except Exception as e:
            print(f"发送通知错误: {e}")

    async def handle(self, line: str, client: 'ATClient') -> None:
        """处理信号相关的AT命令响应"""
        try:
            line = line.split('\n')[0] 
            signal_data = {}
            current_sys_mode = None
            force_notify = False

            if "^CERSSI:" in line:
                parts = line.replace('^CERSSI:', '').strip().split(',')
                if len(parts) >= 19: 
                    rsrp = int(parts[18])  
                    rsrq = int(parts[19])
                    sinr = int(parts[20]) if len(parts) > 20 else 0 
                    
                    signal_data = {
                        "sys_mode": "4G/5G",
                        "rsrp": rsrp,
                        "rsrq": rsrq,
                        "sinr": sinr
                    }
                    current_sys_mode = "4G/5G"

            elif "^HCSQ:" in line:
                parts = line.replace('^HCSQ:', '').strip().split(',')
                if len(parts) >= 4:
                    sys_mode = parts[0].strip('"')
                    rsrp_raw = int(parts[1])
                    sinr_raw = int(parts[2])
                    rsrq_raw = int(parts[3])
                    
                    rsrp = -140 + rsrp_raw
                    sinr = sinr_raw * 0.2 - 20
                    rsrq = rsrq_raw * 0.5 - 20
                    
                    signal_data = {
                        "sys_mode": sys_mode,
                        "rsrp": rsrp,
                        "rsrq": rsrq,
                        "sinr": sinr
                    }
                    current_sys_mode = sys_mode

            if signal_data:
                if self.debug:
                    print(f"信号数据: {signal_data}")

                if self.last_signal_data is None:
                    force_notify = True
                else:
                    rsrp_change = abs(signal_data['rsrp'] - self.last_signal_data['rsrp'])
                    if rsrp_change >= self.signal_change_threshold:
                        force_notify = True
                if current_sys_mode != self.last_sys_mode:
                    force_notify = True

                if force_notify:
                    await self._send_notification(signal_data, current_sys_mode, client)
                    self.last_signal_data = signal_data.copy()
                    self.last_sys_mode = current_sys_mode

        except Exception as e:
            print(f"信号处理错误: {e}")

    async def can_handle(self, line: str) -> bool:
        return "^CERSSI:" in line or "^HCSQ:" in line


class MessageProcessor:
    """消息处理器管理类"""

    def __init__(self):
        self.handlers = [
            CallHandler(),          # 处理来电通知，包括来电号码显示和通话状态变化
            MemoryFullHandler(),    # 处理存储空间满的警告，当短信存储空间不足时发出提醒
            NewSMSHandler(),        # 处理新短信通知，包括接收和解析短信内容
            NetworkSignalHandler()  # 处理网络信号变化，监控信号强度、网络制式切换等
        ]

    async def process(self, line: str, client: 'ATClient') -> None:
        for handler in self.handlers:
            if await handler.can_handle(line):
                await handler.handle(line, client)
                break


class ATConnection(ABC):
    """AT连接基类"""
    
    def __init__(self):
        self.is_connected = False
        self._response_buffer = bytearray()
        self._last_command_time = 0
        self.command_interval = 0.1  
        self.response_timeout = 2.0  # 2秒
        self._command_lock = asyncio.Lock()

    @abstractmethod
    async def connect(self) -> bool:
        """建立连接"""
        pass

    @abstractmethod
    async def close(self):
        """关闭连接"""
        pass

    @abstractmethod
    async def send(self, data: bytes) -> int:
        """发送数据"""
        pass

    @abstractmethod
    async def receive(self, size: int) -> bytes:
        """接收数据"""
        pass

    async def send_command(self, command: str) -> bytearray:
        """发送AT命令"""
        try:
            if not self.is_connected:
                if not await self.connect():
                    return bytearray()

            async with self._command_lock:
                # 强制等待上一个命令的间隔
                now = time.time()
                time_since_last = now - self._last_command_time
                if time_since_last < self.command_interval:
                    await asyncio.sleep(self.command_interval - time_since_last)

                if not command.endswith('\r'):
                    command += '\r'

                # 清空接收缓冲区
                self._response_buffer.clear()
                
                # 发送命令
                await self.send(command.encode())
                self._last_command_time = time.time()

                # 等待响应
                response = bytearray()
                start_time = time.time()
                
                while (time.time() - start_time) < self.response_timeout:
                    try:
                        chunk = await self.receive(4096)
                        if chunk:
                            response.extend(chunk)
                            # 检查是否收到完整响应
                            if (b'OK\r\n' in response or 
                                b'ERROR\r\n' in response or 
                                b'+CMS ERROR:' in response or 
                                b'+CME ERROR:' in response):
                                # 额外等待一小段时间，确保接收到所有数据
                                await asyncio.sleep(0.01)
                                return response

                    except Exception as e:
                        print(f"接收数据错误: {e}")
                        await asyncio.sleep(0.01)
                        continue

                if not response:
                    self.is_connected = False
                    raise ConnectionError("未收到响应")
                
                return response

        except Exception as e:
            self.is_connected = False
            print(f"命令发送失败: {e}")
            await asyncio.sleep(1)
            return bytearray()


class NetworkATConnection(ATConnection):
    """网络AT连接实现"""

    def __init__(self, host: str, port: int, timeout: int):
        super().__init__()
        self.host = host
        self.port = port
        self.timeout = timeout
        self.socket = None

    async def connect(self) -> bool:
        try:
            if self.socket:
                try:
                    self.socket.close()
                except:
                    pass
            
            self.socket = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
            self.socket.settimeout(self.timeout)
            self.socket.connect((self.host, self.port))
            self.socket.setblocking(False)
            self.is_connected = True
            print(f"已连接到网络AT {self.host}:{self.port}")
            return True
        except Exception as e:
            print(f"网络AT连接失败: {e}")
            return False

    async def close(self):
        if self.socket:
            self.socket.close()
            self.socket = None
            self.is_connected = False

    async def send(self, data: bytes) -> int:
        if not self.socket:
            raise ConnectionError("未连接")
        return self.socket.send(data)

    async def receive(self, size: int) -> bytes:
        if not self.socket:
            raise ConnectionError("未连接")
        try:
            self.socket.settimeout(0.1)
            return self.socket.recv(size)
        except (socket.timeout, BlockingIOError):
            return b""

class SerialATConnection(ATConnection):
    """串口AT连接实现"""
    def __init__(self, port: str, baudrate: int, timeout: int):
        super().__init__()
        self.port = port
        self.baudrate = baudrate
        self.timeout = timeout
        self.serial_port = None
    async def connect(self) -> bool:
        try:
            if self.serial_port and self.serial_port.is_open:
                try:
                    self.serial_port.close()
                except:
                    pass
            
            self.serial_port = serial.Serial(
                port=self.port,
                baudrate=self.baudrate,
                timeout=self.timeout
            )
            self.is_connected = True
            print(f"已连接到串口AT {self.port}")
            return True
        except Exception as e:
            print(f"串口AT连接失败: {e}")
            return False

    async def close(self):
        if self.serial_port and self.serial_port.is_open:
            self.serial_port.close()
            self.serial_port = None
            self.is_connected = False

    async def send(self, data: bytes) -> int:
        if not self.serial_port or not self.serial_port.is_open:
            raise ConnectionError("未连接")
        return self.serial_port.write(data)

    async def receive(self, size: int) -> bytes:
        if not self.serial_port or not self.serial_port.is_open:
            raise ConnectionError("未连接")
        if self.serial_port.in_waiting:
            return self.serial_port.read(self.serial_port.in_waiting)
        return b""
class ATClient:
    def __init__(self):
        self.connection_type = AT_CONFIG["TYPE"]
        if self.connection_type == "NETWORK":
            self.connection = NetworkATConnection(
                host=AT_CONFIG["NETWORK"]["HOST"],
                port=AT_CONFIG["NETWORK"]["PORT"],
                timeout=AT_CONFIG["NETWORK"]["TIMEOUT"]
            )
        else:  # SERIAL
            self.connection = SerialATConnection(
                port=AT_CONFIG["SERIAL"]["PORT"],
                baudrate=AT_CONFIG["SERIAL"]["BAUDRATE"],
                timeout=AT_CONFIG["SERIAL"]["TIMEOUT"]
            )

        self._partial_messages: Dict[str, Dict] = {}
        self.notification_manager = NotificationManager()
        self._lock = asyncio.Lock()
        self.websocket_server = None
        self._pdcp_handler = PDCPDataHandler()
        self._command_queue = asyncio.Queue()
        self.max_retries = 3
        self.retry_delay = 5

    @property
    def is_connected(self) -> bool:
        """获取连接状态"""
        return self.connection.is_connected if self.connection else False

    async def connect(self, retry=True):
        """建立连接并进行重试"""
        retries = 0
        while True:
            try:
                if await self.connection.connect():
                    await self._init_at_config()
                    return True
            except Exception as e:
                print(f"连接失败: {e}")
                if not retry or retries >= self.max_retries:
                    raise
                
                retries += 1
                retry_delay = self.retry_delay * retries
                print(f"等待 {retry_delay} 秒后尝试重新连接 ({retries}/{self.max_retries})...")
                await asyncio.sleep(retry_delay)

    async def send_command(self, command: str) -> bytearray:
        """发送AT命令"""
        return await self.connection.send_command(command)

    async def close(self):
        await self.connection.close()

    async def is_ready(self) -> bool:
        """检查AT模块是否准备就绪"""
        try:
            response = await self.send_command("AT+CPIN?\r\n")
            return b"+CPIN: READY" in response
        except:
            return False
    async def _init_at_config(self):
        """初始化AT命令配置"""
        cnmi_config = await self.send_command("AT+CNMI?\r\n")
        cmgf_config = await self.send_command("AT+CMGF?\r\n")
        if "+CNMI: 2,1,0,2,0" not in cnmi_config.decode('ascii', errors='ignore'):
            await self.send_command("AT+CNMI=2,1,0,2,0\r\n")
        if "+CMGF: 0" not in cmgf_config.decode('ascii', errors='ignore'):
            await self.send_command("AT+CMGF=0\r\n")
        await self.send_command("AT+CLIP=1\r\n")

    async def set_pdcp_data_info(self, enable: bool, interval: int = None) -> bool:
        try:
            command = f"AT^PDCPDATAINFO={1 if enable else 0}"
            if enable and interval is not None:
                if not (200 <= interval <= 65535):
                    print("上报间隔必须在200-65535毫秒之间")
                    return False
                command += f",{interval}"
            command += "\r\n"

            response = await self.send_command(command)
            success = b"OK" in response

            if success and self._pdcp_handler:
                self._pdcp_handler.enabled = enable
                if interval is not None:
                    self._pdcp_handler.interval = interval

            return success

        except Exception as e:
            print(f"设置PDCP数据信息上报失败: {e}")
            return False

    async def query_pdcp_data_info(self) -> bool:
        try:
            response = await self.send_command("AT^PDCPDATAINFO?\r\n")
            return b"OK" in response
        except Exception as e:
            print(f"查询PDCP数据信息失败: {e}")
            return False

    def _parse_sms(self, response: bytearray) -> List[SMS]:
        """解析PDU格式短信"""
        sms_list = []
        lines = response.decode('ascii', errors='ignore').split('\r\n')
        i = 0
        while i < len(lines):
            if lines[i].startswith('+CMG'):
                try:
                    pdu_hex = lines[i + 1].strip()
                    if pdu_hex and all(c in '0123456789ABCDEF' for c in pdu_hex):
                        sms_dict = read_incoming_sms(pdu_hex)
                        sms = SMS(
                            index="0",
                            sender=sms_dict['sender'],
                            content=sms_dict['content'],
                            timestamp=sms_dict['date'].strftime('%Y-%m-%d %H:%M:%S') if sms_dict.get(
                                'date') else "未知",
                            partial=sms_dict.get('partial') if isinstance(sms_dict.get('partial'), dict) else None
                        )
                        sms_list.append(sms)
                    i += 2
                except Exception as e:
                    print(f"PDU解析失败: {e}")
                    sms = SMS(
                        index="0",
                        sender="解析失败",
                        content=f"PDU解析错误: {str(e)}",
                        timestamp=time.strftime("%Y-%m-%d %H:%M:%S"),
                        partial=None
                    )
                    sms_list.append(sms)
                    i += 1
            else:
                i += 1
        return sms_list

    async def process_sms(self, index: str = None):
        """处理短信"""
        command = f"AT+CMGR={index}\r\n" if index else "AT+CMGL=0\r\n"
        response = await self.send_command(command)

        sms_list = self._parse_sms(response)
        for sms in sms_list:
            if sms.partial:
                await self._handle_partial_sms(sms)
            else:
                await self.notification_manager.notify_all(sms.sender, sms.content, "SMS")

    async def _handle_partial_sms(self, sms: SMS):
        """处理分段短信"""
        partial = sms.partial
        key = f"{sms.sender}_{partial['reference']}"
        if key not in self._partial_messages:
            self._partial_messages[key] = {
                "sender": sms.sender,
                "parts": {},
                "total_parts": partial["parts_count"]
            }
        self._partial_messages[key]["parts"][partial["part_number"]] = sms.content
        if len(self._partial_messages[key]["parts"]) == self._partial_messages[key]["total_parts"]:
            full_content = "".join(
                self._partial_messages[key]["parts"][i]
                for i in range(1, self._partial_messages[key]["total_parts"] + 1)
            )
            # 发送合并后的通知
            await self.notification_manager.notify_all(sms.sender, full_content, "SMS")
            # WebSocket推送完整消息
            await self.websocket_server.broadcast({
                "type": "new_sms",
                "data": {
                    "sender": sms.sender,
                    "content": full_content,
                    "time": sms.timestamp,
                    "isComplete": True
                }
            })

            del self._partial_messages[key]
class WebSocketServer:
    """WebSocket服务器类"""
    def __init__(self, at_client: ATClient):
        self.at_client = at_client
        self._active_connections = set()
        print("WebSocket服务器已初始化")
    async def broadcast(self, message: dict):
        """向所有连接的客户端广播消息"""
        if not self._active_connections:
            return
        for websocket in self._active_connections.copy():
            try:
                await websocket.send(json.dumps(message))
            except Exception as e:
                print(f"广播消息失败: {e}")
                try:
                    self._active_connections.remove(websocket)
                except:
                    pass
    async def handle_client(self, websocket, path=None):
        """处理WebSocket客户端连接"""
        self._active_connections.add(websocket)
        print("新的WebSocket客户端已连接")
        try:
            while True:
                try:
                    command = await asyncio.wait_for(websocket.recv(), timeout=1.0)
                    print(f"收到原始命令: {command}")
                    if command.startswith('AT^SYSCFGEX'):
                        command = command.replace('\n', '').replace('\r', '')
                        command = command.replace('OK', '')
                        if ',"",""' in command:
                            parts = command.split(',')
                            if len(parts) >= 5:
                                bands = parts[4].strip('"')
                                if bands and not isinstance(bands, str):
                                    bands = str(bands)
                                command = f"{parts[0]},{parts[1]},{parts[2]},{parts[3]},\"{bands}\",\"\",\"\""
                        command += '\r'
                    if command.strip() == "AT+CONNECT?":
                        connection_type = "0" if self.at_client.connection_type == "NETWORK" else "1"
                        response_text = f"+CONNECT: {connection_type}\r\nOK"
                        print(f"发送响应: {response_text}")
                        await websocket.send(json.dumps(ATResponse(
                            success=True,
                            data=response_text,
                            error=None
                        ).to_dict()))
                        continue

                    if not command.endswith('\r'):
                        command = command + '\r'
                    response = await self.at_client.send_command(command)
                    response_text = response.decode('ascii', errors='ignore')
                    response_lines = [line for line in response_text.split('\r\n')
                                    if line and line.strip() != command.strip()]
                    filtered_response = '\r\n'.join(response_lines)
                    print(f"命令响应: {filtered_response}")
                    # 发送响应
                    await websocket.send(json.dumps(ATResponse(
                        success='ERROR' not in filtered_response.upper(),
                        data=filtered_response if 'ERROR' not in filtered_response.upper() else None,
                        error=filtered_response if 'ERROR' in filtered_response.upper() else None
                    ).to_dict()))
                except websockets.exceptions.ConnectionClosed:
                    print("WebSocket客户端断开连接")
                    break
                except asyncio.TimeoutError:
                    continue
                except Exception as e:
                    error_msg = f"处理命令时出错: {str(e)}"
                    print(error_msg)
                    try:
                        await websocket.send(json.dumps(ATResponse(
                            success=False,
                            error=error_msg
                        ).to_dict()))
                    except:
                        break
        finally:
            self._active_connections.remove(websocket)
            print("WebSocket客户端连接已清理")
async def main():
    client = ATClient()
    websocket_server = WebSocketServer(client)
    client.websocket_server = websocket_server

    # 添加 HTTP 服务器
    class QuietHandler(http.server.SimpleHTTPRequestHandler):
        def log_message(self, format, *args):
            pass

    def start_http_server():
        try:
            # 切换到 web 目录
            web_dir = os.path.join(os.path.dirname(os.path.abspath(__file__)), 'web')
            os.chdir(web_dir)
            
            # 创建 HTTP 服务器
            http_server = socketserver.TCPServer(("", HTTP_SERVER["PORT"]), QuietHandler)
            print(f"HTTP 服务器已启动在端口 {HTTP_SERVER['PORT']}")
            http_server.serve_forever()
        except Exception as e:
            print(f"HTTP 服务器启动失败: {e}")

    # 创建 HTTP 服务器线程
    http_thread = threading.Thread(target=start_http_server, daemon=True)
    http_thread.start()

    # 原有的连接监控任务
    async def connection_monitor():
        """连接监控任务"""
        retry_interval = 10
        while True:
            try:
                if not client.is_connected:
                    print("检测到连接断开，尝试重新连接...")
                    try:
                        await client.connect(retry=False)  # 不使用内部重试机制
                        print("重新连接成功")
                    except Exception as e:
                        print(f"重新连接失败: {e}，将在 {retry_interval} 秒后重试")
                await asyncio.sleep(retry_interval)  # 每10秒检查一次连接状态
            except Exception as e:
                print(f"连接监控错误: {e}")
                await asyncio.sleep(retry_interval)

    try:
        await client.connect()
        message_processor = MessageProcessor()
        # 创建连接监控任务
        monitor_connection_task = asyncio.create_task(connection_monitor())
        # 读取WebSocket设置
        ws_config = config['WEBSOCKET_CONFIG']
        # 创建两个服务器实例，分别监听 IPv4 和 IPv6
        server_v4 = await websockets.serve(
            websocket_server.handle_client,
            ws_config['IPV4']['HOST'],
            ws_config['IPV4']['PORT'],
            ping_interval=None,
            ping_timeout=None
        )
        server_v6 = await websockets.serve(
            websocket_server.handle_client,
            ws_config['IPV6']['HOST'],
            ws_config['IPV6']['PORT'],
            ping_interval=None,
            ping_timeout=None
        )
        print("WebSocket服务器已启动")
        print(f"IPv4地址: ws://{ws_config['IPV4']['HOST']}:{ws_config['IPV4']['PORT']}")
        print(f"IPv6地址: ws://[{ws_config['IPV6']['HOST']}]:{ws_config['IPV6']['PORT']}")
        async def monitor_socket():
            try:
                while True:
                    try:
                        if client.connection_type == "NETWORK":
                            client.connection.socket.settimeout(0.1)
                            try:
                                data = client.connection.socket.recv(4096)
                                if data:
                                    line = data.decode('ascii', errors='ignore').strip()
                                    if line:
                                        await message_processor.process(line, client)
                                        await client.websocket_server.broadcast({
                                            "type": "raw_data",
                                            "data": line
                                        })
                            except socket.timeout:
                                await asyncio.sleep(0.01)
                            except BlockingIOError:
                                await asyncio.sleep(0.01)
                        else:  # SERIAL
                            if (isinstance(client.connection, SerialATConnection) and 
                                client.connection.serial_port and 
                                client.connection.serial_port.in_waiting):
                                data = client.connection.serial_port.read(
                                    client.connection.serial_port.in_waiting
                                )
                                if data:
                                    line = data.decode('ascii', errors='ignore').strip()
                                    if line:
                                        await message_processor.process(line, client)
                                        await client.websocket_server.broadcast({
                                            "type": "raw_data",
                                            "data": line
                                        })
                            await asyncio.sleep(0.01)
                    except Exception as e:
                        print(f"监控错误: {e}")
                        await asyncio.sleep(1)
            except asyncio.CancelledError:
                print("监控任务关闭")
                raise
        monitor_task = asyncio.create_task(monitor_socket())
        try:
            # 等待两个服务器都关闭
            await asyncio.gather(
                server_v4.wait_closed(),
                server_v6.wait_closed(),
                monitor_connection_task  # 添加连接监控任务
            )
        finally:
            monitor_connection_task.cancel()  # 取消连接监控任务
            monitor_task.cancel()
            # 关闭所有WebSocket连接
            for ws in websocket_server._active_connections.copy():
                try:
                    await ws.close()
                except:
                    pass
            # 关闭AT客户端连接
            await client.close()
            
            server_v4.close()
            server_v6.close()
            await asyncio.gather(
                server_v4.wait_closed(),
                server_v6.wait_closed()
            )
    except Exception as e:
        print(f"运行错误: {e}")
        raise
    finally:
        if hasattr(client, 'close'):
            await client.close()

def get_base_dir():
    """获取可执行文件所在目录"""
    return os.path.dirname(sys.executable) if getattr(sys, 'frozen', False) else os.path.dirname(__file__)

def force_remove_folder(path):
    """强制删除文件夹（忽略错误）"""
    if os.path.exists(path):
        shutil.rmtree(path, ignore_errors=True)
        print(f"已清理旧文件夹: {path}")

def copy_web_folder():
    # 只在PyInstaller环境下执行复制
    if not getattr(sys, 'frozen', False) or not hasattr(sys, '_MEIPASS'):
        print("非PyInstaller环境，跳过Web文件夹复制")
        return
    
    base_dir = get_base_dir()
    web_dst = os.path.join(base_dir, 'web')
    
    force_remove_folder(web_dst)
    
    web_src = os.path.join(sys._MEIPASS, 'web')
    shutil.copytree(web_src, web_dst)
    print(f"Web文件夹已更新到: {web_dst}")

def cleanup_on_exit():
    """退出时清理文件夹"""
    # 只在PyInstaller环境下执行清理
    if not getattr(sys, 'frozen', False) or not hasattr(sys, '_MEIPASS'):
        return
        
    base_dir = get_base_dir()
    web_dst = os.path.join(base_dir, 'web')
    force_remove_folder(web_dst)

if __name__ == "__main__":
    try:
        if sys.platform == 'win32':
            atexit.register(cleanup_on_exit)
            copy_web_folder()
            asyncio.set_event_loop_policy(asyncio.WindowsSelectorEventLoopPolicy())
        try:
            loop = asyncio.new_event_loop()
            asyncio.set_event_loop(loop)
        except Exception as e:
            loop = asyncio.get_event_loop()
        try:
            loop.run_until_complete(main())
        except KeyboardInterrupt:
            print("\n正在关闭服务...")
        finally:
            pending = asyncio.all_tasks(loop)
            for task in pending:
                task.cancel() 
            loop.run_until_complete(asyncio.gather(*pending, return_exceptions=True))
            loop.close()

    except KeyboardInterrupt:
        print("主动停止监听短信")
    except Exception as e:
        print(f"程序启动错误: {e}")