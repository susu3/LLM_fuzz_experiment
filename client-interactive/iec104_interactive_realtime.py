#!/usr/bin/env python3
"""IEC104 实时交互式客户端 - 无缓冲区堆积"""
import socket
import sys
import threading
import time
from datetime import datetime

class IEC104Client:
    def __init__(self, host='127.0.0.1', port=2404):
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
            
            return True
            
        except Exception as e:
            self.log("✗", f"Connection failed: {e}")
            return False
    
    def send(self, hex_string):
        """发送十六进制数据"""
        try:
            data = bytes.fromhex(hex_string)
            self.sock.send(data)
            
            # 格式化显示
            formatted_hex = ' '.join(hex_string[i:i+2] for i in range(0, len(hex_string), 2))
            self.log("─→", f"Send ({len(data)} bytes): {formatted_hex}")
            
            return True
            
        except ValueError:
            self.log("✗", "Invalid hex string (use only 0-9, a-f, A-F)")
            return False
        except Exception as e:
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
        print("=" * 70)
        print("IEC104 实时交互式客户端")
        print("=" * 70)
        print()
        print("命令说明:")
        print("  • 直接输入十六进制字符串（无空格）: 680407000000")
        print("  • 带空格的十六进制: 68 04 07 00 00 00")
        print("  • 预设命令:")
        print("    - startdt    : 发送 STARTDT 激活帧 (68 04 07 00 00 00)")
        print("    - testfr     : 发送 TESTFR 测试帧 (68 04 43 00 00 00)")
        print("    - stopdt     : 发送 STOPDT 停止帧 (68 04 13 00 00 00)")
        print("  • quit / exit / q : 退出")
        print()
        print("-" * 70)
        print()
        
        if not self.connect():
            return
        
        # 预设命令
        presets = {
            'startdt': '680407000000',
            'testfr':  '680443000000',
            'stopdt':  '680413000000',
        }
        
        try:
            while self.running:
                try:
                    # 使用 input() 获取用户输入
                    user_input = input("hex> ").strip()
                    
                    if not user_input:
                        continue
                    
                    # 检查退出命令
                    if user_input.lower() in ['quit', 'exit', 'q']:
                        break
                    
                    # 检查预设命令
                    if user_input.lower() in presets:
                        hex_str = presets[user_input.lower()]
                        self.log("ℹ ", f"Using preset: {user_input} = {hex_str}")
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
    port = 2404
    
    if len(sys.argv) > 1:
        host = sys.argv[1]
    if len(sys.argv) > 2:
        port = int(sys.argv[2])
    
    client = IEC104Client(host, port)
    client.interactive()

if __name__ == '__main__':
    main()

