# 修改记录

## 修改日期
2025年11月5日

## 修改目的
满足用户对模糊测试实验的五个需求。

---

## 需求检查结果

| 需求 | 状态 | 说明 |
|------|------|------|
| 1. 每个工具独立测试，互不影响 | ✅ 已满足 | 每个工具在独立的 Docker 容器中运行 |
| 2. 一个命令同时开启四个进程 | ✅ 已满足 | `start_all.sh` 脚本 |
| 3. 一个命令同时停止四个进程 | ✅ 已满足 | `stop_all.sh` 脚本 |
| 4. 停止后拷贝结果到共同目录 | ✅ 已满足 | `copy_results.sh` 脚本 |
| 5. 输出目录命名格式 | ✅ 已修改 | 从 `tool-out-libmodbus-次数` 改为 `libmodbus-tool-次数` |

---

## 修改内容

### 1. Dockerfile 修改

#### 修改文件：
- `dockerfiles/Dockerfile.libmodbus.afl-ics`
- `dockerfiles/Dockerfile.libmodbus.aflnet`
- `dockerfiles/Dockerfile.libmodbus.chatafl`
- `dockerfiles/Dockerfile.libmodbus.a2`

#### 修改内容：
将输出目录命名从：
```bash
# 旧格式
/opt/fuzzing/results/afl-ics-out-libmodbus-${RUN_NUM}
/opt/fuzzing/results/aflnet-out-libmodbus-${RUN_NUM}
/opt/fuzzing/results/chatafl-out-libmodbus-${RUN_NUM}
/opt/fuzzing/results/a2-out-libmodbus-${RUN_NUM}
```

改为：
```bash
# 新格式
/opt/fuzzing/results/libmodbus-afl-ics-${RUN_NUM}
/opt/fuzzing/results/libmodbus-aflnet-${RUN_NUM}
/opt/fuzzing/results/libmodbus-chatafl-${RUN_NUM}
/opt/fuzzing/results/libmodbus-a2-${RUN_NUM}
```

同时修复了 `Dockerfile.libmodbus.aflnet` 的 CMD 指令，确保容器启动时自动运行模糊测试：
```dockerfile
# 旧的（错误）
CMD ["/bin/bash"]

# 新的（正确）
CMD ["/opt/fuzzing/start_fuzzing.sh"]
```

---

### 2. 脚本文件修改

#### 2.1 `scripts/start_all.sh`
更新了查看模糊测试状态的路径提示，匹配新的目录命名格式：
```bash
# 示例
docker exec afl-ics-libmodbus cat /opt/fuzzing/results/libmodbus-afl-ics-${RUN_NUMBER}/fuzzer_stats
```

#### 2.2 `scripts/copy_results.sh`
更新了结果目录的命名规则：
```bash
# 旧格式
result_dir="${tool}-out-libmodbus-${RUN_NUMBER}"
docker cp "$container:/opt/fuzzing/results/$result_dir" "$OUTPUT_DIR/${tool}_results"

# 新格式
result_dir="libmodbus-${tool}-${RUN_NUMBER}"
docker cp "$container:/opt/fuzzing/results/$result_dir" "$OUTPUT_DIR/$result_dir"
```

拷贝到本地时，保持原有的命名格式（`libmodbus-tool-次数`），而不是改为其他名称。

#### 2.3 `scripts/run_fuzzing.sh`
更新了手动运行模糊测试时的输出目录路径，匹配新的命名格式。

---

### 3. 文档创建

#### 3.1 `USAGE.md`
创建了详细的使用指南，包含：
- 快速开始指南
- 输出目录命名规则说明
- 查看模糊测试状态的命令
- 完整实验流程示例
- 故障排查指南
- 注意事项

#### 3.2 `CHANGES.md`（本文档）
记录了所有的修改内容和原因。

---

## 命名格式对比

### 旧格式
```
容器内：aflnet-out-libmodbus-1
拷贝后：aflnet_results/
```

### 新格式（符合用户需求）
```
容器内：libmodbus-aflnet-1
拷贝后：libmodbus-aflnet-1/
```

