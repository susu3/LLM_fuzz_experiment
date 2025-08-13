#!/bin/bash

# 停止所有模糊测试容器

echo "停止所有模糊测试容器..."

docker-compose down

echo "所有容器已停止"
echo ""
echo "如需拷贝结果文件，请运行："
echo "  ./scripts/copy_results.sh"
