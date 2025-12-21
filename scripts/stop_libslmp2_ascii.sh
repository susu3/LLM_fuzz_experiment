#!/bin/bash

# 停止所有libslmp2-ascii模糊测试容器

echo "停止 libslmp2-ascii 模糊测试容器..."

docker compose -f docker-compose-libslmp2-ascii.yml down

echo "libslmp2-ascii 容器已停止"
