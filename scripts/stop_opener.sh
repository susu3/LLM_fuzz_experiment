#!/bin/bash

# 停止所有OpENer模糊测试容器

echo "停止 OpENer 模糊测试容器..."

docker compose -f docker-compose-opener.yml down

echo "OpENer 容器已停止"
