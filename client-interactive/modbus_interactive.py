#!/usr/bin/env python3
"""
Modbus TCP 实时交互式客户端
支持发送原始十六进制数据包和预设命令
"""

import socket
import sys
import threading
import time
from datetime import datetime

class ModbusInteractiveClient:
    def __init__(self, host='127.0.0.1', port=1502):
        self.host = host
        self.port = port
        self.sock = None
        self.running = False
        self.receive_thread = None
        self.transaction_id = 1
        
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
                    self.log("←─", f"Recv: {data.hex()}", self.parse_modbus_response(data))
                else:
                    self.log("!", "Server closed connection")
                    self.running = False
                    break
            except socket.timeout:
                continue
            except Exception as e:
                if self.running:
                    self.log("!", f"Receive error: {e}")
                break
    
    def send_hex(self, hex_string):
        """发送十六进制字符串"""
        try:
            # 移除空格和常见分隔符
            hex_clean = hex_string.replace(' ', '').replace(':', '').replace('-', '')
            data = bytes.fromhex(hex_clean)
            self.sock.sendall(data)
            self.log("─→", f"Send: {data.hex()}", self.parse_modbus_request(data))
            return True
        except ValueError as e:
            self.log("✗", f"Invalid hex format: {e}")
            return False
        except Exception as e:
            self.log("✗", f"Send error: {e}")
            return False
    
    def build_modbus_request(self, function_code, address, value_or_count):
        """构建标准 Modbus TCP 请求"""
        trans_id = self.transaction_id
        self.transaction_id = (self.transaction_id + 1) % 65536
        
        protocol_id = 0x0000  # Modbus TCP
        unit_id = 0x01
        
        if function_code in [0x01, 0x02, 0x03, 0x04]:  # Read functions
            # Function Code + Address (2) + Count (2)
            pdu = bytes([function_code]) + address.to_bytes(2, 'big') + value_or_count.to_bytes(2, 'big')
        elif function_code in [0x05, 0x06]:  # Write single
            # Function Code + Address (2) + Value (2)
            pdu = bytes([function_code]) + address.to_bytes(2, 'big') + value_or_count.to_bytes(2, 'big')
        else:
            raise ValueError(f"Unsupported function code: {function_code}")
        
        length = len(pdu) + 1  # PDU + Unit ID
        
        # MBAP Header + PDU
        mbap = trans_id.to_bytes(2, 'big') + protocol_id.to_bytes(2, 'big') + \
               length.to_bytes(2, 'big') + bytes([unit_id])
        
        return mbap + pdu
    
    def send_read_holding_registers(self, address, count):
        """读取保持寄存器 (FC 0x03)"""
        packet = self.build_modbus_request(0x03, address, count)
        self.sock.sendall(packet)
        self.log("─→", f"Send: {packet.hex()}", 
                f"Read Holding Registers: addr={address}, count={count}")
    
    def send_read_coils(self, address, count):
        """读取线圈 (FC 0x01)"""
        packet = self.build_modbus_request(0x01, address, count)
        self.sock.sendall(packet)
        self.log("─→", f"Send: {packet.hex()}", 
                f"Read Coils: addr={address}, count={count}")
    
    def send_write_register(self, address, value):
        """写入单个寄存器 (FC 0x06)"""
        packet = self.build_modbus_request(0x06, address, value)
        self.sock.sendall(packet)
        self.log("─→", f"Send: {packet.hex()}", 
                f"Write Single Register: addr={address}, value={value}")
    
    def send_write_coil(self, address, value):
        """写入单个线圈 (FC 0x05)"""
        coil_value = 0xFF00 if value else 0x0000
        packet = self.build_modbus_request(0x05, address, coil_value)
        self.sock.sendall(packet)
        self.log("─→", f"Send: {packet.hex()}", 
                f"Write Single Coil: addr={address}, value={'ON' if value else 'OFF'}")
    
    def parse_modbus_request(self, data):
        """解析 Modbus 请求"""
        if len(data) < 8:
            return "Invalid: too short"
        
        trans_id = int.from_bytes(data[0:2], 'big')
        protocol_id = int.from_bytes(data[2:4], 'big')
        length = int.from_bytes(data[4:6], 'big')
        unit_id = data[6]
        function_code = data[7]
        
        fc_names = {
            0x01: "Read Coils",
            0x02: "Read Discrete Inputs",
            0x03: "Read Holding Registers",
            0x04: "Read Input Registers",
            0x05: "Write Single Coil",
            0x06: "Write Single Register",
            0x0F: "Write Multiple Coils",
            0x10: "Write Multiple Registers"
        }
        
        fc_name = fc_names.get(function_code, f"Unknown FC {function_code:#04x}")
        return f"[TID={trans_id}] {fc_name}, Unit={unit_id}"
    
    def parse_modbus_response(self, data):
        """解析 Modbus 响应"""
        if len(data) < 8:
            return "Invalid: too short"
        
        trans_id = int.from_bytes(data[0:2], 'big')
        protocol_id = int.from_bytes(data[2:4], 'big')
        length = int.from_bytes(data[4:6], 'big')
        unit_id = data[6]
        function_code = data[7]
        
        if function_code & 0x80:  # Exception response
            exception_code = data[8] if len(data) > 8 else 0
            exception_names = {
                0x01: "Illegal Function",
                0x02: "Illegal Data Address",
                0x03: "Illegal Data Value",
                0x04: "Server Device Failure"
            }
            exc_name = exception_names.get(exception_code, f"Unknown {exception_code}")
            return f"[TID={trans_id}] EXCEPTION: {exc_name}"
        
        if function_code == 0x03 and len(data) > 9:  # Read Holding Registers
            byte_count = data[8]
            registers = []
            for i in range(0, byte_count, 2):
                if 9 + i + 1 < len(data):
                    reg_value = int.from_bytes(data[9+i:9+i+2], 'big')
                    registers.append(f"{reg_value:#06x}")
            return f"[TID={trans_id}] Read Holding Registers: {', '.join(registers)}"
        
        if function_code == 0x01 and len(data) > 9:  # Read Coils
            byte_count = data[8]
            return f"[TID={trans_id}] Read Coils: {byte_count} bytes"
        
        return f"[TID={trans_id}] Function Code {function_code:#04x}"
    
    def log(self, prefix, message, details=""):
        """打印带时间戳的日志"""
        timestamp = datetime.now().strftime("%H:%M:%S.%f")[:-3]
        if details:
            print(f"[{timestamp}] {prefix} {message}\n           └─ {details}")
        else:
            print(f"[{timestamp}] {prefix} {message}")
    
    def show_help(self):
        """显示帮助信息"""
        print("\n" + "="*80)
        print("                    Modbus TCP 实时交互式客户端")
        print("="*80)
        print("\n📝 命令说明:")
        print("  • 直接输入十六进制字符串（无空格）:")
        print("    000100000006010300000001")
        print("  • 带空格的十六进制:")
        print("    00 01 00 00 00 06 01 03 00 00 00 01")
        print("\n  • 预设命令:")
        print("    - read <addr> <count>      : 读取保持寄存器 (FC 0x03)")
        print("    - readc <addr> <count>     : 读取线圈 (FC 0x01)")
        print("    - write <addr> <value>     : 写入单个寄存器 (FC 0x06)")
        print("    - writec <addr> <on|off>   : 写入单个线圈 (FC 0x05)")
        print("\n  • 控制命令:")
        print("    - help / h / ?             : 显示帮助")
        print("    - quit / exit / q          : 退出")
        print("\n  • 示例:")
        print("    read 0 10                  : 读取地址0开始的10个寄存器")
        print("    write 5 1234               : 写入地址5的值为1234")
        print("    readc 0 8                  : 读取地址0开始的8个线圈")
        print("    writec 3 on                : 写入地址3的线圈为ON")
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
                    
                    # 预设命令
                    parts = cmd.split()
                    
                    if parts[0].lower() == 'read' and len(parts) == 3:
                        address = int(parts[1], 0)
                        count = int(parts[2], 0)
                        self.send_read_holding_registers(address, count)
                        continue
                    
                    if parts[0].lower() == 'readc' and len(parts) == 3:
                        address = int(parts[1], 0)
                        count = int(parts[2], 0)
                        self.send_read_coils(address, count)
                        continue
                    
                    if parts[0].lower() == 'write' and len(parts) == 3:
                        address = int(parts[1], 0)
                        value = int(parts[2], 0)
                        self.send_write_register(address, value)
                        continue
                    
                    if parts[0].lower() == 'writec' and len(parts) == 3:
                        address = int(parts[1], 0)
                        value = parts[2].lower() in ['on', '1', 'true', 'yes']
                        self.send_write_coil(address, value)
                        continue
                    
                    # 否则作为十六进制发送
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

