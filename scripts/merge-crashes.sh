#!/bin/bash

# Crash Files Merger
# 合并多次实验的 replayable-crashes 目录，基于文件内容去重
# 
# 功能：
# 1. 自动扫描所有实验组（格式：target-fuzzer-N）
# 2. 合并同一实验组的所有 crashes
# 3. 基于 MD5 内容去重
# 4. 处理文件名冲突（添加来源后缀）
# 5. 输出详细统计信息

set -e

# 配置
BASE_DIR="/home/ecs-user/LLM_fuzz_experiment"
RESULTS_DIR="$BASE_DIR/results"

# 颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# 打印函数
print_header() {
    echo -e "${BLUE}╔══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║          Crash Files Merger - 合并实验 Crashes           ║${NC}"
    echo -e "${BLUE}╚══════════════════════════════════════════════════════════════╝${NC}"
    echo ""
}

print_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

print_step() {
    echo -e "${CYAN}➜${NC} $1"
}

# 检查结果目录
check_results_dir() {
    if [ ! -d "$RESULTS_DIR" ]; then
        print_error "结果目录不存在: $RESULTS_DIR"
        exit 1
    fi
    
    cd "$RESULTS_DIR"
}

# 扫描并识别实验组
scan_experiment_groups() {
    print_step "扫描实验目录..."
    
    # 使用关联数组存储实验组
    declare -gA experiment_groups      # 组名 -> 有crashes的run目录列表
    declare -gA group_total_runs       # 组名 -> 总run数（包括空的）
    declare -gA group_nonempty_runs    # 组名 -> 有crashes的run数
    declare -gA all_runs_in_group      # 组名 -> 所有run目录列表（包括空的）
    
    # 只处理这三种fuzzer
    local allowed_fuzzers="afl-ics aflnet chatafl"
    
    # 扫描所有匹配模式的目录
    for dir in */; do
        dir="${dir%/}"  # 移除尾部斜杠
        
        # 跳过已合并的目录
        if [[ "$dir" =~ -replayable-crashes$ ]]; then
            continue
        fi
        
        # 匹配模式：target-fuzzer-number
        if [[ "$dir" =~ ^(.+)-(afl-ics|aflnet|chatafl)-([0-9]+)$ ]]; then
            target="${BASH_REMATCH[1]}"
            fuzzer="${BASH_REMATCH[2]}"
            run_num="${BASH_REMATCH[3]}"
            
            # 只处理允许的fuzzer
            if [[ ! " $allowed_fuzzers " =~ " $fuzzer " ]]; then
                continue
            fi
            
            group_name="${target}-${fuzzer}"
            
            # 添加到所有runs列表
            if [ -z "${all_runs_in_group[$group_name]}" ]; then
                all_runs_in_group[$group_name]="$dir"
                group_total_runs[$group_name]=1
            else
                all_runs_in_group[$group_name]="${all_runs_in_group[$group_name]} $dir"
                group_total_runs[$group_name]=$((${group_total_runs[$group_name]} + 1))
            fi
            
            # 检查是否有 replayable-crashes 目录且不为空（排除README.txt）
            if [ -d "$dir/replayable-crashes" ]; then
                # 统计crash文件数（排除README.txt）
                crash_count=$(find "$dir/replayable-crashes" -type f ! -name "README.txt" 2>/dev/null | wc -l)
                
                if [ "$crash_count" -gt 0 ]; then
                    # 添加到有crashes的实验组
                    if [ -z "${experiment_groups[$group_name]}" ]; then
                        experiment_groups[$group_name]="$dir"
                        group_nonempty_runs[$group_name]=1
                    else
                        experiment_groups[$group_name]="${experiment_groups[$group_name]} $dir"
                        group_nonempty_runs[$group_name]=$((${group_nonempty_runs[$group_name]} + 1))
                    fi
                fi
            fi
        fi
    done
    
    # 输出找到的实验组
    if [ ${#all_runs_in_group[@]} -eq 0 ]; then
        print_warning "未找到任何实验组（仅处理afl-ics, aflnet, chatafl）"
        exit 0
    fi
    
    echo ""
    print_info "找到 ${#all_runs_in_group[@]} 个实验组（仅afl-ics, aflnet, chatafl）："
    for group in $(echo "${!all_runs_in_group[@]}" | tr ' ' '\n' | sort); do
        local total="${group_total_runs[$group]}"
        local nonempty="${group_nonempty_runs[$group]:-0}"
        
        if [ "$nonempty" -eq "$total" ]; then
            echo "  - ${group}: ${total} 次实验 (全部有crashes)"
        elif [ "$nonempty" -eq 0 ]; then
            echo "  - ${group}: ${total} 次实验 (${YELLOW}全部为空${NC})"
        else
            echo "  - ${group}: ${total} 次实验 (${nonempty} 个有crashes, $((total - nonempty)) 个为空)"
        fi
    done
    echo ""
}

# 计算文件 MD5
get_file_md5() {
    local file="$1"
    md5sum "$file" | awk '{print $1}'
}

# 合并单个实验组的 crashes
merge_group_crashes() {
    local group_name="$1"
    local run_dirs="${experiment_groups[$group_name]}"
    
    print_step "处理实验组: ${CYAN}${group_name}${NC}"
    
    # 创建输出目录
    local output_dir="${RESULTS_DIR}/${group_name}-replayable-crashes"
    mkdir -p "$output_dir"
    
    # 统计变量
    local total_files=0
    local processed_files=0
    local duplicates=0
    local conflicts=0
    
    # 使用关联数组跟踪 MD5 和文件信息
    declare -A md5_to_info     # MD5 -> 第一次出现的run号
    declare -A md5_count       # MD5 -> 出现次数（跨run）
    declare -A file_to_md5     # 文件路径 -> MD5
    
    echo ""
    print_info "  第一遍扫描：建立全局MD5映射..."
    
    # 第一遍：扫描所有文件，建立完整的MD5映射
    for run_dir in $run_dirs; do
        local crash_dir="$RESULTS_DIR/$run_dir/replayable-crashes"
        local run_num=$(echo "$run_dir" | grep -oP '\d+$')
        
        if [ ! -d "$crash_dir" ]; then
            continue
        fi
        
        while IFS= read -r -d '' crash_file; do
            local basename=$(basename "$crash_file")
            
            # 跳过 README.txt
            if [ "$basename" = "README.txt" ]; then
                continue
            fi
            
            total_files=$((total_files + 1))
            
            # 计算 MD5
            local md5=$(get_file_md5 "$crash_file")
            file_to_md5[$crash_file]="$md5"
            
            # 记录首次出现
            if [ -z "${md5_to_info[$md5]}" ]; then
                md5_to_info[$md5]="$run_num"
                md5_count[$md5]=1
            else
                md5_count[$md5]=$((${md5_count[$md5]} + 1))
            fi
        done < <(find "$crash_dir" -type f -print0)
    done
    
    # 统计每个run的详细信息
    declare -A run_total_files   # run -> 总文件数
    declare -A run_unique_files  # run -> 唯一文件数（全局唯一）
    declare -A run_dup_files     # run -> 重复文件数（与其他run重复）
    
    # 获取该组所有run目录（包括空的）
    local all_runs="${all_runs_in_group[$group_name]}"
    
    # 初始化统计（所有run，包括空的）
    for run_dir in $all_runs; do
        local run_num=$(echo "$run_dir" | grep -oP '\d+$')
        run_total_files[$run_num]=0
        run_unique_files[$run_num]=0
        run_dup_files[$run_num]=0
    done
    
    # 统计每个run的贡献（只处理有crashes的）
    for run_dir in $run_dirs; do
        local crash_dir="$RESULTS_DIR/$run_dir/replayable-crashes"
        local run_num=$(echo "$run_dir" | grep -oP '\d+$')
        
        if [ ! -d "$crash_dir" ]; then
            continue
        fi
        
        while IFS= read -r -d '' crash_file; do
            local basename=$(basename "$crash_file")
            
            # 跳过 README.txt
            if [ "$basename" = "README.txt" ]; then
                continue
            fi
            
            run_total_files[$run_num]=$((${run_total_files[$run_num]} + 1))
            
            local md5="${file_to_md5[$crash_file]}"
            
            # 判断是否唯一
            if [ "${md5_count[$md5]}" -eq 1 ]; then
                run_unique_files[$run_num]=$((${run_unique_files[$run_num]} + 1))
            else
                run_dup_files[$run_num]=$((${run_dup_files[$run_num]} + 1))
            fi
        done < <(find "$crash_dir" -type f -print0)
    done
    
    print_info "  第二遍扫描：合并文件..."
    
    # 第二遍：实际合并文件
    declare -A md5_copied      # 已复制的MD5
    declare -A filename_count  # 文件名计数
    
    for run_dir in $run_dirs; do
        local crash_dir="$RESULTS_DIR/$run_dir/replayable-crashes"
        local run_num=$(echo "$run_dir" | grep -oP '\d+$')
        
        if [ ! -d "$crash_dir" ]; then
            continue
        fi
        
        while IFS= read -r -d '' crash_file; do
            local basename=$(basename "$crash_file")
            
            # 跳过 README.txt
            if [ "$basename" = "README.txt" ]; then
                continue
            fi
            
            local md5="${file_to_md5[$crash_file]}"
            
            # 检查是否已经复制过这个MD5
            if [ -n "${md5_copied[$md5]}" ]; then
                # 内容重复，跳过
                duplicates=$((duplicates + 1))
            else
                # 新的唯一文件
                processed_files=$((processed_files + 1))
                md5_copied[$md5]=1
                
                # 处理文件名冲突
                local target_name="$basename"
                if [ -f "$output_dir/$target_name" ]; then
                    # 文件名已存在，添加来源后缀
                    local name_without_ext="${basename%.*}"
                    local ext="${basename##*.}"
                    
                    # 如果没有扩展名
                    if [ "$name_without_ext" = "$ext" ]; then
                        target_name="${basename}_from_run${run_num}"
                    else
                        target_name="${name_without_ext}_from_run${run_num}.${ext}"
                    fi
                    
                    conflicts=$((conflicts + 1))
                fi
                
                # 复制文件
                cp "$crash_file" "$output_dir/$target_name"
                filename_count[$basename]=$((${filename_count[$basename]:-0} + 1))
            fi
        done < <(find "$crash_dir" -type f -print0)
    done
    
    # 输出详细统计（显示所有run，包括空的，按run号排序）
    echo ""
    print_info "  各实验统计："
    
    # 获取所有run号并排序
    local all_run_nums=()
    for run_dir in $all_runs; do
        local run_num=$(echo "$run_dir" | grep -oP '\d+$')
        all_run_nums+=("$run_num")
    done
    
    # 排序run号
    IFS=$'\n' sorted_runs=($(sort -n <<<"${all_run_nums[*]}"))
    unset IFS
    
    for run_num in "${sorted_runs[@]}"; do
        local total="${run_total_files[$run_num]:-0}"
        local unique="${run_unique_files[$run_num]:-0}"
        local dup="${run_dup_files[$run_num]:-0}"
        
        if [ "$total" -eq 0 ]; then
            echo "    - Run #${run_num}: ${YELLOW}0 文件 (空)${NC}"
        elif [ "$dup" -eq 0 ]; then
            echo "    - Run #${run_num}: ${total} 文件 (${unique} 唯一)"
        else
            echo "    - Run #${run_num}: ${total} 文件 (${unique} 唯一, ${dup} 重复)"
        fi
    done
    
    echo ""
    print_info "  合并统计："
    echo "    - 总文件数:       ${total_files}"
    echo "    - 内容去重后:     ${processed_files}"
    echo "    - 重复文件(跳过): ${duplicates}"
    echo "    - 文件名冲突:     ${conflicts}"
    
    echo ""
    print_info "  ✓ 输出目录: ${output_dir}"
    echo ""
    echo "  ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
}

# 主函数
main() {
    print_header
    
    check_results_dir
    scan_experiment_groups
    
    # 统计有crashes的实验组数量
    local total_groups_with_crashes=${#experiment_groups[@]}
    
    if [ "$total_groups_with_crashes" -eq 0 ]; then
        print_warning "所有实验组都没有crashes文件，无需合并"
        exit 0
    fi
    
    local current_group=1
    
    print_step "开始合并 ${total_groups_with_crashes} 个有crashes的实验组..."
    echo ""
    
    # 处理每个有crashes的实验组（排序输出）
    for group in $(echo "${!experiment_groups[@]}" | tr ' ' '\n' | sort); do
        echo -e "${YELLOW}[${current_group}/${total_groups_with_crashes}]${NC}"
        merge_group_crashes "$group"
        current_group=$((current_group + 1))
    done
    
    # 最终总结
    echo ""
    print_header
    print_info "全部完成！"
    echo ""
    print_info "所有实验组合并结果："
    
    # 显示所有实验组（包括空的）
    for group in $(echo "${!all_runs_in_group[@]}" | tr ' ' '\n' | sort); do
        if [ -n "${experiment_groups[$group]}" ]; then
            # 有crashes的组
            local output_dir="${group}-replayable-crashes"
            local file_count=$(find "$RESULTS_DIR/$output_dir" -type f 2>/dev/null | wc -l)
            echo "  - ${output_dir}/ (${file_count} 文件)"
        else
            # 空的组
            echo "  - ${group}-replayable-crashes/ (${YELLOW}0 文件 - 所有run都为空${NC})"
        fi
    done
    echo ""
}

# 运行主函数
main "$@"

