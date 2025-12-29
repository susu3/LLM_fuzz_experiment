# libslmp 覆盖率分析脚本说明

## 概述
本脚本参考 modbus、iec104、ethernetip 的覆盖率分析脚本设计，完成了 libslmp 协议的覆盖率分析功能。

## 创建的脚本

### 1. coverage-libslmp.sh (621行)
主覆盖率分析脚本，功能包括：
- 使用 gcovr 进行代码覆盖率分析
- 支持服务器监控和自动重启
- 生成行覆盖率和分支覆盖率报告

### 2. replay-libslmp.sh (115行)
测试用例回放脚本，功能包括：
- 使用 aflnet-replay 工具回放测试用例
- 支持失败重试机制（最多3次）
- 显示详细的回放统计信息

## 与参考脚本的对比

| 特性 | modbus | iec104 | ethernetip | libslmp |
|------|--------|--------|------------|---------|
| 协议名称 | MODBUS | IEC104 | ETHER_NETIP | SLMPB |
| 默认端口 | 1502/5502 | 2404 | 44818 | 8888 |
| 服务器程序 | server-coverage/modbus_server | iec104_monitor/iec104servertest | OpENer/eip_server_harness | svrskel_afl |
| 构建系统 | autotools/cmake | 混合 | cmake | cmake |
| 支持变体 | libmodbus/libplctag | iec104/freyrscada-iec104 | opener/eipscanner | libslmp2/libslmp2-ascii |

## 关键设计决策

### 1. 协议选择
- 使用 `SLMPB` (SLMP Binary) 作为协议名称
- 参考 Dockerfile 中的 AFL fuzzing 配置：`-P SLMPB`

### 2. 端口配置
- 默认端口：8888
- 与 Docker 容器配置保持一致

### 3. 服务器程序
- 使用 `svrskel_afl` 作为服务器程序
- 构建路径：`build-coverage/samples/svrskel/svrskel_afl`

### 4. 构建系统
- 使用 CMake 构建系统
- 覆盖率文件位置：`build-coverage/` 目录

### 5. Patch 应用
- 支持自动应用 `add-svrskel-afl.patch`
- 自动复制 `svrskel_afl.c` 文件

## 使用方法

### 基本用法
```bash
# 完整分析
./coverage-analysis/coverage-libslmp.sh libslmp2 aflnet 1

# ASCII 变体分析
./coverage-analysis/coverage-libslmp.sh libslmp2-ascii afl-ics 1
```

### 高级用法
```bash
# 仅重新编译
./coverage-analysis/coverage-libslmp.sh --rebuild-only

# 仅生成报告
./coverage-analysis/coverage-libslmp.sh --report-only

# 启动监控服务器
./coverage-analysis/coverage-libslmp.sh --monitor-only

# 查看帮助
./coverage-analysis/coverage-libslmp.sh --help
```

### 测试用例回放
```bash
# 手动回放测试用例
./coverage-analysis/replay-libslmp.sh libslmp2 aflnet 1
```

## 输出文件

### 覆盖率报告位置
```
/home/ecs-user/LLM_fuzz_experiment/coverage-reports/
├── coverage-line-libslmp2-aflnet-1.txt
└── coverage-branch-libslmp2-aflnet-1.txt
```

### 报告内容
- **行覆盖率报告**：显示 Lines/Exec/Cover 统计
- **分支覆盖率报告**：显示 Branches/Taken/Cover 统计

## 功能特性

### 1. 服务器监控
- 每5秒检查一次服务器状态
- 自动重启崩溃的服务器
- 最多重启100次

### 2. 覆盖率数据管理
- 自动清理旧的 .gcda 文件
- 防止覆盖率数据污染
- 优雅关闭服务器以确保数据写入

### 3. 错误处理
- 详细的状态输出（颜色编码）
- 端口占用自动释放
- 失败重试机制

## 参考文档

本脚本的设计参考了以下文件：
- `coverage-modbus.sh` - 构建系统和服务器管理
- `coverage-iec104.sh` - 多目标支持和patch应用
- `coverage-ethernetip.sh` - CMake构建和端口管理
- `replay-modbus.sh` - 测试用例回放机制

## 注意事项

1. **前提条件**：
   - 需要安装 gcovr
   - 需要 aflnet-replay 工具
   - 需要完成模糊测试并生成测试用例

2. **目录要求**：
   - fuzzing 输出目录必须存在
   - 至少有一个测试用例（id:* 文件）

3. **服务器要求**：
   - 端口 8888 必须可用
   - 服务器需要支持覆盖率编译标志

## 故障排除

### 问题：No .gcno files found
**解决方案**：检查 CMake 配置是否正确应用了覆盖率标志

### 问题：Server port not responding
**解决方案**：检查端口是否被占用，使用 `fuser -k 8888/tcp` 释放

### 问题：Patch already applied
**说明**：这是正常的，脚本会自动跳过已应用的 patch

## 版本信息

- 创建日期：2025-12-29
- 基于版本：modbus v1.0, iec104 v1.0, ethernetip v1.0
- 脚本版本：1.0

