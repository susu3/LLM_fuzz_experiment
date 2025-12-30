# 模糊测试工具对比实验
## 🔧 测试工具

1. **AFL-ICS**: `git@github.com:susu3/AFL-ICS.git`
2. **AFLNet**: `git@github.com:susu3/aflnet-ICS-.git`  
3. **ChatAFL**: `git@github.com:susu3/ChatAFL.git`
4. **A2**: `git@github.com:susu3/A2.git`
5. **A3**: `git@github.com:susu3/A3.git`

## 📁 项目结构

```
LLM_fuzz_experiment/
├── dockerfiles/              # Libmodbus的Dockerfile
│   ├── Dockerfile.libmodbus.afl-ics
│   ├── Dockerfile.libmodbus.aflnet
│   ├── Dockerfile.libmodbus.chatafl
│   ├── Dockerfile.libmodbus.a2
│   └── Dockerfile.libmodbus.a3
├── dockerfiles-iec104/       # IEC104的Dockerfile
├── dockerfiles-freyrscada-iec104/  # FreyrSCADA IEC104的Dockerfile
├── dockerfiles-libplctag/    # Libplctag的Dockerfile
├── dockerfiles-libslmp2/     # libslmp2的Dockerfile
├── dockerfiles-opener/       # OpENer的Dockerfile
├── dockerfiles-eipscanner/   # EIPScanner的Dockerfile
├── scripts/                  # 管理脚本
│   ├── start_all.sh         # 启动Libmodbus所有容器
│   ├── stop_all.sh          # 停止Libmodbus所有容器
│   ├── start_iec104.sh      # 启动IEC104所有容器
│   ├── stop_iec104.sh       # 停止IEC104所有容器
│   ├── start_libplctag.sh   # 启动Libplctag所有容器
│   ├── stop_libplctag.sh    # 停止Libplctag所有容器
│   ├── start_libslmp2.sh    # 启动libslmp2所有容器
│   ├── stop_libslmp2.sh     # 停止libslmp2所有容器
│   ├── start_opener.sh      # 启动OpENer所有容器
│   ├── stop_opener.sh       # 停止OpENer所有容器
│   ├── start_eipscanner.sh  # 启动EIPScanner所有容器
│   └── stop_eipscanner.sh   # 停止EIPScanner所有容器
├── coverage-analysis/        # 覆盖率分析脚本
│   ├── coverage-modbus.sh   # Modbus覆盖率分析
│   ├── replay-modbus.sh     # Modbus测试用例重放
│   ├── coverage-iec104.sh   # IEC104覆盖率分析
│   ├── replay-iec104.sh     # IEC104测试用例重放
│   ├── coverage-ethernetip.sh  # EtherNet/IP覆盖率分析
│   ├── replay-ethernetip.sh    # EtherNet/IP测试用例重放
│   ├── coverage-libslmp.sh  # SLMP覆盖率分析
│   └── replay-libslmp.sh    # SLMP测试用例重放
├── results/                  # 结果输出目录
├── coverage-reports/         # 覆盖率报告目录
├── docker-compose.yml        # Libmodbus容器编排文件
├── docker-compose-iec104.yml # IEC104容器编排文件
├── docker-compose-freyrscada-iec104.yml  # FreyrSCADA IEC104容器编排文件
├── docker-compose-libplctag.yml  # Libplctag容器编排文件
├── docker-compose-libslmp2.yml   # libslmp2容器编排文件
├── docker-compose-opener.yml     # OpENer容器编排文件
├── docker-compose-eipscanner.yml # EIPScanner容器编排文件
└── README.md                # 项目说明文档
```

## 🚀 快速开始

### 1. 设置环境变量

```bash
# 设置必要的环境变量
export LLM_API_KEY=your-api-key-here

# 添加用户到docker组
sudo usermod -aG docker $USER
newgrp docker
```

### 2. 启动容器并自动开始模糊测试

以 **Libmodbus** 为例：

```bash
# 第1次实验（默认）
./scripts/start_all.sh

# 第2次实验
./scripts/start_all.sh 2

# 第3次实验
./scripts/start_all.sh 3
```

容器将自动开始运行模糊测试，无需手动干预。每次实验会创建独立的输出目录。

### 3. 监控运行状态

