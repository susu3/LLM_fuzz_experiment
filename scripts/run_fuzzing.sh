#!/bin/bash

# 在指定容器中运行模糊测试命令的辅助脚本

CONTAINER="$1"
TOOL="$2"
RUN_NUM="${3:-1}"

if [[ -z "$CONTAINER" || -z "$TOOL" ]]; then
    echo "用法: $0 <container_name> <tool_name> [run_number]"
    echo ""
    echo "示例:"
    echo "  $0 afl-ics-libmodbus afl-ics 1"
    echo "  $0 aflnet-libmodbus aflnet 1"
    echo "  $0 chatafl-libmodbus chatafl 1"
    echo "  $0 a2-libmodbus a2 1"
    echo ""
    echo "run_number 默认为 1"
    exit 1
fi

echo "在容器 $CONTAINER 中运行 $TOOL 模糊测试..."

case "$TOOL" in
    "afl-ics")
        CMD="afl-fuzz -d -i /opt/fuzzing/AFL-ICS/tutorials/libmodbus/in-modbus -o /opt/fuzzing/results/afl-ics-out-libmodbus-${RUN_NUM} -N tcp://127.0.0.1/1502 -P MODBUS -r /opt/fuzzing/AFL-ICS/sample_specs/Markdown/modbus.md -D 10000 -q 3 -s 3 -E -K -R ./server 1502"
        ;;
    "aflnet")
        CMD="afl-fuzz -d -i /opt/fuzzing/aflnet-ICS-/tutorials/libmodbus/in-modbus -o /opt/fuzzing/results/aflnet-out-libmodbus-${RUN_NUM} -N tcp://127.0.0.1/1502 -P MODBUS -D 10000 -q 3 -s 3 -E -K -R ./server 1502"
        ;;
    "chatafl")
        CMD="afl-fuzz -d -i /opt/fuzzing/chatafl/ChatAFL/tutorials/libmodbus/in-modbus -o /opt/fuzzing/results/chatafl-out-libmodbus-${RUN_NUM} -N tcp://127.0.0.1/1502 -P MODBUS -D 10000 -q 3 -s 3 -E -K -R ./server 1502"
        ;;
    "a2")
        CMD="afl-fuzz -d -i /opt/fuzzing/A2/tutorials/libmodbus/in-modbus -o /opt/fuzzing/results/a2-out-libmodbus-${RUN_NUM} -N tcp://127.0.0.1/1502 -P MODBUS -r /opt/fuzzing/A2/sample_specs/Markdown/modbus.md -D 10000 -q 3 -s 3 -E -K -R ./server 1502"
        ;;
    *)
        echo "错误: 不支持的工具 $TOOL"
        echo "支持的工具: afl-ics, aflnet, chatafl, a2"
        exit 1
        ;;
esac

echo "执行命令: $CMD"
echo ""
echo "进入容器并手动执行此命令，或者直接运行："
echo "docker exec -it $CONTAINER bash -c \"cd /opt/fuzzing/libmodbus/tests && $CMD\""
