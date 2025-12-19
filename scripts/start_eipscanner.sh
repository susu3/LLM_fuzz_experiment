#!/bin/bash

# 启动所有五个EIPScanner模糊测试工具的Docker容器并自动开始模糊测试

RUN_NUMBER="${1:-1}"

echo "启动 EIPScanner 模糊测试容器（实验次数: $RUN_NUMBER）..."

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
echo "构建 Docker 镜像（EIPScanner）..."
docker compose -f docker-compose-eipscanner.yml build

echo "启动容器（EIPScanner - 第 $RUN_NUMBER 次实验）..."
docker compose -f docker-compose-eipscanner.yml up -d

echo ""
echo "所有 EIPScanner 容器已启动！"
echo ""

docker compose -f docker-compose-eipscanner.yml ps

echo ""
echo "查看日志："
echo "  docker logs -f afl-ics-eipscanner"
echo "  docker logs -f aflnet-eipscanner"
echo "  docker logs -f chatafl-eipscanner"
echo "  docker logs -f a2-eipscanner"
echo "  docker logs -f a3-eipscanner"

echo ""
echo "停止容器："
echo "  ./scripts/stop_eipscanner.sh"
