#!/bin/bash

# 为目标设置完整的实验环境

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

TARGET="$1"

if [[ -z "$TARGET" ]]; then
    echo "用法: $0 <target_name>"
    echo "例如: $0 libmodbus"
    exit 1
fi

CONFIG_FILE="$PROJECT_ROOT/targets/config/${TARGET}.yml"
TARGET_DIR="$PROJECT_ROOT/targets/$TARGET"

if [[ ! -f "$CONFIG_FILE" ]]; then
    echo "错误：配置文件不存在: $CONFIG_FILE"
    echo "请先运行: ./scripts/create_target.sh $TARGET"
    exit 1
fi

echo "为目标 $TARGET 设置实验环境..."

# 生成Dockerfile文件
echo "1. 生成Dockerfile文件..."
"$SCRIPT_DIR/generate_dockerfiles.sh" "$TARGET"

# 生成docker-compose.yml
echo "2. 生成docker-compose.yml..."
"$SCRIPT_DIR/generate_compose.sh" "$TARGET"

# 创建目标特定的脚本
echo "3. 创建目标特定的实验脚本..."

mkdir -p "$TARGET_DIR/scripts"

# 创建启动脚本
cat > "$TARGET_DIR/scripts/start_experiment.sh" << 'EOF'
#!/bin/bash

# 启动指定目标的模糊测试实验

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TARGET_DIR="$(dirname "$SCRIPT_DIR")"
TARGET_NAME="$(basename "$TARGET_DIR")"
PROJECT_ROOT="$(dirname "$(dirname "$TARGET_DIR")")"

RUN_NUMBER="${1:-1}"

echo "启动 $TARGET_NAME 模糊测试实验，运行次数: $RUN_NUMBER"

# 检查环境变量
if [[ -z "$HTTPS_PROXY" ]]; then
    echo "警告: HTTPS_PROXY 环境变量未设置"
fi

if [[ -z "$LLM_API_KEY" ]]; then
    echo "警告: LLM_API_KEY 环境变量未设置"
fi

# 设置环境变量
export RUN_NUMBER="$RUN_NUMBER"

# 检查是否有 .env 文件
if [[ -f "$PROJECT_ROOT/.env" ]]; then
    echo "加载 .env 文件..."
    source "$PROJECT_ROOT/.env"
elif [[ -f "$PROJECT_ROOT/env.example" ]]; then
    echo "未找到 .env 文件，请参考 env.example 创建"
fi

# 切换到目标目录
cd "$TARGET_DIR"

# 检查docker-compose文件
if [[ ! -f "docker-compose.yml" ]]; then
    echo "错误：docker-compose.yml不存在"
    echo "请先运行: ../../scripts/setup_target.sh $TARGET_NAME"
    exit 1
fi

# 停止已有的容器（如果存在）
echo "停止已有的容器..."
docker-compose down 2>/dev/null || true

# 构建镜像
echo "构建Docker镜像..."
docker-compose build

# 启动容器
echo "启动容器（后台运行）..."
docker-compose up -d

echo "实验已启动！"
echo ""
echo "运行状态检查:"
echo "  ../scripts/monitor.sh $TARGET_NAME"
echo ""
echo "进入容器:"
echo "  docker exec -it <container_name> /bin/bash"
echo ""
echo "查看日志:"
echo "  docker-compose logs -f"
echo ""
echo "停止实验:"
echo "  ../scripts/stop_experiment.sh $TARGET_NAME"
EOF

# 创建监控脚本
cat > "$TARGET_DIR/scripts/monitor.sh" << 'EOF'
#!/bin/bash

# 监控指定目标的实验状态

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TARGET_DIR="$(dirname "$SCRIPT_DIR")"
TARGET_NAME="$(basename "$TARGET_DIR")"

echo "=== $TARGET_NAME 模糊测试状态 ==="
echo ""

cd "$TARGET_DIR"

# 检查容器状态
echo "容器状态:"
docker-compose ps

echo ""
echo "容器资源使用:"
docker stats --no-stream --format "table {{.Container}}\t{{.CPUPerc}}\t{{.MemUsage}}\t{{.NetIO}}" 2>/dev/null | grep "$TARGET_NAME" || echo "未找到运行中的容器"

