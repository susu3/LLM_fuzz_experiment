#!/usr/bin/env python3
"""SLMP (Seamless Message Protocol) 实时交互式客户端"""
import socket
import sys
import threading
import time
from datetime import datetime

class SLMPClient:
    def __init__(self, host='127.0.0.1', port=8888):
        self.host = host
        self.port = port
        self.sock = None
        self.running = False
        self.recv_thread = None
        
    def timestamp(self):
        """获取当前时间戳"""
        return datetime.now().strftime('%H:%M:%S.%f')[:-3]
    
    def log(self, prefix, message, flush=True):
        """带时间戳的日志输出"""
        print(f"[{self.timestamp()}] {prefix} {message}", flush=flush)
    
    def receive_loop(self):
        """独立线程：持续接收服务器数据"""
        self.sock.settimeout(0.1)  # 100ms 超时，避免阻塞
        
        while self.running:
            try:
                data = self.sock.recv(4096)
                if data:
                    hex_str = data.hex()
                    # 格式化十六进制显示（每2字节加空格）
                    formatted_hex = ' '.join(hex_str[i:i+2] for i in range(0, len(hex_str), 2))
                    
                    # ASCII 表示
                    ascii_repr = ''.join(chr(b) if 32 <= b < 127 else '.' for b in data)
                    
                    self.log("←─", f"Recv ({len(data)} bytes): {formatted_hex}")
                    if ascii_repr.strip('.'):
                        self.log("   ", f"ASCII: {ascii_repr}")
                    
                    # 尝试简单解析 SLMP 帧
                    self.parse_slmp_frame(data)
                else:
                    # 连接关闭
                    self.log("⚠ ", "Server closed connection")
                    self.running = False
                    break
                    
            except socket.timeout:
                # 正常超时，继续循环
                continue
            except OSError:
                # Socket 已关闭
                break
            except Exception as e:
                self.log("⚠ ", f"Receive error: {e}")
                break
    
    def parse_slmp_frame(self, data):
        """简单解析 SLMP 帧结构"""
        try:
            if len(data) < 2:
                return
            
            # SLMP Binary 帧：子头部 + 网络号 + PC号 + 请求目标单元I/O号 + 请求目标单元站号 + ...
            subheader = (data[1] << 8) | data[0]
            
            if len(data) >= 11:
                # 尝试解析为 Binary 格式
                network_no = data[2]
                pc_no = data[3]
                req_dest_io = (data[5] << 8) | data[4]
                req_dest_station = data[6]
                data_length = (data[8] << 8) | data[7]
                end_code = (data[10] << 8) | data[9] if len(data) >= 11 else None
                
                self.log("   ", f"SLMP: SubHdr=0x{subheader:04x}, Net={network_no}, PC={pc_no}, "
                              f"DestIO=0x{req_dest_io:04x}, Station={req_dest_station}, "
                              f"DataLen={data_length}, EndCode=0x{end_code:04x}" if end_code is not None else "")
                
                # 解析结束码
                if end_code is not None:
                    if end_code == 0x0000:
                        self.log("   ", "✓ Success (EndCode=0x0000)")
                    else:
                        self.log("   ", f"⚠ Error EndCode=0x{end_code:04x}")
        except Exception:
            pass
    
    def connect(self):
        """连接到服务器"""
        try:
            self.sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
            self.sock.connect((self.host, self.port))
            self.running = True
            
            self.log("✓", f"Connected to {self.host}:{self.port}")
            
            # 启动接收线程
            self.recv_thread = threading.Thread(target=self.receive_loop, daemon=True)
            self.recv_thread.start()
            
            # 自动发送一个心跳包，避免服务器接收超时（2秒超时）
            time.sleep(0.1)  # 等待接收线程启动
            self.log("ℹ ", "Sending initial heartbeat to keep connection alive...")
            self.send("50000000ff00000900100019060000010000", silent=False)
            
            return True
            
        except Exception as e:
            self.log("✗", f"Connection failed: {e}")
            return False
    
    def send(self, hex_string, silent=False):
        """发送十六进制数据"""
        try:
            # 移除空格和常见分隔符
            hex_clean = hex_string.replace(' ', '').replace(':', '').replace('-', '')
            data = bytes.fromhex(hex_clean)
            self.sock.send(data)
            
            # 格式化显示（除非是静默模式）
            if not silent:
                formatted_hex = ' '.join(hex_clean[i:i+2] for i in range(0, len(hex_clean), 2))
                self.log("─→", f"Send ({len(data)} bytes): {formatted_hex}")
            
            return True
            
        except ValueError:
            if not silent:
                self.log("✗", "Invalid hex string (use only 0-9, a-f, A-F)")
            return False
        except Exception as e:
            if not silent:
                self.log("✗", f"Send error: {e}")
            return False
    
    def close(self):
        """关闭连接"""
        self.running = False
        if self.sock:
            try:
                self.sock.close()
            except:
                pass
        if self.recv_thread:
            self.recv_thread.join(timeout=1)
        self.log("✓", "Connection closed")
    
    def interactive(self):
        """交互式主循环"""
        print("=" * 80)
        print(" " * 25 + "SLMP 实时交互式客户端")
        print("=" * 80)
        print()
        print("📝 命令说明:")
        print("  • 直接输入十六进制字符串（无空格）:")
        print("    50000000ff00090010001906000001000000")
        print("  • 带空格的十六进制:")
        print("    50 00 00 00 00 ff 00 09 00 10 00 19 06 00 00 01 00 00 00")
        print()
        print("  • 预设命令:")
        print("    - read     : 读取设备内存 (Device Read)")
        print("    - write    : 写入设备内存 (Device Write)")
        print("    - test     : 自环测试 (Loopback Test)")
        print()
        print("  • 控制命令:")
        print("    - quit / exit / q : 退出")
        print()
        print("-" * 80)
        print()
        
        if not self.connect():
            return
        
        # 预设命令（示例 SLMP 帧）
        presets = {
            # Device Read (Binary) - 读取 D0，1个字
            'read': '500000000000ff03000c001000010401000000a8000100',
            
            # Device Write (Binary) - 写入 D0 = 0x1234
            'write': '500000000000ff03000e001400010401000000a80001003412',
            
            # Loopback Test (Self-test)
            'test': '50000000ff0009001000190600000100',
            
            # 用户提供的测试命令
            'usertest': '50000000ff0009001000190600000100',
        }
        
        try:
            while self.running:
                try:
                    # 使用 input() 获取用户输入
                    user_input = input("slmp> ").strip()
                    
                    if not user_input:
                        continue
                    
                    # 检查退出命令
                    if user_input.lower() in ['quit', 'exit', 'q']:
                        break
                    
                    # 检查预设命令
                    if user_input.lower() in presets:
                        hex_str = presets[user_input.lower()]
                        self.log("ℹ ", f"Using preset: {user_input}")
                        self.send(hex_str)
                        continue
                    
                    # 移除空格和常见分隔符
                    hex_str = user_input.replace(' ', '').replace(':', '').replace('-', '')
                    
                    # 发送数据
                    self.send(hex_str)
                    
                except KeyboardInterrupt:
                    print()  # 换行
                    self.log("ℹ ", "Interrupted (Ctrl+C), use 'quit' to exit")
                    continue
                    
        except EOFError:
            print()  # 换行
        finally:
            self.close()

def main():
    # 禁用 stdout 缓冲
    sys.stdout = sys.__stdout__
    sys.stderr = sys.__stderr__
    
    # 解析命令行参数
    host = '127.0.0.1'
    port = 8888
    
    if len(sys.argv) > 1:
        host = sys.argv[1]
    if len(sys.argv) > 2:
        port = int(sys.argv[2])
    
    client = SLMPClient(host, port)
    client.interactive()

if __name__ == '__main__':
    main()

