#!/bin/bash

# 参数: ./replay-ethernetip.sh [target] [fuzzer] [run_number]
# 示例: ./replay-ethernetip.sh opener aflnet 1
#       ./replay-ethernetip.sh eipscanner afl-ics 1

# 参数解析（可选，默认为 opener）
TARGET_IMPL="${1:-opener}"     # opener 或 eipscanner
FUZZER="${2:-aflnet}"          # afl-ics, aflnet, chatafl, a2, a3
RUN_NUM="${3:-1}"              # 实验次数

# 设置输入文件目录和aflnet-replay路径
AFLNET_REPLAY="/home/ecs-user/AFL-ICS/aflnet-replay"  # 使用绝对路径
TARGET="ETHERNETIP"  # 协议名称
TARGET_PORT="44818"  # EtherNet/IP 使用 44818

# 根据目标实现调整路径
BASE_DIR="/home/ecs-user/LLM_fuzz_experiment"

if [ "$TARGET_IMPL" = "eipscanner" ]; then
    INPUT_DIR="$BASE_DIR/results/eipscanner-${FUZZER}-${RUN_NUM}/replayable-queue"
else
    INPUT_DIR="$BASE_DIR/results/opener-${FUZZER}-${RUN_NUM}/replayable-queue"
fi

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
        echo "Replay failed for $TESTCASE, attempt $((RETRY_COUNT + 1)) of $MAX_RETRIES"
        RETRY_COUNT=$((RETRY_COUNT + 1))
        sleep 1  # 在重试之前稍作等待
      fi
    done

    if [ $RETRY_COUNT -eq $MAX_RETRIES ]; then
      echo "Warning: $TESTCASE failed after $MAX_RETRIES attempts"
    fi
  fi
done

echo "Replay completed for all test cases in $INPUT_DIR"