```bash
# 查看容器状态
docker compose ps

# 查看模糊测试实时统计信息（以第1次实验为例）
docker exec afl-ics-libmodbus cat /opt/fuzzing/results/libmodbus-afl-ics-1/fuzzer_stats
docker exec aflnet-libmodbus cat /opt/fuzzing/results/libmodbus-aflnet-1/fuzzer_stats
docker exec chatafl-libmodbus cat /opt/fuzzing/results/libmodbus-chatafl-1/fuzzer_stats
docker exec a2-libmodbus cat /opt/fuzzing/results/libmodbus-a2-1/fuzzer_stats
docker exec a3-libmodbus cat /opt/fuzzing/results/libmodbus-a3-1/fuzzer_stats

# 查看容器运行日志
docker compose logs -f afl-ics-libmodbus
```

### 4. （可选）进入容器检查

```bash
# 进入容器手动检查
docker exec -it afl-ics-libmodbus /bin/bash
```

### 5. 停止实验并查看结果

```bash
# 停止所有容器
./scripts/stop_all.sh

# 查看结果（结果已通过volume挂载同步到宿主机）
ls -lh ./results/
```

> 💡 **结果已实时同步**：容器运行时，结果会实时写入 `./results/` 目录，无需额外拷贝

## 🔄 多次实验对比

框架支持运行多次独立实验进行结果对比。以 Libmodbus 为例：

```bash
# 运行第1次实验
./scripts/start_all.sh 1
# 等待实验完成（24小时或手动停止）
./scripts/stop_all.sh

# 运行第2次实验  
./scripts/start_all.sh 2
# 等待实验完成
./scripts/stop_all.sh

# 运行第3次实验
./scripts/start_all.sh 3
# 等待实验完成
./scripts/stop_all.sh

# 查看所有实验结果
ls -lh ./results/
```

每次实验的输出目录格式：`协议名-工具名-次数`  
例如：`libmodbus-aflnet-1`, `iec104-afl-ics-2`, `libplctag-chatafl-3`

结果会实时保存在 `./results/` 目录，通过 Docker volume 挂载自动同步。

## 🔧 测试其他目标

要测试其他目标程序，只需简单修改：

### 创建新的Dockerfile和compose文件

1. 复制 `Dockerfile.libmodbus.*` 为 `Dockerfile.newtarget.*`
2. 复制 `docker-compose.yml` 为 `docker-compose-newtarget.yml`
3. 修改相关路径和容器名称

## 📊 工具差异

- **AFL-ICS**, **A2**, **A3**: 需要使用 `-r` 参数指定规范文件
- **AFLNet**, **ChatAFL**: 不需要规范文件
- 每个工具都使用自己仓库中的输入文件 (`tutorials/libmodbus/in-modbus`)
- 所有工具都支持 ASAN (AddressSanitizer) 进行内存错误检测

## 📈 覆盖率分析

项目提供了覆盖率分析脚本，可以分析模糊测试的代码覆盖率。以 Libmodbus 为例：

```bash
# 分析 aflnet 第1次实验的覆盖率
./coverage-analysis/coverage-modbus.sh libmodbus aflnet 1

# 分析 afl-ics 第1次实验的覆盖率
./coverage-analysis/coverage-modbus.sh libmodbus afl-ics 1
```

### 覆盖率报告

覆盖率报告保存在 `coverage-reports/` 目录：
- 行覆盖率报告: `coverage-line-{target}-{fuzzer}-{run}.txt`
- 分支覆盖率报告: `coverage-branch-{target}-{fuzzer}-{run}.txt`

## 🚨 注意事项

1. 所有目标程序都在Docker容器内自动克隆和编译
2. 容器启动后自动开始模糊测试，支持SSH断开后继续运行
3. 需要设置正确的SSH密钥（用于克隆私有仓库）和API密钥环境变量
4. 模糊测试会消耗大量CPU和内存资源
5. **结果文件通过 volume 自动同步**：`./results/` 目录实时包含所有测试结果，无需手动拷贝
6. 所有模糊测试工具都启用了 ASAN (AddressSanitizer) 进行内存错误检测

## 🎯 支持的协议

本框架支持以下工业控制协议的模糊测试：

| 协议 | 实现库数量 | 支持的实现 |
|------|-----------|-----------|
| **Modbus** | 2 | libmodbus, libplctag |
| **IEC104** | 2 | lib60870, FreyrSCADA |
| **EtherNet/IP** | 2 | OpENer, EIPScanner |
| **SLMP** | 1 | libslmp2 |

**总计**: 4种协议，7种实现库

每种实现都支持5种模糊测试工具（AFL-ICS, AFLNet, ChatAFL, A2, A3）的对比测试。

---

这是一个精简且自动化的实验框架，专注于核心功能：构建Docker容器，自动并行运行模糊测试，可选进入容器查看状态，支持覆盖率分析。支持 Modbus、IEC104、EtherNet/IP 和 SLMP 四种工业控制协议的模糊测试。