#!/bin/bash

# 为指定目标生成所有Dockerfile

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

echo "为目标 $TARGET 生成Dockerfile..."

# 检查Python和PyYAML
if ! command -v python3 &> /dev/null; then
    echo "错误：需要安装Python3"
    exit 1
fi

python3 -c "import yaml" 2>/dev/null || {
    echo "安装PyYAML..."
    pip3 install PyYAML
}

# 为每个工具生成Dockerfile
TOOLS=("afl-ics" "aflnet" "chatafl" "a2")

for tool in "${TOOLS[@]}"; do
    echo "生成 Dockerfile.${tool}.${TARGET}..."
    
    python3 "$SCRIPT_DIR/template_processor.py" \
        --config "$CONFIG_FILE" \
        --tool "$tool" \
        --template "$PROJECT_ROOT/templates/Dockerfile.tool.template" \
        --output "$PROJECT_ROOT/dockerfiles/Dockerfile.${tool}.${TARGET}" \
        --type dockerfile
done

echo "所有Dockerfile生成完成！"
echo ""
echo "生成的文件："
ls -la "$PROJECT_ROOT/dockerfiles/Dockerfile.*.$TARGET"
