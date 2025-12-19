#!/bin/bash

echo "停止所有 EIPScanner 模糊测试容器..."

docker compose -f docker-compose-eipscanner.yml down

echo "所有 EIPScanner 容器已停止"
