#!/bin/bash

# 启动所有四个模糊测试工具的Docker容器并自动开始模糊测试

RUN_NUMBER="${1:-1}"

echo "启动四个模糊测试工具的Docker容器（实验次数: $RUN_NUMBER）..."

# 检查环境变量
if [[ -z "$HTTPS_PROXY" ]]; then
    echo "警告: HTTPS_PROXY 环境变量未设置"
fi

if [[ -z "$LLM_API_KEY" ]]; then
    echo "警告: LLM_API_KEY 环境变量未设置"
fi

# 设置实验次数环境变量
export RUN_NUM="$RUN_NUMBER"

# 构建并启动容器
echo "构建Docker镜像..."
docker-compose build

echo "启动容器并自动开始模糊测试（第 $RUN_NUMBER 次实验）..."
docker-compose up -d

echo ""
echo "所有容器已启动，模糊测试自动运行中！"
echo ""
echo "容器状态："
docker-compose ps

echo ""
echo "查看模糊测试实时状态："
echo "  docker exec afl-ics-libmodbus cat /opt/fuzzing/results/afl-ics-out-libmodbus-${RUN_NUMBER}/fuzzer_stats"
echo "  docker exec aflnet-libmodbus cat /opt/fuzzing/results/aflnet-out-libmodbus-${RUN_NUMBER}/fuzzer_stats"
echo "  docker exec chatafl-libmodbus cat /opt/fuzzing/results/chatafl-out-libmodbus-${RUN_NUMBER}/fuzzer_stats"
echo "  docker exec a2-libmodbus cat /opt/fuzzing/results/a2-out-libmodbus-${RUN_NUMBER}/fuzzer_stats"

echo ""
echo "查看容器日志："
echo "  docker-compose logs -f afl-ics-libmodbus"
echo "  docker-compose logs -f aflnet-libmodbus"
echo "  docker-compose logs -f chatafl-libmodbus"
echo "  docker-compose logs -f a2-libmodbus"

echo ""
echo "进入容器（可选）："
echo "  docker exec -it afl-ics-libmodbus /bin/bash"
echo "  docker exec -it aflnet-libmodbus /bin/bash"
echo "  docker exec -it chatafl-libmodbus /bin/bash"
echo "  docker exec -it a2-libmodbus /bin/bash"

echo ""
echo "停止所有容器："
echo "  ./scripts/stop_all.sh"

echo ""
echo "拷贝结果文件："
echo "  ./scripts/copy_results.sh $RUN_NUMBER"
echo ""
echo "使用方法："
echo "  $0 [次数]     # 默认为第1次实验"
echo "  $0 1         # 第1次实验" 
echo "  $0 2         # 第2次实验"
echo "  $0 3         # 第3次实验"
