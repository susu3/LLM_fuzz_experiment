# 模糊测试实验使用指南

## 概述

本项目对若干个工控协议的视线进行模糊测试，使用五个独立的模糊测试工具：
- **AFL-ICS**
- **AFLNet**
- **ChatAFL**
- **A2**
- **A3**

每个工具在独立的 Docker 容器中运行，互不影响。

---

## 快速开始

### 1. 启动所有四个模糊测试进程

```bash
# 启动第1次实验
./scripts/start_all.sh 1

# 启动第2次实验
./scripts/start_all.sh 2

# 启动第3次实验
./scripts/start_all.sh 3
```

**说明：** 这个命令会同时启动四个 Docker 容器，每个容器独立运行一个模糊测试工具。

---

### 2. 停止所有四个模糊测试进程

```bash
./scripts/stop_all.sh
```

**说明：** 这个命令会同时停止所有正在运行的模糊测试容器。

---

### 3. 拷贝结果到共同目录

```bash
# 拷贝第1次实验的结果
./scripts/copy_results.sh 1

# 拷贝第2次实验的结果
./scripts/copy_results.sh 2
```

**说明：** 
- 结果会被拷贝到 `copied_results_run<次数>_<时间戳>` 目录
- 每个模糊器的结果目录命名格式为：`libmodbus-<模糊器名称>-<次数>`

---

## 输出目录命名规则

容器内结果目录命名格式：
```
libmodbus-afl-ics-1      # AFL-ICS 第1次实验结果
libmodbus-aflnet-1       # AFLNet 第1次实验结果
libmodbus-chatafl-1      # ChatAFL 第1次实验结果
libmodbus-a2-1           # A2 第1次实验结果
```

拷贝后的本地目录示例：
```
copied_results_run1_20250814_113021/
  ├── libmodbus-afl-ics-1/
  ├── libmodbus-aflnet-1/
  ├── libmodbus-chatafl-1/
  └── libmodbus-a2-1/
```

---

## 查看模糊测试状态

### 查看容器状态
```bash
docker compose ps
```

### 查看模糊测试统计信息
```bash
# AFL-ICS
docker exec afl-ics-libmodbus cat /opt/fuzzing/results/libmodbus-afl-ics-1/fuzzer_stats

# AFLNet
docker exec aflnet-libmodbus cat /opt/fuzzing/results/libmodbus-aflnet-1/fuzzer_stats

# ChatAFL
docker exec chatafl-libmodbus cat /opt/fuzzing/results/libmodbus-chatafl-1/fuzzer_stats

# A2
docker exec a2-libmodbus cat /opt/fuzzing/results/libmodbus-a2-1/fuzzer_stats
```

### 查看容器日志
```bash
# 查看单个容器日志
docker compose logs -f afl-ics-libmodbus
docker compose logs -f aflnet-libmodbus
docker compose logs -f chatafl-libmodbus
docker compose logs -f a2-libmodbus

# 查看所有容器日志
docker compose logs -f
```

---

## 进入容器调试

```bash
# 进入 AFL-ICS 容器
docker exec -it afl-ics-libmodbus /bin/bash

# 进入 AFLNet 容器
docker exec -it aflnet-libmodbus /bin/bash

# 进入 ChatAFL 容器
docker exec -it chatafl-libmodbus /bin/bash

# 进入 A2 容器
docker exec -it a2-libmodbus /bin/bash
```

---

## 完整实验流程示例

```bash
# 步骤1: 启动第1次实验
./scripts/start_all.sh 1

# 步骤2: 等待一段时间让模糊测试运行（例如24小时）
# 可以使用上面的命令查看实时状态

# 步骤3: 停止所有容器
./scripts/stop_all.sh

# 步骤4: 拷贝结果
./scripts/copy_results.sh 1

# 步骤5: 开始第2次实验
./scripts/start_all.sh 2

# ... 重复上述流程
```

---

## 特性说明

✅ **独立运行** - 每个模糊测试工具在独立容器中运行，互不影响

✅ **一键启动** - 一个命令同时启动四个模糊测试进程

✅ **一键停止** - 一个命令同时停止所有模糊测试进程

✅ **统一收集** - 停止后可将所有结果拷贝到共同目录

✅ **规范命名** - 输出目录按照 `libmodbus-<模糊器>-<次数>` 格式命名

✅ **支持多次实验** - 通过次数参数支持多轮实验，结果互不覆盖

---

## 环境要求

- Docker 和 Docker Compose
- SSH 密钥配置（用于克隆私有仓库）
- 足够的磁盘空间存储模糊测试结果

---

## 故障排查

### 容器未启动
```bash
# 查看容器状态
docker compose ps

# 查看错误日志
docker compose logs
```

### 结果目录为空
```bash
# 检查容器内是否有结果
docker exec afl-ics-libmodbus ls -la /opt/fuzzing/results/
```

### 重新构建镜像
```bash
# 清理旧容器和镜像
docker compose down
docker system prune -a

# 重新构建
./scripts/start_all.sh 1
```

---

## 注意事项

1. 每次实验使用不同的次数参数，避免结果被覆盖
2. 在停止容器前确保拷贝了需要的结果
3. 模糊测试通常需要长时间运行（数小时到数天）
4. 注意监控系统资源使用情况（CPU、内存、磁盘）

