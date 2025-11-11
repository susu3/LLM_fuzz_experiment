#!/bin/bash

# 从容器中拷贝模糊测试结果文件

RUN_NUMBER="${1:-1}"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
OUTPUT_DIR="./copied_results_run${RUN_NUMBER}_${TIMESTAMP}"

echo "拷贝第 $RUN_NUMBER 次实验的结果..."
echo "创建输出目录: $OUTPUT_DIR"
mkdir -p "$OUTPUT_DIR"

CONTAINERS=("afl-ics-libmodbus" "aflnet-libmodbus" "chatafl-libmodbus" "a2-libmodbus" "a3-libmodbus")
TOOLS=("afl-ics" "aflnet" "chatafl" "a2" "a3")

for i in "${!CONTAINERS[@]}"; do
    container="${CONTAINERS[$i]}"
    tool="${TOOLS[$i]}"
    result_dir="libmodbus-${tool}-${RUN_NUMBER}"
    
    echo "从容器 $container 拷贝结果目录 $result_dir..."
    
    # 检查容器是否存在
    if docker ps -a --format "table {{.Names}}" | grep -q "^${container}$"; then
        # 拷贝特定次数的结果目录（保持原有命名格式）
        docker cp "$container:/opt/fuzzing/results/$result_dir" "$OUTPUT_DIR/$result_dir" 2>/dev/null || echo "  警告: 容器 $container 中没有结果目录 $result_dir"
        
        # 拷贝AFL统计信息（如果存在）
        docker exec "$container" test -f "/opt/fuzzing/results/$result_dir/fuzzer_stats" && \
        docker cp "$container:/opt/fuzzing/results/$result_dir/fuzzer_stats" "$OUTPUT_DIR/${result_dir}_fuzzer_stats" 2>/dev/null || echo "  注意: 未找到 $tool 的统计文件"
    else
        echo "  容器 $container 不存在"
    fi
done

echo ""
echo "结果拷贝完成！"
echo "输出目录: $OUTPUT_DIR"
echo ""
echo "查看结果："
echo "  ls -la $OUTPUT_DIR"
echo ""
echo "使用方法："
echo "  $0 [次数]     # 默认拷贝第1次实验结果"
echo "  $0 1         # 拷贝第1次实验结果"
echo "  $0 2         # 拷贝第2次实验结果"
