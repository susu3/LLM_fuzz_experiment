#!/bin/bash

# 参数: ./replay-libslmp.sh [fuzzer] [run_number]
# 示例: ./replay-libslmp.sh aflnet 1

# 参数解析
FUZZER="${1:-aflnet}"          # afl-ics, aflnet, chatafl, a2, a3
RUN_NUM="${2:-1}"              # 实验次数

# 设置输入文件目录和aflnet-replay路径
BASE_DIR="/home/ecs-user/LLM_fuzz_experiment"
INPUT_DIR="$BASE_DIR/results/libslmp2-${FUZZER}-${RUN_NUM}/replayable-queue"
AFLNET_REPLAY="/home/ecs-user/AFL-ICS/aflnet-replay"  # 使用绝对路径
TARGET="SLMPB"  # 协议名称 (SLMPB: SLMP Binary)
TARGET_PORT="8888"  # 端口

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

# 统计测试用例总数
TOTAL_TESTCASES=$(find "$INPUT_DIR" -name "id:*" -type f 2>/dev/null | wc -l)
echo "========================================"
echo "Input directory: $INPUT_DIR"
echo "Total test cases found: $TOTAL_TESTCASES"
echo "Target port: $TARGET_PORT"
echo "Protocol: $TARGET"
echo "========================================"

TESTCASE_COUNT=0
SUCCESS_COUNT=0
FAIL_COUNT=0

# 遍历输入目录中的所有以 "id:" 开头的文件
for TESTCASE in "$INPUT_DIR"/id:*; do
  if [ -f "$TESTCASE" ]; then
    TESTCASE_COUNT=$((TESTCASE_COUNT + 1))
    echo ""
    echo "[$TESTCASE_COUNT/$TOTAL_TESTCASES] Replaying: $TESTCASE"

    RETRY_COUNT=0
    MAX_RETRIES=3

    # 执行 aflnet-replay 并处理失败的情况
    while [ $RETRY_COUNT -lt $MAX_RETRIES ]; do
      # 检查服务器端口是否可用（等待最多30秒）
      port_check_count=0
      while ! nc -z 127.0.0.1 "$TARGET_PORT" 2>/dev/null && [ $port_check_count -lt 30 ]; do
        sleep 1
        port_check_count=$((port_check_count + 1))
      done
      
      if [ $port_check_count -ge 30 ]; then
        echo "Warning: Server port $TARGET_PORT not responding after 30 seconds"
      fi
      
      "$AFLNET_REPLAY" "$TESTCASE" "$TARGET" "$TARGET_PORT"
      if [ $? -eq 0 ]; then
        echo "✓ Replay succeeded for $TESTCASE"
        SUCCESS_COUNT=$((SUCCESS_COUNT + 1))
        break  # 成功时退出 while 循环
      else
        echo "Replay failed for $TESTCASE, attempt $((RETRY_COUNT + 1)) of $MAX_RETRIES"
        RETRY_COUNT=$((RETRY_COUNT + 1))
        # 等待更长时间让服务器恢复
        sleep 3
      fi
    done

    # 处理错误
    if [ "$RETRY_COUNT" -eq "$MAX_RETRIES" ]; then
      echo "✗ Warning: $TESTCASE failed after $MAX_RETRIES attempts"
      FAIL_COUNT=$((FAIL_COUNT + 1))
    fi
  fi
done

echo ""
echo "========================================"
echo "Replay Summary:"
echo "  Total test cases: $TESTCASE_COUNT"
echo "  Successful:       $SUCCESS_COUNT"
echo "  Failed:           $FAIL_COUNT"
if [ "$TESTCASE_COUNT" -gt 0 ]; then
  echo "  Success rate:     $(awk "BEGIN {printf \"%.2f\", ($SUCCESS_COUNT/$TESTCASE_COUNT)*100}")%"
else
  echo "  Success rate:     N/A (no test cases)"
fi
echo "========================================"