### 命名规则
```
格式：libmodbus-<fuzzer>-<run_number>

示例：
- libmodbus-afl-ics-1    （AFL-ICS 第1次实验）
- libmodbus-aflnet-2     （AFLNet 第2次实验）
- libmodbus-chatafl-3    （ChatAFL 第3次实验）
- libmodbus-a2-1         （A2 第1次实验）
```

---

## 使用示例

### 启动第1次实验
```bash
./scripts/start_all.sh 1
```

容器内会生成以下目录：
- `/opt/fuzzing/results/libmodbus-afl-ics-1`
- `/opt/fuzzing/results/libmodbus-aflnet-1`
- `/opt/fuzzing/results/libmodbus-chatafl-1`
- `/opt/fuzzing/results/libmodbus-a2-1`

### 停止并拷贝结果
```bash
./scripts/stop_all.sh
./scripts/copy_results.sh 1
```

本地会生成目录（示例）：
```
copied_results_run1_20251105_143021/
├── libmodbus-afl-ics-1/
│   ├── queue/
│   ├── crashes/
│   └── fuzzer_stats
├── libmodbus-aflnet-1/
│   ├── queue/
│   ├── crashes/
│   └── fuzzer_stats
├── libmodbus-chatafl-1/
│   └── ...
└── libmodbus-a2-1/
    └── ...
```

---

## 向后兼容性

**注意：** 这些修改改变了输出目录的命名格式，因此：

1. **需要重新构建 Docker 镜像**
   ```bash
   docker compose build
   ```

2. **旧的结果目录不会自动迁移**
   - 旧格式的结果（如 `aflnet-out-libmodbus-1`）仍然保留在 `results/` 目录中
   - 新的实验会使用新格式（如 `libmodbus-aflnet-1`）

3. **建议**
   - 如果需要保留旧结果，请先备份 `results/` 目录
   - 清理旧容器：`docker compose down`
   - 重新构建并启动：`./scripts/start_all.sh 1`

---

## 测试建议

在正式运行长时间实验前，建议进行短时间测试：

```bash
# 1. 启动所有容器
./scripts/start_all.sh 1

# 2. 等待几分钟，检查容器状态
docker compose ps

# 3. 检查结果目录是否正确创建
docker exec afl-ics-libmodbus ls -la /opt/fuzzing/results/
docker exec aflnet-libmodbus ls -la /opt/fuzzing/results/
docker exec chatafl-libmodbus ls -la /opt/fuzzing/results/
docker exec a2-libmodbus ls -la /opt/fuzzing/results/

# 4. 停止容器
./scripts/stop_all.sh

# 5. 拷贝结果并检查
./scripts/copy_results.sh 1
ls -la copied_results_run1_*/
```

---

## 技术细节

### Docker Compose
- 使用 `docker compose up -d` 同时启动所有容器
- 使用 `docker compose down` 同时停止所有容器
- 每个容器通过环境变量 `RUN_NUM` 接收实验次数

### 环境变量传递
```
宿主机 → Docker Compose → 容器启动脚本
RUN_NUM=${RUN_NUM} → environment: - RUN_NUM=${RUN_NUM} → OUTPUT_DIR="/opt/fuzzing/results/libmodbus-tool-${RUN_NUM}"
```

### 容器独立性
- 每个容器有独立的网络空间
- 每个容器有独立的文件系统
- 通过 volume 挂载共享 `results/` 目录到宿主机
- 容器之间不会相互干扰

---

## 未来改进建议

1. **添加自动化测试脚本**
   - 自动检查容器是否正常启动
   - 自动检查模糊测试是否正常运行
   - 自动收集和分析结果

2. **添加监控脚本**
   - 实时监控四个容器的资源使用情况
   - 定期检查模糊测试进度
   - 异常情况自动告警

3. **添加结果分析脚本**
   - 自动比较四个工具的测试效果
   - 生成可视化报告
   - 统计覆盖率、crash数量等指标

4. **支持并行多次实验**
   - 同时运行多次实验（不同的次数）
   - 更好的资源隔离和管理

---

## 联系信息

如有问题或建议，请通过以下方式联系：
- 提交 Issue
- 创建 Pull Request
- 发送邮件

---

**文档版本：** 1.0  
**最后更新：** 2025年11月5日

