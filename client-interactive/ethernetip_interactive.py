#!/usr/bin/env python3
"""
EtherNet/IP (CIP) 实时交互式客户端
支持与 OpENer 和 EIPScanner 服务端进行通信
"""

import socket
import sys
import threading
import time
import struct
from datetime import datetime

class EtherNetIPClient:
    # EtherNet/IP Encapsulation Commands
    CMD_NOP = 0x0000
    CMD_LIST_SERVICES = 0x0004
    CMD_LIST_IDENTITY = 0x0063
    CMD_LIST_INTERFACES = 0x0064
    CMD_REGISTER_SESSION = 0x0065
    CMD_UNREGISTER_SESSION = 0x0066
    CMD_SEND_RR_DATA = 0x006F
    CMD_SEND_UNIT_DATA = 0x0070
    CMD_INDICATE_STATUS = 0x0072
    CMD_CANCEL = 0x0073
    
    # EtherNet/IP Status Codes
    STATUS_SUCCESS = 0x0000
    STATUS_UNSUPPORTED_COMMAND = 0x0001
    STATUS_INSUFFICIENT_MEMORY = 0x0002
    STATUS_INVALID_FORMAT = 0x0003
    STATUS_INVALID_SESSION = 0x0064
    STATUS_UNSUPPORTED_PROTOCOL = 0x0069
    
    # CIP Service Codes
    SERVICE_GET_ATTRIBUTE_ALL = 0x01
    SERVICE_GET_ATTRIBUTE_SINGLE = 0x0E
    SERVICE_SET_ATTRIBUTE_SINGLE = 0x10
    SERVICE_RESET = 0x05
    SERVICE_START = 0x06
    SERVICE_STOP = 0x07
    
    CMD_NAMES = {
        0x0000: "NOP",
        0x0004: "ListServices",
        0x0063: "ListIdentity",
        0x0064: "ListInterfaces",
        0x0065: "RegisterSession",
        0x0066: "UnregisterSession",
        0x006F: "SendRRData",
        0x0070: "SendUnitData",
        0x0072: "IndicateStatus",
        0x0073: "Cancel"
    }
    
    STATUS_NAMES = {
        0x0000: "SUCCESS",
        0x0001: "UnsupportedCommand",
        0x0002: "InsufficientMemory",
        0x0003: "InvalidFormat",
        0x0064: "InvalidSession",
        0x0069: "UnsupportedProtocol"
    }
    
    def __init__(self, host='127.0.0.1', port=44818):
        self.host = host
        self.port = port
        self.sock = None
        self.running = False
        self.recv_thread = None
        self.session_handle = 0x00000000  # Will be set after registration
        self.context = b'\x00' * 8  # 8-byte context
        
    def timestamp(self):
        """获取当前时间戳"""
        return datetime.now().strftime('%H:%M:%S.%f')[:-3]
    
    def log(self, prefix, message, flush=True):
        """带时间戳的日志输出"""
        print(f"[{self.timestamp()}] {prefix} {message}", flush=flush)
    
    def build_encaps_header(self, command, length, session_handle=None, status=0x00000000):
        """
        构建 EtherNet/IP 封装头部 (24 字节)
        Format: Command(2) + Length(2) + SessionHandle(4) + Status(4) + Context(8) + Options(4)
        """
        if session_handle is None:
            session_handle = self.session_handle
            
        header = struct.pack(
            '<HHIIQI',  # Little-endian: ushort, ushort, uint, uint, ulonglong, uint
            command,
            length,
            session_handle,
            status,
            int.from_bytes(self.context, 'little'),  # Context as 64-bit int
            0x00000000  # Options
        )
        return header
    
    def parse_encaps_header(self, data):
        """解析 EtherNet/IP 封装头部"""
        if len(data) < 24:
            return None
        
        command, length, session_handle, status, context_int, options = struct.unpack('<HHIIQI', data[:24])
        
        return {
            'command': command,
            'command_name': self.CMD_NAMES.get(command, f"Unknown(0x{command:04x})"),
            'length': length,
            'session_handle': session_handle,
            'status': status,
            'status_name': self.STATUS_NAMES.get(status, f"Unknown(0x{status:08x})"),
            'context': context_int.to_bytes(8, 'little'),
            'options': options
        }
    
    def build_register_session(self):
        """构建 RegisterSession 数据包"""
        # RegisterSession data: ProtocolVersion(2) + OptionFlags(2)
        data = struct.pack('<HH', 1, 0)  # Version=1, Flags=0
        header = self.build_encaps_header(self.CMD_REGISTER_SESSION, len(data), session_handle=0)
        return header + data
    
    def build_unregister_session(self):
        """构建 UnregisterSession 数据包"""
        header = self.build_encaps_header(self.CMD_UNREGISTER_SESSION, 0)
        return header
    
    def build_list_identity(self):
        """构建 ListIdentity 数据包（用于设备发现）"""
        header = self.build_encaps_header(self.CMD_LIST_IDENTITY, 0, session_handle=0)
        return header
    
    def build_send_rr_data(self, cip_data):
        """
        构建 SendRRData 数据包
        Format: InterfaceHandle(4) + Timeout(2) + ItemCount(2) + Items...
        """
        interface_handle = 0x00000000
        timeout = 0x0005  # 5 seconds
        item_count = 0x0002  # Typically 2 items: NULL address + Unconnected message
        
        # Item 1: NULL Address Item (TypeID=0x0000, Length=0)
        item1 = struct.pack('<HH', 0x0000, 0x0000)
        
        # Item 2: Unconnected Data Item (TypeID=0x00B2, Length=len(cip_data))
        item2 = struct.pack('<HH', 0x00B2, len(cip_data)) + cip_data
        
        data = struct.pack('<IHH', interface_handle, timeout, item_count) + item1 + item2
        header = self.build_encaps_header(self.CMD_SEND_RR_DATA, len(data))
        return header + data
    
    def build_get_attribute_single(self, class_id, instance_id, attribute_id):
        """
        构建 CIP GetAttributeSingle 请求
        Service: 0x0E, EPATH: Class/Instance/Attribute
        """
        service = self.SERVICE_GET_ATTRIBUTE_SINGLE
        
        # EPATH: Logical Segment for Class/Instance/Attribute
        # Format: [Segment Type/Size][Class][Segment Type/Size][Instance][Segment Type/Size][Attribute]
        epath = bytes([
            0x20, class_id,           # Logical Class (8-bit)
            0x24, instance_id,        # Logical Instance (8-bit)
            0x30, attribute_id        # Logical Attribute (8-bit)
        ])
        epath_size = len(epath) // 2  # EPATH size in words
        
        cip_data = bytes([service, epath_size]) + epath
        return self.build_send_rr_data(cip_data)
    
    def receive_loop(self):
        """独立线程：持续接收服务器数据"""
        self.sock.settimeout(0.1)  # 100ms 超时，避免阻塞
        
        while self.running:
            try:
                # First, read the header to know the data length
                header_data = b''
                while len(header_data) < 24 and self.running:
                    chunk = self.sock.recv(24 - len(header_data))
                    if not chunk:
                        self.log("⚠ ", "Server closed connection")
                        self.running = False
                        return
                    header_data += chunk
                
                if len(header_data) < 24:
                    continue
                
                # Parse header to get data length
                header = self.parse_encaps_header(header_data)
                if not header:
                    continue
                
                # Read the data payload
                data_payload = b''
                data_length = header['length']
                while len(data_payload) < data_length and self.running:
                    chunk = self.sock.recv(data_length - len(data_payload))
                    if not chunk:
                        self.log("⚠ ", "Connection lost during data read")
                        self.running = False
                        return
                    data_payload += chunk
                
                # Complete packet
                full_packet = header_data + data_payload
                hex_str = full_packet.hex()
                formatted_hex = ' '.join(hex_str[i:i+2] for i in range(0, len(hex_str), 2))
                
                self.log("←─", f"Recv ({len(full_packet)} bytes): {formatted_hex}")
                self.parse_packet(header, data_payload)
                
                # Update session handle if this is RegisterSession response
                if header['command'] == self.CMD_REGISTER_SESSION and header['status'] == self.STATUS_SUCCESS:
                    self.session_handle = header['session_handle']
                    self.log("   ", f"✓ Session registered: 0x{self.session_handle:08x}")
                
            except socket.timeout:
                continue
            except OSError:
                break
            except Exception as e:
                if self.running:
                    self.log("⚠ ", f"Receive error: {e}")
                break
    
    def parse_packet(self, header, data):
        """解析 EtherNet/IP 数据包"""
        try:
            cmd_name = header['command_name']
            status_name = header['status_name']
            
            self.log("   ", f"EIP: {cmd_name}, Status={status_name}, " +
                           f"Session=0x{header['session_handle']:08x}, Length={header['length']}")
            
            # Parse specific command data
            if header['command'] == self.CMD_REGISTER_SESSION and len(data) >= 4:
                proto_ver, flags = struct.unpack('<HH', data[:4])
                self.log("   ", f"RegisterSession: ProtocolVersion={proto_ver}, Flags=0x{flags:04x}")
            
            elif header['command'] == self.CMD_LIST_IDENTITY and len(data) > 0:
                self.log("   ", f"ListIdentity: {len(data)} bytes of device info")
                # Could parse device identity here
            
            elif header['command'] == self.CMD_SEND_RR_DATA and len(data) >= 6:
                interface_handle, timeout, item_count = struct.unpack('<IHH', data[:8])
                self.log("   ", f"SendRRData: Timeout={timeout}ms, Items={item_count}")
                
                # Parse CPF items
                offset = 8
                for i in range(item_count):
                    if offset + 4 <= len(data):
                        item_type, item_length = struct.unpack('<HH', data[offset:offset+4])
                        offset += 4
                        item_data = data[offset:offset+item_length]
                        offset += item_length
                        
                        if item_type == 0x00B2 and len(item_data) >= 2:  # Unconnected Message
                            service_reply = item_data[0]
                            general_status = item_data[2] if len(item_data) > 2 else 0
                            
                            if service_reply & 0x80:
                                service_code = service_reply & 0x7F
                                status_str = "SUCCESS" if general_status == 0 else f"ERROR(0x{general_status:02x})"
                                self.log("   ", f"  CIP Reply: Service=0x{service_code:02x}, Status={status_str}")
                                
                                # Parse data if success
                                if general_status == 0 and len(item_data) > 4:
                                    reply_data = item_data[4:]
                                    self.log("   ", f"  CIP Data: {reply_data.hex()}")
        except Exception as e:
            self.log("   ", f"Parse error: {e}")
    
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
            
            # Auto register session
            time.sleep(0.1)
            self.log("ℹ ", "Auto-registering session...")
            self.send_raw(self.build_register_session())
            time.sleep(0.2)  # Wait for session registration
            
            return True
            
        except Exception as e:
            self.log("✗", f"Connection failed: {e}")
            return False
    
    def send_raw(self, data):
        """发送原始字节数据"""
        try:
            self.sock.send(data)
            hex_str = data.hex()
            formatted_hex = ' '.join(hex_str[i:i+2] for i in range(0, len(hex_str), 2))
            self.log("─→", f"Send ({len(data)} bytes): {formatted_hex}")
            return True
        except Exception as e:
            self.log("✗", f"Send error: {e}")
            return False
    
    def send_hex(self, hex_string):
        """发送十六进制字符串"""
        try:
            hex_clean = hex_string.replace(' ', '').replace(':', '').replace('-', '')
            data = bytes.fromhex(hex_clean)
            return self.send_raw(data)
        except ValueError:
            self.log("✗", "Invalid hex string")
            return False
    
    def close(self):
        """关闭连接"""
        # Send UnregisterSession if we have a session
        if self.session_handle != 0:
            self.log("ℹ ", "Unregistering session...")
            try:
                self.send_raw(self.build_unregister_session())
                time.sleep(0.1)
            except:
                pass
        
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
        print(" " * 20 + "EtherNet/IP 实时交互式客户端")
        print("=" * 80)
        print()
        print("📝 命令说明:")
        print("  • 直接输入十六进制字符串:")
        print("    6500040000000000000000000000000000000000000001000000")
        print("  • 带空格的十六进制:")
        print("    65 00 04 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 01 00 00 00")
        print()
        print("  • 预设命令:")
        print("    - register        : 注册会话 (Register Session)")
        print("    - unregister      : 注销会话 (Unregister Session)")
        print("    - listid          : 列出设备身份 (List Identity)")
        print("    - getvendor       : 读取厂商ID (Get Attribute: Class 0x01)")
        print("    - getdevicetype   : 读取设备类型")
        print("    - getproductname  : 读取产品名称")
        print()
        print("  • 控制命令:")
        print("    - quit / exit / q : 退出")
        print()
        print("-" * 80)
        print()
        
        if not self.connect():
            return
        
        # 预设命令
        presets = {
            'register': lambda: self.build_register_session(),
            'unregister': lambda: self.build_unregister_session(),
            'listid': lambda: self.build_list_identity(),
            'getvendor': lambda: self.build_get_attribute_single(0x01, 1, 1),  # Identity Object, Instance 1, Vendor ID
            'getdevicetype': lambda: self.build_get_attribute_single(0x01, 1, 2),  # Device Type
            'getproductname': lambda: self.build_get_attribute_single(0x01, 1, 7),  # Product Name
        }
        
        try:
            while self.running:
                try:
                    user_input = input("enip> ").strip()
                    
                    if not user_input:
                        continue
                    
                    # 检查退出命令
                    if user_input.lower() in ['quit', 'exit', 'q']:
                        break
                    
                    # 检查预设命令
                    if user_input.lower() in presets:
                        data = presets[user_input.lower()]()
                        self.send_raw(data)
                        continue
                    
                    # 否则作为十六进制发送
                    self.send_hex(user_input)
                    
                except KeyboardInterrupt:
                    print()
                    self.log("ℹ ", "Interrupted (Ctrl+C), use 'quit' to exit")
                    continue
                    
        except EOFError:
            print()
        finally:
            self.close()

def main():
    # 解析命令行参数
    host = '127.0.0.1'
    port = 44818
    
    if len(sys.argv) > 1:
        host = sys.argv[1]
    if len(sys.argv) > 2:
        port = int(sys.argv[2])
    
    client = EtherNetIPClient(host, port)
    client.interactive()

if __name__ == '__main__':
    main()

