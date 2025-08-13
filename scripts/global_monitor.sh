#!/bin/bash

# 全局监控所有目标的实验状态

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

echo "=== 全局模糊测试监控面板 ==="
echo "监控时间: $(date)"
echo ""

# 检查所有目标
TARGETS_DIR="$PROJECT_ROOT/targets"
if [[ -d "$TARGETS_DIR" ]]; then
    for target_dir in "$TARGETS_DIR"/*/; do
        if [[ -d "$target_dir" ]]; then
            target_name=$(basename "$target_dir")
            
            # 跳过config目录
            if [[ "$target_name" == "config" ]]; then
                continue
            fi
            
            echo "--- $target_name ---"
            
            # 检查是否有运行中的容器
            cd "$target_dir"
            if [[ -f "docker-compose.yml" ]]; then
                running_containers=$(docker-compose ps -q 2>/dev/null | wc -l)
                if [[ $running_containers -gt 0 ]]; then
                    echo "状态: 运行中 ($running_containers 个容器)"
                    
                    # 显示容器状态
                    docker-compose ps --format "table {{.Name}}\t{{.State}}\t{{.Ports}}" 2>/dev/null
                    
                    # 显示资源使用
                    echo ""
                    echo "资源使用:"
                    docker stats --no-stream --format "table {{.Container}}\t{{.CPUPerc}}\t{{.MemUsage}}" 2>/dev/null | grep "$target_name" || echo "  无法获取资源信息"
                else
                    echo "状态: 已停止"
                fi
            else
                echo "状态: 未配置"
            fi
            
            # 检查结果目录
            echo ""
            echo "结果:"
            RESULTS_DIR="$PROJECT_ROOT/results"
            if [[ -d "$RESULTS_DIR" ]]; then
                result_count=$(find "$RESULTS_DIR" -name "*$target_name*" -type d 2>/dev/null | wc -l)
                if [[ $result_count -gt 0 ]]; then
                    echo "  发现 $result_count 个结果目录"
                    find "$RESULTS_DIR" -name "*$target_name*" -type d 2>/dev/null | head -5 | while read dir; do
                        size=$(du -sh "$dir" 2>/dev/null | cut -f1)
                        echo "    $(basename "$dir"): $size"
                    done
                    if [[ $result_count -gt 5 ]]; then
                        echo "    ... 还有 $((result_count - 5)) 个结果目录"
                    fi
                else
                    echo "  无结果文件"
                fi
            else
                echo "  结果目录不存在"
            fi
            
            echo ""
        fi
    done
else
    echo "未找到targets目录"
fi

echo "=== 系统资源概览 ==="
echo "CPU使用: $(top -l 1 | grep "CPU usage" | awk '{print $3}' | sed 's/%//' 2>/dev/null || echo '无法获取')"
echo "内存使用: $(top -l 1 | grep "PhysMem" | awk '{print $2}' 2>/dev/null || echo '无法获取')"
echo "磁盘使用: $(df -h . | tail -1 | awk '{print $5}' 2>/dev/null || echo '无法获取')"

echo ""
echo "=== 快捷命令 ==="
echo "查看特定目标: cd targets/<target_name> && ./scripts/monitor.sh"
echo "停止所有实验: $0 --stop-all"
echo "收集所有结果: $0 --collect-all"

# 处理命令行参数
if [[ "$1" == "--stop-all" ]]; then
    echo ""
    echo "停止所有实验..."
    for target_dir in "$TARGETS_DIR"/*/; do
        if [[ -d "$target_dir" && -f "$target_dir/docker-compose.yml" ]]; then
            target_name=$(basename "$target_dir")
            if [[ "$target_name" != "config" ]]; then
                echo "停止 $target_name..."
                cd "$target_dir"
                docker-compose down 2>/dev/null || true
            fi
        fi
    done
    echo "所有实验已停止"
fi

if [[ "$1" == "--collect-all" ]]; then
    echo ""
    echo "收集所有结果..."
    for target_dir in "$TARGETS_DIR"/*/; do
        if [[ -d "$target_dir" && -f "$target_dir/scripts/collect_results.sh" ]]; then
            target_name=$(basename "$target_dir")
            if [[ "$target_name" != "config" ]]; then
                echo "收集 $target_name 结果..."
                cd "$target_dir"
                ./scripts/collect_results.sh 1 2>/dev/null || echo "  收集失败"
            fi
        fi
    done
    echo "所有结果收集完成"
fi
