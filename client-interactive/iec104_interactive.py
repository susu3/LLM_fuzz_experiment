#!/usr/bin/env python3
"""IEC104 交互式十六进制客户端"""
import socket
import sys
import time

def main():
    host = '127.0.0.1'
    port = 2404
    
    try:
        sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        sock.connect((host, port))
        print(f"[+] Connected to {host}:{port}")
        print("[*] Enter hex strings (e.g., 680407000000)")
        print("[*] Commands: 'quit' to exit, 'recv' to check responses")
        print()
        
        sock.settimeout(0.1)  # 非阻塞接收
        
        while True:
            try:
                # 显示提示符
                user_input = input("hex> ").strip()
                
                if not user_input:
                    continue
                
                if user_input.lower() in ['quit', 'exit', 'q']:
                    print("[*] Closing connection...")
                    break
                
                if user_input.lower() == 'recv':
                    # 只接收，不发送
                    print("[*] Checking for responses...")
                else:
                    # 发送十六进制数据
                    try:
                        data = bytes.fromhex(user_input)
                        sock.send(data)
                        print(f"[→] Sent: {data.hex()}")
                    except ValueError:
                        print("[!] Invalid hex string")
                        continue
                
                # 尝试接收响应
                time.sleep(0.05)  # 给服务器一点反应时间
                try:
                    resp = sock.recv(4096)
                    if resp:
                        print(f"[←] Response: {resp.hex()}")
                        # 也显示可读的ASCII（如果有）
                        ascii_repr = ''.join(chr(b) if 32 <= b < 127 else '.' for b in resp)
                        print(f"[←] ASCII: {ascii_repr}")
                except socket.timeout:
                    pass  # 没有响应，正常
                
            except KeyboardInterrupt:
                print("\n[*] Interrupted, closing...")
                break
            except Exception as e:
                print(f"[!] Error: {e}")
                break
        
        sock.close()
        print("[*] Connection closed")
        
    except Exception as e:
        print(f"[!] Connection error: {e}")
        sys.exit(1)

if __name__ == '__main__':
    main()