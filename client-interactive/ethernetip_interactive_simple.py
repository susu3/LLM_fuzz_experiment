#!/usr/bin/env python3
"""
EtherNet/IP (CIP) 简易交互式客户端
用于漏洞验证，仅支持原始十六进制数据收发
"""

import socket
import sys
import threading
import struct
from datetime import datetime

class EtherNetIPClientSimple:
    def __init__(self, host='127.0.0.1', port=44818):
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
    
    def parse_encaps_header(self, data):
        """
        解析 EtherNet/IP 封装头部 (24 字节) 以获取数据长度
        Format: Command(2) + Length(2) + SessionHandle(4) + Status(4) + Context(8) + Options(4)
        """
        if len(data) < 24:
            return None
        
        command, length, session, status, context, options = struct.unpack('<HHIIQI', data[:24])
        return {
            'length': length,
            'command': command,
            'session': session,
            'status': status
        }
    
    def receive_loop(self):
        """独立线程：持续接收服务器数据"""
        self.sock.settimeout(0.1)  # 100ms 超时，避免阻塞
        
        while self.running:
            try:
                # 1. 读取头部 (24字节)
                header_data = b''
                while len(header_data) < 24 and self.running:
                    try:
                        chunk = self.sock.recv(24 - len(header_data))
                        if not chunk:
                            self.log("⚠ ", "Server closed connection")
                            self.running = False
                            return
                        header_data += chunk
                    except socket.timeout:
                        continue
                
                if len(header_data) < 24:
                    continue
                
                # 2. 解析头部获取负载长度
                header = self.parse_encaps_header(header_data)
                if not header:
                    continue
                
                payload_len = header['length']
                
                # 3. 读取负载数据
                payload_data = b''
                while len(payload_data) < payload_len and self.running:
                    try:
                        chunk = self.sock.recv(payload_len - len(payload_data))
                        if not chunk:
                            break
                        payload_data += chunk
                    except socket.timeout:
                        continue
                
                # 4. 组合并显示
                full_packet = header_data + payload_data
                hex_str = full_packet.hex()
                formatted_hex = ' '.join(hex_str[i:i+2] for i in range(0, len(hex_str), 2))
                
                # 简要显示解析信息
                info = f"Cmd=0x{header['command']:04x} Len={header['length']} Session=0x{header['session']:08x} Status=0x{header['status']:08x}"
                self.log("←─", f"Recv ({len(full_packet)} bytes): {formatted_hex}")
                self.log("   ", f"└── {info}")
                
            except socket.timeout:
                continue
            except OSError:
                break
            except Exception as e:
                if self.running:
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
    
    def send_hex(self, hex_string):
        """发送十六进制字符串"""
        try:
            # 清理输入：去除空格、冒号、换行
            hex_clean = hex_string.replace(' ', '').replace(':', '').replace('-', '').replace('\n', '')
            if not hex_clean:
                return False
                
            data = bytes.fromhex(hex_clean)
            self.sock.send(data)
            
            # 格式化显示发送内容
            hex_out = data.hex()
            formatted_out = ' '.join(hex_out[i:i+2] for i in range(0, len(hex_out), 2))
            self.log("─→", f"Send ({len(data)} bytes): {formatted_out}")
            return True
        except ValueError:
            self.log("✗", "Invalid hex string")
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

    def run(self):
        """主循环"""
        print("=" * 60)
        print("EtherNet/IP 简易十六进制发送工具")
        print("=" * 60)
        print("直接输入十六进制字符串发送 (如: 65 00 04 00 ...)")
        print("输入 'q' 或 'quit' 退出")
        print("-" * 60)
        
        if not self.connect():
            return

        try:
            while self.running:
                try:
                    user_input = input().strip()
                    
                    if not user_input:
                        continue
                    
                    if user_input.lower() in ['q', 'quit', 'exit']:
                        break
                    
                    self.send_hex(user_input)
                    
                except KeyboardInterrupt:
                    print()
                    break
                except EOFError:
                    break
        finally:
            self.close()

def main():
    host = '127.0.0.1'
    port = 44818
    
    if len(sys.argv) > 1:
        host = sys.argv[1]
    if len(sys.argv) > 2:
        port = int(sys.argv[2])
    
    client = EtherNetIPClientSimple(host, port)
    client.run()

if __name__ == '__main__':
    main()
