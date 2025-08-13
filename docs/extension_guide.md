# 扩展指南

## 添加新的测试目标

### 步骤1：创建目标配置

```bash
# 创建新目标（例如nginx）
./scripts/create_target.sh nginx
```

这将生成 `targets/config/nginx.yml` 配置模板。

### 步骤2：配置目标参数

编辑 `targets/config/nginx.yml`：

```yaml
target:
  name: nginx
  source_path: /home/ecs-user/nginx  # 实际路径
  port: 8080                         # 服务端口
  protocol: HTTP                     # 协议类型
  
  build:
    base_image: ubuntu:20.04
    dependencies:
      - libpcre3-dev                 # nginx特定依赖
      - zlib1g-dev
      - libssl-dev
    environment_vars:
      - "AFL_HARDEN=1"
      - "CC=afl-gcc"
    pre_build_commands:
      - "cd /opt/fuzzing/targets/nginx && ./auto/configure --with-debug --with-http_stub_status_module"
    build_commands:
      - "cd /opt/fuzzing/targets/nginx && make CC=afl-gcc"
    post_build_commands:
      - "cd /opt/fuzzing/targets/nginx && cp objs/nginx ./http-server"
      - "cd /opt/fuzzing/targets/nginx && chmod +x ./http-server"

tools:
  afl-ics:
    repo: git@github.com:susu3/AFL-ICS.git
    build_commands:
      - "make clean all"
    command: "afl-fuzz -d -i /opt/fuzzing/A2/tutorials/nginx/in-http -o $OUTPUT_DIR -N tcp://127.0.0.1/8080 -P HTTP -r /opt/fuzzing/A2/sample_specs/Markdown/http.md -D 10000 -q 3 -s 3 -E -K -R ./http-server 8080"
    needs_spec: true
    
  # ... 其他工具配置
```

### 步骤3：生成实验环境

```bash
# 生成所有Docker文件和脚本
./scripts/setup_target.sh nginx

# 启动实验
cd targets/nginx
./scripts/start_experiment.sh 1
```

## 添加新的模糊测试工具

### 步骤1：修改配置模板

在 `targets/config/libmodbus.yml` 中添加新工具：

```yaml
tools:
  # 现有工具...
  
  new-fuzzer:
    repo: git@github.com:user/new-fuzzer.git
    build_commands:
      - "make clean all"
      - "export PATH=/opt/fuzzing/tools/new-fuzzer:$PATH"
    command: "new-fuzz -i /opt/fuzzing/A2/tutorials/libmodbus/in-modbus -o $OUTPUT_DIR -t tcp://127.0.0.1/1502 ./server"
    needs_spec: false
```

### 步骤2：更新生成脚本

修改 `scripts/generate_dockerfiles.sh`：

```bash
# 添加新工具到工具列表
TOOLS=("afl-ics" "aflnet" "chatafl" "a2" "new-fuzzer")
```

### 步骤3：重新生成环境

```bash
./scripts/setup_target.sh libmodbus
```

## 自定义Docker镜像

### 创建自定义基础镜像

```dockerfile
# dockerfiles/custom-base.Dockerfile
FROM ubuntu:20.04

# 添加自定义配置
RUN apt-get update && apt-get install -y \
    custom-package \
    && rm -rf /var/lib/apt/lists/*

# 自定义环境设置
ENV CUSTOM_VAR=value
```

### 在配置中使用自定义镜像

```yaml
target:
  build:
    base_image: custom-base:latest  # 使用自定义镜像
```

## 扩展监控功能

### 添加自定义指标监控

创建 `scripts/custom_monitor.py`：

```python
#!/usr/bin/env python3
import docker
import json
import time

def collect_custom_metrics():
    client = docker.from_env()
    containers = client.containers.list()
    
    metrics = {}
    for container in containers:
        if 'libmodbus' in container.name:
            # 收集自定义指标
            stats = container.stats(stream=False)
            metrics[container.name] = {
                'cpu_usage': stats['cpu_stats']['cpu_usage']['total_usage'],
                'memory_usage': stats['memory_stats']['usage'],
                # 添加更多指标...
            }
    
    return metrics

if __name__ == '__main__':
    while True:
        metrics = collect_custom_metrics()
        print(json.dumps(metrics, indent=2))
        time.sleep(60)
```

### 集成到监控脚本

修改 `scripts/global_monitor.sh`，添加：

```bash
# 启动自定义监控
python3 scripts/custom_monitor.py > logs/custom_metrics.log &
```

## 添加结果分析工具

### 创建性能对比脚本

```bash
# scripts/compare_performance.py
#!/usr/bin/env python3
import os
import glob
import matplotlib.pyplot as plt

def analyze_fuzzer_stats(result_dir):
    stats_file = os.path.join(result_dir, 'fuzzer_stats')
    if not os.path.exists(stats_file):
        return None
    
    stats = {}
    with open(stats_file) as f:
        for line in f:
            if ':' in line:
                key, value = line.strip().split(':', 1)
                stats[key.strip()] = value.strip()
    
    return stats

def generate_comparison_report():
    tools = ['afl-ics', 'aflnet', 'chatafl', 'a2']
    metrics = {}
    
    for tool in tools:
        pattern = f"results/{tool}-out-*"
        dirs = glob.glob(pattern)
        if dirs:
            stats = analyze_fuzzer_stats(dirs[0])
            if stats:
                metrics[tool] = stats
    
    # 生成对比图表
    # ... 图表生成代码 ...
    
    print("性能对比报告已生成")

if __name__ == '__main__':
    generate_comparison_report()
```

## 配置文件高级选项

### 条件编译

```yaml
target:
  build:
    # 基于目标类型的条件配置
    conditional_commands:
      if_protocol_http:
        - "cd /opt/fuzzing/targets/${TARGET} && ./configure --enable-http"
      if_protocol_modbus:
        - "cd /opt/fuzzing/targets/${TARGET} && ./configure --enable-modbus"
```

### 动态参数替换

```yaml
tools:
  afl-ics:
    command: "afl-fuzz -d -i ${INPUT_DIR} -o ${OUTPUT_DIR} -N tcp://127.0.0.1/${PORT} -P ${PROTOCOL} -D ${DURATION:-10000} ./server ${PORT}"
    
# 在运行时替换变量
environment:
  INPUT_DIR: "/opt/fuzzing/A2/tutorials/${TARGET}/in-${PROTOCOL}"
  DURATION: "20000"  # 覆盖默认值
```

## 扩展网络协议支持

### 添加新协议

1. **更新A2仓库**：添加新协议的输入文件和规范
2. **修改配置**：在目标配置中指定新协议
3. **调整AFL参数**：根据协议特性调整模糊测试参数

```yaml
target:
  protocol: MQTT
  port: 1883

tools:
  afl-ics:
    command: "afl-fuzz -d -i /opt/fuzzing/A2/tutorials/${TARGET}/in-mqtt -o $OUTPUT_DIR -N tcp://127.0.0.1/1883 -P MQTT -r /opt/fuzzing/A2/sample_specs/Markdown/mqtt.md ./mqtt-server 1883"
```

## 部署到多台服务器

### 分布式部署配置

创建 `deploy/cluster-config.yml`：

```yaml
clusters:
  server1:
    host: 192.168.1.10
    targets: ["libmodbus", "nginx"]
    
  server2:
    host: 192.168.1.11
    targets: ["openssl", "mqtt"]

# 部署脚本
./scripts/deploy_cluster.sh cluster-config.yml
```

这样的扩展架构可以满足未来添加更多测试目标和工具的需求。
