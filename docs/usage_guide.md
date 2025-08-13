# 使用说明

## 基本工作流程

### 1. 启动实验

```bash
# 进入libmodbus目标目录
cd targets/libmodbus

# 启动第1次实验
./scripts/start_experiment.sh 1

# 查看启动状态
./scripts/monitor.sh
```

### 2. 监控运行状态

#### 全局监控
```bash
# 查看所有目标的状态
./scripts/global_monitor.sh

# 停止所有实验
./scripts/global_monitor.sh --stop-all

# 收集所有结果
./scripts/global_monitor.sh --collect-all
```

#### 特定目标监控
```bash
cd targets/libmodbus

# 查看运行状态
./scripts/monitor.sh

# 查看实时日志
docker-compose logs -f

# 查看特定容器日志
docker-compose logs -f afl-ics-libmodbus
```

### 3. 进入容器调试

```bash
# 进入AFL-ICS容器
docker exec -it afl-ics-libmodbus /bin/bash

# 在容器内查看AFL状态
cd /opt/fuzzing/targets/libmodbus
cat /opt/fuzzing/results/afl-ics-out-libmodbus-1/fuzzer_stats

# 查看运行日志
cat /opt/fuzzing/logs/afl-ics.log
```

### 4. 手动控制实验

```bash
# 停止实验
./scripts/stop_experiment.sh

# 重启实验
./scripts/start_experiment.sh 1

# 启动新一轮实验
./scripts/start_experiment.sh 2
```

## 高级用法

### 自定义实验参数

编辑 `targets/config/libmodbus.yml` 来修改实验参数：

```yaml
# 修改运行时间
experiment:
  duration: 48h  # 改为48小时

# 修改AFL参数
tools:
  afl-ics:
    command: "afl-fuzz -d -i ... -D 20000 ..."  # 修改-D参数
```

重新生成Docker文件：
```bash
./scripts/setup_target.sh libmodbus
```

### 批量运行多次实验

```bash
# 连续运行5次实验
for i in {1..5}; do
    echo "启动第 $i 次实验"
    ./scripts/start_experiment.sh $i
    
    # 等待24小时
    sleep 86400
    
    # 停止并收集结果
    ./scripts/stop_experiment.sh
    ./scripts/collect_results.sh $i
    
    echo "第 $i 次实验完成"
done
```

### 实时性能监控

```bash
# 监控容器资源使用
watch -n 5 'docker stats --no-stream'

# 监控磁盘使用
watch -n 60 'du -sh results/*'

# 监控AFL统计信息
watch -n 30 'docker exec afl-ics-libmodbus cat /opt/fuzzing/results/afl-ics-out-libmodbus-1/fuzzer_stats | head -20'
```

## 结果分析

### 查看AFL统计信息

```bash
# 查看基本统计
docker exec afl-ics-libmodbus cat /opt/fuzzing/results/afl-ics-out-libmodbus-1/fuzzer_stats

# 关键指标
# - execs_done: 执行次数
# - corpus_count: 语料库大小  
# - unique_crashes: 唯一崩溃数
# - unique_hangs: 唯一挂起数
# - exec_speed: 执行速度
```

### 比较不同工具的性能

```bash
# 生成对比报告
./scripts/compare_results.sh 1

# 查看崩溃文件
ls -la results/*/crashes/

# 统计结果
echo "AFL-ICS crashes: $(ls results/afl-ics-out-libmodbus-1/crashes/ | wc -l)"
echo "AFLNet crashes: $(ls results/aflnet-out-libmodbus-1/crashes/ | wc -l)"
echo "ChatAFL crashes: $(ls results/chatafl-out-libmodbus-1/crashes/ | wc -l)"
echo "A2 crashes: $(ls results/a2-out-libmodbus-1/crashes/ | wc -l)"
```

## 常见使用场景

### 场景1：短期测试
```bash
# 修改为1小时测试
# 编辑配置文件中的duration或直接在容器内停止
docker exec afl-ics-libmodbus pkill afl-fuzz
```

### 场景2：资源受限环境
```bash
# 限制容器资源使用
# 在docker-compose.yml中添加：
# deploy:
#   resources:
#     limits:
#       cpus: '2.0'
#       memory: 4G
```

### 场景3：调试模式
```bash
# 以调试模式启动单个工具
docker run -it --rm \
  -v $(pwd)/results:/opt/fuzzing/results \
  -v /home/ecs-user/libmodbus:/opt/fuzzing/targets/libmodbus:ro \
  afl-ics-libmodbus /bin/bash
```

## 故障恢复

### 容器意外停止
```bash
# 检查容器状态
docker-compose ps

# 重启停止的容器
docker-compose restart afl-ics-libmodbus

# 查看容器退出原因
docker-compose logs afl-ics-libmodbus
```

### 磁盘空间不足
```bash
# 清理旧结果
rm -rf results/old_experiment_*

# 压缩结果文件
tar -czf results_backup.tar.gz results/
rm -rf results/
mkdir results
```

### 内存不足
```bash
# 查看内存使用
free -h

# 限制容器内存使用
# 在docker-compose.yml中添加内存限制
```
