#!/bin/bash

# 停止所有 libplctag 模糊测试容器

echo "停止所有 libplctag 模糊测试容器..."

docker compose -f docker-compose-libplctag.yml down

echo "所有 libplctag 容器已停止"
echo ""
echo "如需拷贝结果文件，请运行："
echo "  ./scripts/copy_results_libplctag.sh [次数]"

