#!/bin/bash

# 为新目标创建配置模板

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

TARGET="$1"

if [[ -z "$TARGET" ]]; then
    echo "用法: $0 <target_name>"
    echo "例如: $0 nginx"
    exit 1
fi

CONFIG_FILE="$PROJECT_ROOT/targets/config/${TARGET}.yml"
TARGET_DIR="$PROJECT_ROOT/targets/$TARGET"

if [[ -f "$CONFIG_FILE" ]]; then
    echo "警告：配置文件已存在: $CONFIG_FILE"
    read -p "是否覆盖？(y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "操作取消"
        exit 0
    fi
fi

echo "为目标 $TARGET 创建配置文件..."

# 创建目录
mkdir -p "$(dirname "$CONFIG_FILE")"
mkdir -p "$TARGET_DIR/scripts"

# 创建配置文件模板
cat > "$CONFIG_FILE" << EOF
target:
  name: $TARGET
  source_path: /home/ecs-user/$TARGET  # 修改为实际路径
  port: 8080  # 修改为实际端口
  protocol: HTTP  # 修改为实际协议
  
  # 目标特定的编译配置
  build:
    base_image: ubuntu:20.04
    dependencies:
      # 添加目标特定的依赖包
      # - libssl-dev
      # - zlib1g-dev
    environment_vars:
      - "AFL_HARDEN=1"
      - "CC=afl-gcc"
      - "CXX=afl-g++"
    pre_build_commands:
      # 编译前的准备命令
      # - "cd /opt/fuzzing/targets/$TARGET && ./configure"
    build_commands:
      # 编译命令
      # - "cd /opt/fuzzing/targets/$TARGET && make clean"
      # - "cd /opt/fuzzing/targets/$TARGET && make CC=afl-gcc"
    post_build_commands:
      # 编译后处理命令
      # - "cd /opt/fuzzing/targets/$TARGET && cp binary ./server"
      # - "cd /opt/fuzzing/targets/$TARGET && chmod +x ./server"

tools:
  afl-ics:
    repo: git@github.com:susu3/AFL-ICS.git
    build_commands:
      - "make clean all"
    command: "afl-fuzz -d -i /opt/fuzzing/A2/tutorials/$TARGET/in-$TARGET -o \$OUTPUT_DIR -N tcp://127.0.0.1/8080 -P HTTP -r /opt/fuzzing/A2/sample_specs/Markdown/$TARGET.md -D 10000 -q 3 -s 3 -E -K -R ./server 8080"
    needs_spec: true
    
  aflnet:
    repo: git@github.com:susu3/aflnet-ICS-.git
    build_commands:
      - "make clean all"
    command: "afl-fuzz -d -i /opt/fuzzing/A2/tutorials/$TARGET/in-$TARGET -o \$OUTPUT_DIR -N tcp://127.0.0.1/8080 -P HTTP -D 10000 -q 3 -s 3 -E -K -R ./server 8080"
    needs_spec: false
    
  chatafl:
    repo: git@github.com:susu3/ChatAFL.git
    build_commands:
      - "make clean all"
    command: "afl-fuzz -d -i /opt/fuzzing/A2/tutorials/$TARGET/in-$TARGET -o \$OUTPUT_DIR -N tcp://127.0.0.1/8080 -P HTTP -D 10000 -q 3 -s 3 -E -K -R ./server 8080"
    needs_spec: false
    
  a2:
    repo: git@github.com:susu3/A2.git
    build_commands:
      - "make clean all"
    command: "afl-fuzz -d -i /opt/fuzzing/A2/tutorials/$TARGET/in-$TARGET -o \$OUTPUT_DIR -N tcp://127.0.0.1/8080 -P HTTP -r /opt/fuzzing/A2/sample_specs/Markdown/$TARGET.md -D 10000 -q 3 -s 3 -E -K -R ./server 8080"
    needs_spec: true

experiment:
  duration: 24h
  parallel: true
  auto_collect_results: true
EOF

echo "配置文件已创建: $CONFIG_FILE"
echo ""
echo "请编辑配置文件以适配您的具体目标："
echo "1. 修改source_path为实际的目标程序路径"
echo "2. 修改port和protocol为实际值"
echo "3. 添加目标特定的依赖包"
echo "4. 设置正确的编译命令"
echo "5. 调整AFL命令参数"
echo ""
echo "编辑完成后，运行以下命令生成Docker文件："
echo "  ./scripts/generate_dockerfiles.sh $TARGET"
echo "  ./scripts/generate_compose.sh $TARGET"
