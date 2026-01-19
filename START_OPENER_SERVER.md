# 启动 OpENer 服务器用于交互测试

## 问题说明

`eip_server_harness` 是 **AFL 模糊测试专用服务器**，设计为：
- ✗ 单请求模式（收到一个包后立即断开）
- ✗ 不分配真实的 Session Handle
- ✗ 不维持持久连接

**不适合交互式测试！**

## 解决方案：使用 OpENer

OpENer 是完整的 EtherNet/IP 协议栈实现，支持：
- ✓ 持久连接
- ✓ 完整的会话管理
- ✓ 多个请求-响应循环
- ✓ 符合 ODVA 标准

## 启动 OpENer 服务器

### 方法 1：直接运行（推荐）

```bash
# 在终端 5 中运行
cd /home/ecs-user/LLM_fuzz_experiment/OpENer/build-server/src/ports/POSIX
./OpENer lo
```

**说明：**
- `lo` - 网络接口名称（loopback）
- 服务器会监听在 `0.0.0.0:44818`
- 支持持久TCP连接

### 方法 2：后台运行

```bash
cd /home/ecs-user/LLM_fuzz_experiment/OpENer/build-server/src/ports/POSIX
nohup ./OpENer lo > opener.log 2>&1 &
echo $! > opener.pid
echo "OpENer started with PID $(cat opener.pid)"
```

停止服务器：
```bash
kill $(cat /home/ecs-user/LLM_fuzz_experiment/OpENer/build-server/src/ports/POSIX/opener.pid)
```

## 使用交互客户端连接

```bash
# 在终端 4 中运行
cd /home/ecs-user/LLM_fuzz_experiment/client-interactive
./ethernetip_interactive.py 127.0.0.1 44818
```

### 期望输出

```
[HH:MM:SS.mmm] ✓ Connected to 127.0.0.1:44818
[HH:MM:SS.mmm] ℹ  Auto-registering session...
[HH:MM:SS.mmm] ─→ Send (28 bytes): 65 00 04 00 00 00 00 00 ...
[HH:MM:SS.mmm] ←─ Recv (28 bytes): 65 00 04 00 78 56 34 12 ...
[HH:MM:SS.mmm]     EIP: RegisterSession, Status=SUCCESS, Session=0x12345678
[HH:MM:SS.mmm]     ✓ Session registered: 0x12345678

enip> getvendor
[HH:MM:SS.mmm] ─→ Send (48 bytes): ...
[HH:MM:SS.mmm] ←─ Recv (XX bytes): ...
[HH:MM:SS.mmm]     CIP Reply: Service=0x0E, Status=SUCCESS
```

**关键区别：**
- ✓ Session Handle 为非零值（如 `0x12345678`）
- ✓ RegisterSession 响应包含4字节数据
- ✓ 连接保持活跃，可以发送多个命令

## 验证服务器运行

```bash
# 检查端口监听
netstat -tlnp | grep 44818

# 或使用 ss
ss -tlnp | grep 44818
```

应该看到：
```
tcp  0  0  0.0.0.0:44818  0.0.0.0:*  LISTEN  PID/OpENer
```

## 两种服务器对比

| 特性 | eip_server_harness | OpENer |
|------|-------------------|--------|
| 用途 | AFL 模糊测试 | 生产级服务器 |
| 连接模式 | 单请求后断开 | 持久连接 |
| Session管理 | 无（回显0） | 完整实现 |
| 协议完整性 | 部分（仅解析） | 完整 |
| 适合交互 | ✗ | ✓ |
| 适合模糊测试 | ✓ | ✓ |

## 故障排查

### 端口被占用
```bash
# 查找占用进程
sudo lsof -i :44818

# 或
sudo fuser -k 44818/tcp  # 强制终止
```

### OpENer 启动失败
```bash
# 检查可执行文件
ls -la /home/ecs-user/LLM_fuzz_experiment/OpENer/build-server/src/ports/POSIX/OpENer

# 查看错误信息
cd /home/ecs-user/LLM_fuzz_experiment/OpENer/build-server/src/ports/POSIX
./OpENer lo 2>&1 | tee opener_debug.log
```

### 无法连接
```bash
# 确认服务器监听
netstat -tlnp | grep 44818

# 测试连接
nc -zv 127.0.0.1 44818

# 或使用 telnet
telnet 127.0.0.1 44818
```