echo ""
echo "结果目录大小:"
RESULTS_DIR="../../results"
if [[ -d "$RESULTS_DIR" ]]; then
    find "$RESULTS_DIR" -name "*$TARGET_NAME*" -type d 2>/dev/null | while read dir; do
        size=$(du -sh "$dir" 2>/dev/null | cut -f1)
        echo "  $dir: $size"
    done
else
    echo "  结果目录不存在"
fi

echo ""
echo "实时查看日志: docker-compose logs -f"
echo "进入容器: docker exec -it <container_name> /bin/bash"
EOF

# 创建停止脚本
cat > "$TARGET_DIR/scripts/stop_experiment.sh" << 'EOF'
#!/bin/bash

# 停止指定目标的模糊测试实验

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TARGET_DIR="$(dirname "$SCRIPT_DIR")"
TARGET_NAME="$(basename "$TARGET_DIR")"

echo "停止 $TARGET_NAME 模糊测试实验..."

cd "$TARGET_DIR"

# 停止容器
docker-compose down

echo "实验已停止"
echo ""
echo "收集结果: ../scripts/collect_results.sh $TARGET_NAME"
EOF

# 创建结果收集脚本
cat > "$TARGET_DIR/scripts/collect_results.sh" << 'EOF'
#!/bin/bash

# 收集指定目标的实验结果

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TARGET_DIR="$(dirname "$SCRIPT_DIR")"
TARGET_NAME="$(basename "$TARGET_DIR")"
PROJECT_ROOT="$(dirname "$(dirname "$TARGET_DIR")")"

RUN_NUMBER="${1:-1}"
COLLECT_DIR="$PROJECT_ROOT/collected_results/${TARGET_NAME}/run_${RUN_NUMBER}_$(date +%Y%m%d_%H%M%S)"

echo "收集 $TARGET_NAME 第 $RUN_NUMBER 次实验结果..."

mkdir -p "$COLLECT_DIR"

# 收集结果文件
RESULTS_DIR="$PROJECT_ROOT/results"
if [[ -d "$RESULTS_DIR" ]]; then
    echo "复制结果文件..."
    find "$RESULTS_DIR" -name "*${TARGET_NAME}-${RUN_NUMBER}" -type d 2>/dev/null | while read dir; do
        tool_name=$(basename "$dir" | cut -d'-' -f1)
        echo "  收集 $tool_name 结果..."
        cp -r "$dir" "$COLLECT_DIR/"
    done
fi

# 收集日志
LOGS_DIR="$PROJECT_ROOT/logs"
if [[ -d "$LOGS_DIR" ]]; then
    echo "复制日志文件..."
    cp -r "$LOGS_DIR" "$COLLECT_DIR/"
fi

# 生成汇总报告
echo "生成汇总报告..."
cat > "$COLLECT_DIR/summary.txt" << SUMMARY
实验汇总报告
=================

目标: $TARGET_NAME
运行次数: $RUN_NUMBER
收集时间: $(date)

结果目录:
$(find "$COLLECT_DIR" -name "*-out-*" -type d | while read dir; do
    echo "  $(basename "$dir"): $(du -sh "$dir" | cut -f1)"
done)

SUMMARY

echo "结果收集完成！"
echo "收集目录: $COLLECT_DIR"
EOF

# 设置执行权限
chmod +x "$TARGET_DIR/scripts/"*.sh

echo "4. 创建结果收集目录..."
mkdir -p "$PROJECT_ROOT/collected_results/$TARGET"

echo ""
echo "目标 $TARGET 的实验环境设置完成！"
echo ""
echo "生成的文件："
echo "  - Dockerfile文件: dockerfiles/Dockerfile.*.$TARGET"
echo "  - docker-compose.yml: targets/$TARGET/docker-compose.yml"
echo "  - 实验脚本: targets/$TARGET/scripts/"
echo ""
echo "下一步："
echo "1. 检查并编辑配置文件: $CONFIG_FILE"
echo "2. 启动实验: cd targets/$TARGET && ./scripts/start_experiment.sh 1"
