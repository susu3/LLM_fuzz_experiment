#!/usr/bin/env python3
"""
Modbus TCP 实时交互式客户端（简化版）
只支持发送原始十六进制数据包
"""

import socket
import sys
import threading
from datetime import datetime

class ModbusInteractiveClient:
    def __init__(self, host='127.0.0.1', port=1502):
        self.host = host
        self.port = port
        self.sock = None
        self.running = False
        self.receive_thread = None
        
    def connect(self):
        """连接到 Modbus 服务器"""
        try:
            self.sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
            self.sock.settimeout(1.0)
            self.sock.connect((self.host, self.port))
            self.running = True
            
            # 启动接收线程
            self.receive_thread = threading.Thread(target=self.receive_loop, daemon=True)
            self.receive_thread.start()
            
            self.log("✓", f"Connected to {self.host}:{self.port}")
            return True
        except Exception as e:
            self.log("✗", f"Connection failed: {e}")
            return False
    
    def disconnect(self):
        """断开连接"""
        self.running = False
        if self.sock:
            try:
                self.sock.close()
            except:
                pass
        self.log("✓", "Disconnected")
    
    def receive_loop(self):
        """接收数据的独立线程"""
        while self.running:
            try:
                data = self.sock.recv(4096)
                if data:
                    # 格式化显示（每2字节加空格）
                    formatted_hex = ' '.join(data.hex()[i:i+2] for i in range(0, len(data.hex()), 2))
                    self.log("←─", f"Recv ({len(data)} bytes): {formatted_hex}")
                else:
                    self.log("⚠ ", "Server closed connection")
                    self.running = False
                    break
            except socket.timeout:
                continue
            except Exception as e:
                if self.running:
                    self.log("⚠ ", f"Receive error: {e}")
                break
    
    def send_hex(self, hex_string):
        """发送十六进制字符串"""
        try:
            # 移除空格和常见分隔符（支持多种格式）
            hex_clean = hex_string.replace(' ', '').replace(':', '').replace('-', '')
            data = bytes.fromhex(hex_clean)
            self.sock.sendall(data)
            
            # 格式化显示（每2字节加空格）
            formatted_hex = ' '.join(data.hex()[i:i+2] for i in range(0, len(data.hex()), 2))
            self.log("─→", f"Send ({len(data)} bytes): {formatted_hex}")
            
            return True
        except ValueError as e:
            self.log("✗", f"Invalid hex format: {e}")
            return False
        except Exception as e:
            self.log("✗", f"Send error: {e}")
            return False
    
    def log(self, prefix, message):
        """打印带时间戳的日志"""
        timestamp = datetime.now().strftime("%H:%M:%S.%f")[:-3]
        print(f"[{timestamp}] {prefix} {message}")
    
    def show_help(self):
        """显示帮助信息"""
        print("\n" + "="*80)
        print("              Modbus TCP 原始字节交互客户端")
        print("="*80)
        print("\n📝 使用说明:")
        print("  • 输入十六进制字符串（无空格）:")
        print("    000100000006010300000001")
        print()
        print("  • 输入带空格/分隔符的十六进制:")
        print("    00 01 00 00 00 06 01 03 00 00 00 01")
        print("    00:01:00:00:00:06:01:03:00:00:00:01")
        print("    00-01-00-00-00-06-01-03-00-00-00-01")
        print()
        print("  • 控制命令:")
        print("    - help / h / ?    : 显示帮助")
        print("    - quit / exit / q : 退出")
        print("-"*80 + "\n")
    
    def run(self):
        """主循环"""
        if not self.connect():
            return
        
        self.show_help()
        
        try:
            while self.running:
                try:
                    cmd = input("> ").strip()
                    
                    if not cmd:
                        continue
                    
                    # 退出命令
                    if cmd.lower() in ['quit', 'exit', 'q']:
                        break
                    
                    # 帮助命令
                    if cmd.lower() in ['help', 'h', '?']:
                        self.show_help()
                        continue
                    
                    # 作为十六进制发送
                    self.send_hex(cmd)
                    
                except KeyboardInterrupt:
                    print("\n")
                    break
                except EOFError:
                    break
                except Exception as e:
                    self.log("✗", f"Error: {e}")
        
        finally:
            self.disconnect()

def main():
    # 解析命令行参数
    host = '127.0.0.1'
    port = 1502
    
    if len(sys.argv) > 1:
        host = sys.argv[1]
    if len(sys.argv) > 2:
        port = int(sys.argv[2])
    
    client = ModbusInteractiveClient(host, port)
    client.run()

if __name__ == '__main__':
    main()

