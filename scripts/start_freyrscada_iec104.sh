#!/bin/bash

# 启动FreyrSCADA IEC104模糊测试容器

RUN_NUMBER="${1:-1}"

echo "启动 FreyrSCADA IEC104 模糊测试容器（实验次数: $RUN_NUMBER）..."

# 检查环境变量
if [[ -z "$LLM_API_KEY" ]]; then
    echo "警告: LLM_API_KEY 环境变量未设置"
fi

# 检查SSH agent
if ! ssh-add -l &>/dev/null; then
    echo "警告: SSH agent未运行或没有加载密钥"
    echo "请运行: ssh-add ~/.ssh/id_rsa"
fi

export RUN_NUM="$RUN_NUMBER"
export DOCKER_BUILDKIT=1

echo "构建 Docker 镜像（FreyrSCADA IEC104）..."
docker compose -f docker-compose-freyrscada-iec104.yml build

echo "启动容器（FreyrSCADA IEC104 - 第 $RUN_NUMBER 次实验）..."
docker compose -f docker-compose-freyrscada-iec104.yml up -d

echo ""
echo "所有 FreyrSCADA IEC104 容器已启动！"
echo ""
docker compose -f docker-compose-freyrscada-iec104.yml ps

echo ""
echo "查看日志："
echo "  docker logs -f afl-ics-freyrscada-iec104"
echo "  docker logs -f aflnet-freyrscada-iec104"
echo "  docker logs -f chatafl-freyrscada-iec104"
echo "  docker logs -f a2-freyrscada-iec104"
echo "  docker logs -f a3-freyrscada-iec104"
echo ""
echo "停止容器："
echo "  ./scripts/stop_freyrscada_iec104.sh"

