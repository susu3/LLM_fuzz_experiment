#!/bin/bash

# 停止所有IEC104模糊测试容器

echo "停止所有IEC104模糊测试容器..."

docker compose -f docker-compose-iec104.yml down

echo "所有容器已停止"
echo ""

