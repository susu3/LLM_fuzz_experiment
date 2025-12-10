#!/bin/bash

# 参数: ./replay-iec104.sh [fuzzer] [run_number]
# 示例: ./replay-iec104.sh aflnet 1
#       ./replay-iec104.sh afl-ics 1

# 参数解析（可选，默认为 aflnet）
FUZZER="${1:-aflnet}"          # afl-ics, aflnet, chatafl, a2, a3
RUN_NUM="${2:-1}"              # 实验次数

# 设置输入文件目录和aflnet-replay路径
INPUT_DIR="/fuzzing/out-iec104/replayable-queue"  # 默认路径，会被下面覆盖
AFLNET_REPLAY="/home/ecs-user/AFL-ICS/aflnet-replay"  # 使用绝对路径
TARGET="IEC104"  # 协议名称（IEC104使用与MODBUS类似的重放方式）
TARGET_PORT="10000"  # IEC104 使用 10000

# 根据模糊测试工具调整路径（使用绝对路径）
BASE_DIR="/home/ecs-user/LLM_fuzz_experiment"

INPUT_DIR="$BASE_DIR/results/iec104-${FUZZER}-${RUN_NUM}/replayable-queue"

# 如果 replayable-queue 不存在，尝试 queue 目录
if [ ! -d "$INPUT_DIR" ]; then
    INPUT_DIR="${INPUT_DIR%/replayable-queue}/queue"
fi

# 检查输入目录是否存在
if [ ! -d "$INPUT_DIR" ]; then
  echo "Error: Input directory $INPUT_DIR does not exist!"
  exit 1
fi

# 检查aflnet-replay是否可执行
if [ ! -x "$AFLNET_REPLAY" ]; then
  echo "Error: aflnet-replay not found or not executable at $AFLNET_REPLAY"
  exit 1
fi

# 遍历输入目录中的所有以 "id:" 开头的文件
for TESTCASE in "$INPUT_DIR"/id:*; do
  if [ -f "$TESTCASE" ]; then
    echo "Replaying test case: $TESTCASE"

    RETRY_COUNT=0
    MAX_RETRIES=3

    # 执行 aflnet-replay 并处理失败的情况
    while [ $RETRY_COUNT -lt $MAX_RETRIES ]; do
      "$AFLNET_REPLAY" "$TESTCASE" "$TARGET" "$TARGET_PORT"
      if [ $? -eq 0 ]; then
        echo "Replay succeeded for $TESTCASE"
        break  # 成功时退出 while 循环
      else
	RETRY_COUNT=$((RETRY_COUNT+1))
        echo "Replay failed for $TESTCASE. Retrying in 10 seconds..."
        sleep 10
      fi
    done

    #处理错误
    if [ "$RETRY_COUNT" -eq "$MAX_RETRIES" ]; then
	echo "Replay failed after $MAX_RETRIES attempts for $TESTCASE. Skipping"
    fi
  fi
done

echo "All test cases replayed."

