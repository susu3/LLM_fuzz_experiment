#!/bin/bash

# 停止所有libslmp2模糊测试容器

echo "停止 libslmp2 模糊测试容器..."

docker compose -f docker-compose-libslmp2.yml down

echo "libslmp2 容器已停止"
