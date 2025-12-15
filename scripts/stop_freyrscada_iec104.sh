#!/bin/bash

echo "停止所有 FreyrSCADA IEC104 模糊测试容器..."

docker compose -f docker-compose-freyrscada-iec104.yml down

echo "所有 FreyrSCADA IEC104 容器已停止"

