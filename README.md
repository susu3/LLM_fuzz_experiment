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
├── dockerfiles/           # 四个工具的Dockerfile
│   ├── Dockerfile.libmodbus.afl-ics
│   ├── Dockerfile.libmodbus.aflnet
│   ├── Dockerfile.libmodbus.chatafl
│   └── Dockerfile.libmodbus.a2
├── scripts/               # 管理脚本
│   ├── start_all.sh      # 启动所有容器并自动开始模糊测试
│   ├── stop_all.sh       # 停止所有容器
│   └── copy_results.sh   # 拷贝结果文件
├── results/              # 结果输出目录
├── docker-compose.yml    # 容器编排文件
└── env.example          # 环境变量配置示例
```

## 🚀 快速开始

### 1. 设置环境变量

```bash
# 设置必要的环境变量
export LLM_API_KEY=your-api-key-here

### 2. 启动所有容器并自动开始模糊测试

```bash
sudosudo usermod -aG docker $USER
newgrp docker

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
docker exec afl-ics-libmodbus cat /opt/fuzzing/results/afl-ics-out-libmodbus-1/fuzzer_stats
docker exec aflnet-libmodbus cat /opt/fuzzing/results/aflnet-out-libmodbus-1/fuzzer_stats
docker exec chatafl-libmodbus cat /opt/fuzzing/results/chatafl-out-libmodbus-1/fuzzer_stats
docker exec a2-libmodbus cat /opt/fuzzing/results/a2-out-libmodbus-1/fuzzer_stats

# 查看容器运行日志
docker compose logs -f afl-ics-libmodbus
docker compose logs -f aflnet-libmodbus
docker compose logs -f chatafl-libmodbus
docker compose logs -f a2-libmodbus
```

### 4. （可选）进入容器检查

```bash
# 如需要手动检查，可以进入容器
docker exec -it afl-ics-libmodbus /bin/bash
docker exec -it aflnet-libmodbus /bin/bash
docker exec -it chatafl-libmodbus /bin/bash
docker exec -it a2-libmodbus /bin/bash
```

### 5. 停止实验并收集结果

```bash
# 停止所有容器
./scripts/stop_all.sh

# # 拷贝第1次实验结果
# ./scripts/copy_results.sh 1

# # 拷贝第2次实验结果
# ./scripts/copy_results.sh 2

# # 拷贝第3次实验结果
# ./scripts/copy_results.sh 3
# ```

## 🔄 多次实验对比

框架支持运行多次独立实验进行结果对比：

```bash
# 运行第1次实验
./scripts/start_all.sh 1
# 等待实验完成（24小时或手动停止）
./scripts/stop_all.sh
./scripts/copy_results.sh 1

# 运行第2次实验  
./scripts/start_all.sh 2
# 等待实验完成
./scripts/stop_all.sh
./scripts/copy_results.sh 2

# 运行第3次实验
./scripts/start_all.sh 3
# 等待实验完成
./scripts/stop_all.sh
./scripts/copy_results.sh 3
```

每次实验的输出目录格式：
- `afl-ics-out-libmodbus-1`, `afl-ics-out-libmodbus-2`, ...
- `aflnet-out-libmodbus-1`, `aflnet-out-libmodbus-2`, ...
- `chatafl-out-libmodbus-1`, `chatafl-out-libmodbus-2`, ...
- `a2-out-libmodbus-1`, `a2-out-libmodbus-2`, ...

## 🔧 测试其他目标

要测试其他目标程序，只需简单修改：

### 方法1：手动修改Dockerfile

1. 修改 `dockerfiles/` 中的 `COPY` 路径指向新目标
2. 修改启动脚本中的模糊测试命令参数（端口、协议等）
3. 重新构建: `docker compose build`

### 方法2：创建新的Dockerfile和compose文件

1. 复制 `Dockerfile.libmodbus.*` 为 `Dockerfile.newtarget.*`
2. 复制 `docker-compose.yml` 为 `docker-compose-newtarget.yml`
3. 修改相关路径和容器名称

## 📊 工具差异

- **AFL-ICS** 和 **A2**: 需要使用 `-r` 参数指定规范文件
- **AFLNet** 和 **ChatAFL**: 不需要规范文件
- 每个工具都使用自己仓库中的输入文件 (`tutorials/libmodbus/in-modbus`)

## 🚨 注意事项

1. 确保 `/home/ecs-user/libmodbus` 路径存在且可访问
2. libmodbus目标程序直接从服务器拷贝，无需编译
3. 所有模糊测试工具使用AFLNet相同的编译方法
4. 容器启动后自动开始模糊测试，支持SSH断开后继续运行
5. 需要设置正确的代理和API密钥环境变量
6. 模糊测试会消耗大量CPU和内存资源
7. 结果文件会保存在 `./results/` 目录中

## 🔧 技术细节

- **编译方法**: 所有工具使用 `make clean all` + `cd llvm_mode && make`
- **目标处理**: libmodbus直接从 `/home/ecs-user/libmodbus` 拷贝，无需重新编译
- **自动化**: 容器启动后立即执行对应的afl-fuzz命令
- **工作目录**: 模糊测试在libmodbus/tests目录下运行，使用相对路径 `./server`
- **结果隔离**: 每个工具输出到独立的目录（`工具名-out-libmodbus-次数`）

---

这是一个精简且自动化的实验框架，专注于核心功能：构建4个Docker容器，自动并行运行模糊测试，可选进入容器查看状态，最后拷贝结果文件。