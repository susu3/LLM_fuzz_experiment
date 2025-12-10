#!/bin/bash

# 启动所有五个IEC104模糊测试工具的Docker容器并自动开始模糊测试

RUN_NUMBER="${1:-1}"

echo "启动五个IEC104模糊测试工具的Docker容器（实验次数: $RUN_NUMBER）..."

# 检查环境变量
if [[ -z "$LLM_API_KEY" ]]; then
    echo "警告: LLM_API_KEY 环境变量未设置"
fi

# 检查SSH agent是否运行
if ! ssh-add -l &>/dev/null; then
    echo "警告: SSH agent未运行或没有加载密钥"
    echo "请运行: ssh-add ~/.ssh/id_rsa (或你的私钥文件)"
fi

# 设置实验次数环境变量
export RUN_NUM="$RUN_NUMBER"

# 启用Docker BuildKit以支持SSH挂载
export DOCKER_BUILDKIT=1

# 构建并启动容器
echo "构建Docker镜像（使用BuildKit和SSH agent forwarding）..."
docker compose -f docker-compose-iec104.yml build

echo "启动容器并自动开始模糊测试（第 $RUN_NUMBER 次实验）..."
docker compose -f docker-compose-iec104.yml up -d

echo ""
echo "所有容器已启动，模糊测试自动运行中！"
echo ""
echo "容器状态："
docker compose -f docker-compose-iec104.yml ps

echo ""
echo "查看模糊测试实时状态："
echo "  docker exec afl-ics-iec104 cat /opt/fuzzing/results/iec104-afl-ics-${RUN_NUMBER}/fuzzer_stats"
echo "  docker exec aflnet-iec104 cat /opt/fuzzing/results/iec104-aflnet-${RUN_NUMBER}/fuzzer_stats"
echo "  docker exec chatafl-iec104 cat /opt/fuzzing/results/iec104-chatafl-${RUN_NUMBER}/fuzzer_stats"
echo "  docker exec a2-iec104 cat /opt/fuzzing/results/iec104-a2-${RUN_NUMBER}/fuzzer_stats"
echo "  docker exec a3-iec104 cat /opt/fuzzing/results/iec104-a3-${RUN_NUMBER}/fuzzer_stats"

echo ""
echo "查看容器日志："
echo "  docker compose -f docker-compose-iec104.yml logs -f afl-ics-iec104"
echo "  docker compose -f docker-compose-iec104.yml logs -f aflnet-iec104"
echo "  docker compose -f docker-compose-iec104.yml logs -f chatafl-iec104"
echo "  docker compose -f docker-compose-iec104.yml logs -f a2-iec104"
echo "  docker compose -f docker-compose-iec104.yml logs -f a3-iec104"

echo ""
echo "进入容器（可选）："
echo "  docker exec -it afl-ics-iec104 /bin/bash"
echo "  docker exec -it aflnet-iec104 /bin/bash"
echo "  docker exec -it chatafl-iec104 /bin/bash"
echo "  docker exec -it a2-iec104 /bin/bash"
echo "  docker exec -it a3-iec104 /bin/bash"

echo ""
echo "停止所有容器："
echo "  ./scripts/stop_iec104.sh"

echo ""
echo "拷贝结果文件："
echo "  ./scripts/copy_results_iec104.sh $RUN_NUMBER"
echo ""
echo "使用方法："
echo "  $0 [次数]     # 默认为第1次实验"
echo "  $0 1         # 第1次实验" 
echo "  $0 2         # 第2次实验"
echo "  $0 3         # 第3次实验"

