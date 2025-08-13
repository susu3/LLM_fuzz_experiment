#!/bin/bash

# 为指定目标生成docker-compose.yml文件

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

TARGET="$1"

if [[ -z "$TARGET" ]]; then
    echo "用法: $0 <target_name>"
    echo "例如: $0 libmodbus"
    exit 1
fi

CONFIG_FILE="$PROJECT_ROOT/targets/config/${TARGET}.yml"

if [[ ! -f "$CONFIG_FILE" ]]; then
    echo "错误：配置文件不存在: $CONFIG_FILE"
    exit 1
fi

echo "为目标 $TARGET 生成docker-compose.yml..."

# 创建目标目录
TARGET_DIR="$PROJECT_ROOT/targets/$TARGET"
mkdir -p "$TARGET_DIR"

# 生成docker-compose.yml
python3 "$SCRIPT_DIR/template_processor.py" \
    --config "$CONFIG_FILE" \
    --template "$PROJECT_ROOT/templates/docker-compose.template" \
    --output "$TARGET_DIR/docker-compose.yml" \
    --type compose

echo "docker-compose.yml生成完成！"
echo "文件位置: $TARGET_DIR/docker-compose.yml"
