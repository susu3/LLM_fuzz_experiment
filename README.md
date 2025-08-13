# LLM模糊测试对比实验框架

这是一个用于对比多个模糊测试工具性能的Docker化实验框架。支持四个AFL变种工具对不同网络协议目标进行并行模糊测试。

## 🔧 支持的工具

1. **AFL-ICS**: `git@github.com:susu3/AFL-ICS.git`
2. **AFLNet**: `git@github.com:susu3/aflnet-ICS-.git`
3. **ChatAFL**: `git@github.com:susu3/ChatAFL.git`
4. **A2**: `git@github.com:susu3/A2.git`

## 🎯 当前支持的测试目标

- **libmodbus**: MODBUS协议库 (位于 `/home/ecs-user/libmodbus`)

## 📁 项目结构

```
LLM_fuzz_experiment/
├── templates/              # Dockerfile和docker-compose模板
├── targets/                # 测试目标配置和脚本
│   ├── config/            # 目标配置文件
│   │   └── libmodbus.yml  # libmodbus配置
│   └── libmodbus/         # libmodbus实验环境
│       ├── docker-compose.yml
│       └── scripts/       # 目标特定脚本
├── dockerfiles/           # 生成的Dockerfile
├── scripts/               # 通用脚本
├── results/               # 实验结果输出
├── logs/                  # 运行日志
└── docs/                  # 详细文档
```

## 🚀 快速开始

### 1. 设置libmodbus实验

```bash
# 为libmodbus生成Docker文件和配置
./scripts/setup_target.sh libmodbus

# 启动实验（第1次运行）
cd targets/libmodbus
./scripts/start_experiment.sh 1
```

### 2. 监控实验状态

```bash
# 全局监控
./scripts/global_monitor.sh

# 特定目标监控
cd targets/libmodbus
./scripts/monitor.sh
```

### 3. 进入容器调试

```bash
# 进入特定工具容器
docker exec -it afl-ics-libmodbus /bin/bash
docker exec -it aflnet-libmodbus /bin/bash
docker exec -it chatafl-libmodbus /bin/bash
docker exec -it a2-libmodbus /bin/bash

# 查看AFL运行状态
docker exec -it afl-ics-libmodbus cat /opt/fuzzing/results/afl-ics-out-libmodbus-1/fuzzer_stats
```

### 4. 停止实验并收集结果

```bash
# 停止实验
cd targets/libmodbus
./scripts/stop_experiment.sh

# 收集结果
./scripts/collect_results.sh 1
```

## 🔄 多次实验

支持运行多次实验进行对比：

```bash
# 第2次实验
./scripts/start_experiment.sh 2

# 第3次实验  
./scripts/start_experiment.sh 3
```

输出目录将自动命名为：`{工具名}-out-{目标名}-{次数}`

## ⚙️ 环境配置

实验需要以下环境变量，请在服务器上手动设置：

### 方法1：直接设置环境变量

```bash
export HTTPS_PROXY=XXX
export LLM_API_KEY=XXX
```

### 方法2：使用环境配置文件

```bash
# 复制配置文件模板
cp env.example .env

# 编辑配置文件，设置实际的代理和API密钥值
vim .env
```

### 验证环境变量

```bash
echo "HTTPS_PROXY: $HTTPS_PROXY"
echo "LLM_API_KEY: $LLM_API_KEY"
```

## 📊 实验特性

- **24小时自动运行**: 每个实验自动运行24小时后停止
- **后台持续运行**: 支持SSH断开后继续运行
- **实时监控**: 可随时查看运行状态和资源使用
- **结果自动收集**: 实验结束后自动收集和整理结果
- **并行执行**: 四个工具同时运行，互不干扰

## 🔧 添加新的测试目标

### 1. 创建新目标配置

```bash
./scripts/create_target.sh <目标名>
```

### 2. 编辑配置文件

编辑 `targets/config/<目标名>.yml`，设置：
- 源代码路径
- 编译依赖和命令
- 网络端口和协议
- AFL命令参数

### 3. 生成实验环境

```bash
./scripts/setup_target.sh <目标名>
```

## 📖 详细文档

- [安装配置指南](docs/setup_guide.md)
- [使用说明](docs/usage_guide.md)
- [扩展指南](docs/extension_guide.md)
- [安全使用指南](docs/security_guide.md)
- [故障排除](docs/troubleshooting.md)

## 🎯 实验命令对比

**工具1 (AFL-ICS) 和工具4 (A2)** - 需要规范文件：
```bash
afl-fuzz -d -i /opt/fuzzing/A2/tutorials/libmodbus/in-modbus \
  -o $OUTPUT_DIR -N tcp://127.0.0.1/1502 -P MODBUS \
  -r /opt/fuzzing/A2/sample_specs/Markdown/modbus.md \
  -D 10000 -q 3 -s 3 -E -K -R ./server 1502
```

**工具2 (AFLNet) 和工具3 (ChatAFL)** - 不需要规范文件：
```bash
afl-fuzz -d -i /opt/fuzzing/A2/tutorials/libmodbus/in-modbus \
  -o $OUTPUT_DIR -N tcp://127.0.0.1/1502 -P MODBUS \
  -D 10000 -q 3 -s 3 -E -K -R ./server 1502
```

---

**注意**: 所有实验都在服务器环境中运行，确保目标程序路径正确且具有访问权限。
