#!/bin/bash

# Coverage Analysis Script for SLMP Fuzzing
# This script uses gcovr to analyze code coverage after replaying test cases
# Includes server monitoring and automatic restart functionality
# 使用方法: ./coverage-libslmp.sh [fuzzer] [run_number]
# 示例: ./coverage-libslmp.sh aflnet 1

set -e

# 参数解析
FUZZER="${1:-aflnet}"          # afl-ics, aflnet, chatafl, a2, a3
RUN_NUM="${2:-1}"              # 实验次数

# Configuration（使用绝对路径）
BASE_DIR="/home/ecs-user/LLM_fuzz_experiment"
TARGET_IMPL="libslmp2"
SLMP_DIR="$BASE_DIR/libslmp2"
OUTPUT_DIR="$BASE_DIR/results/libslmp2-${FUZZER}-${RUN_NUM}"
COVERAGE_DIR="$BASE_DIR/coverage-reports"
REPLAY_SCRIPT="$BASE_DIR/coverage-analysis/replay-libslmp.sh"
SERVER_PORT="8888"

SERVER_CHECK_INTERVAL=5  # Check server status every 5 seconds
MAX_SERVER_RESTART_ATTEMPTS=100  # 增加重启次数限制

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}=== SLMP Coverage Analysis Tool ===${NC}"
echo -e "${BLUE}Target: libslmp2 | Fuzzer: $FUZZER | Run: #$RUN_NUM${NC}"

# Global variables
SERVER_PID=""
COVERAGE_SERVER_RUNNING=false
SERVER_RESTART_COUNT=0

# Function to print colored messages
print_status() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check if required directories exist
check_prerequisites() {
    print_status "Checking prerequisites..."
    
    if [ ! -d "$SLMP_DIR" ]; then
        print_error "SLMP directory not found: $SLMP_DIR"
        exit 1
    fi
    
    if [ ! -d "$OUTPUT_DIR" ]; then
        print_error "Fuzzing output directory not found: $OUTPUT_DIR"
        exit 1
    fi
    
    if [ ! -f "$REPLAY_SCRIPT" ]; then
        print_error "Replay script not found: $REPLAY_SCRIPT"
        exit 1
    fi
    
    # Check if gcovr is available
    if ! command -v gcovr &> /dev/null; then
        print_error "gcovr is not installed or not in PATH"
        exit 1
    fi
    
    print_status "All prerequisites satisfied"
}

# Rebuild with coverage flags
rebuild_with_coverage() {
    print_status "Rebuilding libslmp2 with coverage instrumentation..."
    
    cd "$SLMP_DIR"
    
    # Configure with coverage flags
    export CFLAGS="-fprofile-arcs -ftest-coverage -O0 -g"
    export CXXFLAGS="-fprofile-arcs -ftest-coverage -O0 -g"
    export LDFLAGS="-fprofile-arcs -ftest-coverage"
    
    # 彻底清理之前的覆盖率数据
    print_status "Cleaning previous coverage data..."
    OLD_GCDA=$(find . -name "*.gcda" 2>/dev/null | wc -l)
    OLD_GCNO=$(find . -name "*.gcno" 2>/dev/null | wc -l)
    print_status "Found $OLD_GCDA old .gcda files and $OLD_GCNO old .gcno files"
    
    rm -rf build-coverage
    find . -name "*.gcda" -delete 2>/dev/null || true
    find . -name "*.gcno" -delete 2>/dev/null || true
    
    print_status "Old coverage data cleaned. Starting fresh build..."
    
    # 修复 CMake 版本兼容性问题（现代 CMake 不支持 < 3.5）
    print_status "Fixing CMake version compatibility..."
    # 使用通用正则表达式匹配所有 2.x 版本
    find . -name "CMakeLists.txt" -type f -exec sed -i 's/cmake_minimum_required(VERSION 2\.[0-9]\+\.[0-9]\+)/cmake_minimum_required(VERSION 3.5.0)/' {} \; 2>/dev/null || true
    find . -name "CMakeLists.txt" -type f -exec sed -i 's/cmake_minimum_required(VERSION 2\.[0-9]\+)/cmake_minimum_required(VERSION 3.5.0)/' {} \; 2>/dev/null || true
    print_status "CMake version updated to 3.5.0 in all CMakeLists.txt files"
    
    # 检查是否需要复制文件
    if [ ! -f "samples/svrskel/svrskel_afl.c" ]; then
        print_status "Copying svrskel_afl.c..."
        cp "$BASE_DIR/dockerfiles-libslmp2/svrskel_afl.c" samples/svrskel/
    fi
    
    # 始终复制 svrskel_afl_coverage.c 以确保使用最新版本
    print_status "Copying svrskel_afl_coverage.c (覆盖模式)..."
    cp -f "$BASE_DIR/dockerfiles-libslmp2/svrskel_afl_coverage.c" samples/svrskel/
    
    # 手动添加 svrskel_afl_coverage 到 CMakeLists.txt（如果还没有）
    if ! grep -q "svrskel_afl_coverage" samples/svrskel/CMakeLists.txt 2>/dev/null; then
        print_status "Adding svrskel_afl_coverage to CMakeLists.txt..."
        
        # 在 sources 行添加 svrskel_afl_coverage.c
        sed -i 's/set(sources svrskel\.c svrskel_afl\.c)/set(sources svrskel.c svrskel_afl.c svrskel_afl_coverage.c)/' samples/svrskel/CMakeLists.txt
        
        # 在 svrskel_afl 后添加 svrskel_afl_coverage 的构建规则
        if ! grep -q "add_executable(svrskel_afl_coverage" samples/svrskel/CMakeLists.txt; then
            sed -i '/add_executable(svrskel_afl svrskel_afl\.c)/a\\nadd_executable(svrskel_afl_coverage svrskel_afl_coverage.c)' samples/svrskel/CMakeLists.txt
        fi
        
        # 在 svrskel_afl 链接库后添加 svrskel_afl_coverage 的链接规则
        if ! grep -q "target_link_libraries(svrskel_afl_coverage" samples/svrskel/CMakeLists.txt; then
            sed -i '/target_link_libraries(svrskel_afl PRIVATE slmp)/a\\ntarget_link_libraries(svrskel_afl_coverage PRIVATE slmp)' samples/svrskel/CMakeLists.txt
        fi
        
        print_status "svrskel_afl_coverage added to CMakeLists.txt"
    else
        print_status "svrskel_afl_coverage already in CMakeLists.txt, skipping..."
    fi
    
    mkdir -p build-coverage
    cd build-coverage
    
    cmake -DCMAKE_C_COMPILER=gcc \
          -DCMAKE_CXX_COMPILER=g++ \
          -DCMAKE_C_FLAGS="$CFLAGS" \
          -DCMAKE_CXX_FLAGS="$CXXFLAGS" \
          -DCMAKE_EXE_LINKER_FLAGS="$LDFLAGS" \
          -DCMAKE_BUILD_TYPE=Debug \
          ..
    make -j$(nproc) svrskel_afl_coverage
    cd ..
    
    # Check if .gcno files were created during build
    print_status "Checking for .gcno files after build..."
    GCNO_COUNT=$(find build-coverage -name "*.gcno" 2>/dev/null | wc -l)
    GCNO_COUNT_ALL=$(find . -name "*.gcno" 2>/dev/null | wc -l)
    print_status "Found $GCNO_COUNT .gcno files in build-coverage directory"
    print_status "Found $GCNO_COUNT_ALL .gcno files total in libslmp2"
    
    if [ "$GCNO_COUNT" -eq 0 ] && [ "$GCNO_COUNT_ALL" -eq 0 ]; then
        print_warning "No .gcno files found. Coverage instrumentation may have failed."
    else
        print_status "Coverage instrumentation successful: .gcno files generated at compile time"
    fi
    
    print_status "libslmp2 rebuilt with coverage instrumentation"
}

# Check if coverage server is running
is_coverage_server_running() {
    local pid=""
    
    # libslmp2 使用 svrskel_afl_coverage
    pid=$(pgrep -f "svrskel_afl_coverage.*$SERVER_PORT" 2>/dev/null)
    
    if [ ! -z "$pid" ]; then
        SERVER_PID=$pid
        return 0
    else
        return 1
    fi
}

# Start coverage-enabled server with monitoring
start_coverage_server() {
    print_status "Starting coverage-enabled SLMP server with monitoring..."
    
    # Kill any existing servers more aggressively
    pkill -9 -f "svrskel_afl_coverage" 2>/dev/null || true
    pkill -9 -f "svrskel_afl" 2>/dev/null || true
    
    # Force release the port using fuser
    fuser -k $SERVER_PORT/tcp 2>/dev/null || true
    sleep 2
    
    # Double check and wait for port to be released
    wait_count=0
    while ss -tuln 2>/dev/null | grep -q ":$SERVER_PORT " && [ $wait_count -lt 10 ]; do
        print_status "Waiting for port $SERVER_PORT to be released..."
        fuser -k $SERVER_PORT/tcp 2>/dev/null || true
        sleep 1
        wait_count=$((wait_count + 1))
    done
    
    # Start the coverage-enabled server
    cd "$SLMP_DIR/build-coverage"
    
    if [ ! -f "./samples/svrskel/svrskel_afl_coverage" ]; then
        print_error "svrskel_afl_coverage binary not found. Please run rebuild first."
        exit 1
    fi
    
    # Start server with correct working directory for .gcda files
    ./samples/svrskel/svrskel_afl_coverage $SERVER_PORT &
    SERVER_PID=$!
    
    # Wait for server to start
    sleep 3
    
    # Verify server is running
    if is_coverage_server_running; then
        print_status "Coverage-enabled server started with PID: $SERVER_PID"
        COVERAGE_SERVER_RUNNING=true
        SERVER_RESTART_COUNT=0
    else
        print_error "Failed to start coverage-enabled server"
        exit 1
    fi
}

# Monitor and restart coverage server if needed
monitor_coverage_server() {
    print_status "Starting server monitoring (checking every ${SERVER_CHECK_INTERVAL}s)..."
    
    while [ "$COVERAGE_SERVER_RUNNING" = true ]; do
        if ! is_coverage_server_running; then
            print_warning "Coverage server is not running. Attempting restart..."
            
            SERVER_RESTART_COUNT=$((SERVER_RESTART_COUNT + 1))
            
            if [ $SERVER_RESTART_COUNT -le $MAX_SERVER_RESTART_ATTEMPTS ]; then
                print_status "Restart attempt $SERVER_RESTART_COUNT of $MAX_SERVER_RESTART_ATTEMPTS"
                
                # 强制清理可能残留的服务器进程
                pkill -9 -f "svrskel_afl_coverage" 2>/dev/null || true
                pkill -9 -f "svrskel_afl" 2>/dev/null || true
                
                # 使用 fuser 强制释放端口
                fuser -k $SERVER_PORT/tcp 2>/dev/null || true
                sleep 2
                
                # 确保端口已释放
                port_wait=0
                while ss -tuln 2>/dev/null | grep -q ":$SERVER_PORT " && [ $port_wait -lt 10 ]; do
                    print_status "Waiting for port $SERVER_PORT to be released... ($port_wait/10)"
                    fuser -k -9 $SERVER_PORT/tcp 2>/dev/null || true
                    sleep 1
                    port_wait=$((port_wait + 1))
                done
                
                cd "$SLMP_DIR/build-coverage"
                ./samples/svrskel/svrskel_afl_coverage $SERVER_PORT &
                SERVER_PID=$!
                
                # 等待服务器启动（增加等待时间）
                sleep 3
                
                if is_coverage_server_running; then
                    print_status "Coverage server restarted successfully with PID: $SERVER_PID"
                else
                    print_error "Failed to restart coverage server (attempt $SERVER_RESTART_COUNT)"
                    # 显示可能的错误信息
                    print_error "Port $SERVER_PORT may still be in use or server binary has issues"
                fi
            else
                print_error "Maximum restart attempts ($MAX_SERVER_RESTART_ATTEMPTS) reached. Stopping monitoring."
                COVERAGE_SERVER_RUNNING=false
                break
            fi
        else
            # Server is running, reset restart count
            if [ $SERVER_RESTART_COUNT -gt 0 ]; then
                SERVER_RESTART_COUNT=0
                print_status "Server stability restored"
            fi
        fi
        
        sleep $SERVER_CHECK_INTERVAL
    done
}

# Start server monitoring in background
start_server_monitoring() {
    print_status "Starting background server monitoring..."
    monitor_coverage_server &
    MONITOR_PID=$!
    print_status "Server monitoring started with PID: $MONITOR_PID"
}

# Stop server monitoring
stop_server_monitoring() {
    if [ ! -z "$MONITOR_PID" ]; then
        print_status "Stopping server monitoring..."
        kill $MONITOR_PID 2>/dev/null || true
        wait $MONITOR_PID 2>/dev/null || true
    fi
    COVERAGE_SERVER_RUNNING=false
}

# Run test case replay with server monitoring
run_replay_with_monitoring() {
    print_status "Running test case replay with server monitoring..."
    
    # Start server monitoring in background
    start_server_monitoring
    
    # Make sure replay script is executable
    chmod +x "$REPLAY_SCRIPT"
    
    # Run the replay script with parameters
    print_status "Starting test case replay..."
    "$REPLAY_SCRIPT" "$FUZZER" "$RUN_NUM"
    
    # Stop server monitoring
    stop_server_monitoring
    
    print_status "Test case replay completed"
    
    # Check if .gcda files were generated during execution (runtime coverage data)
    print_status "Checking for .gcda files after server execution..."
    GCDA_COUNT=$(find "$SLMP_DIR" -name "*.gcda" 2>/dev/null | wc -l)
    GCDA_COUNT_BUILD=$(find "$SLMP_DIR/build-coverage" -name "*.gcda" 2>/dev/null | wc -l)
    print_status "Found $GCDA_COUNT .gcda files total in libslmp2"
    print_status "Found $GCDA_COUNT_BUILD .gcda files in build-coverage directory"
    
    if [ "$GCDA_COUNT" -eq 0 ]; then
        print_warning "No .gcda files found. The coverage-enabled server may not have executed properly or no code was covered."
        print_status "This means either:"
        print_status "  1. The server didn't run successfully"
        print_status "  2. No test cases were executed"
        print_status "  3. The executed code paths didn't trigger coverage data generation"
    else
        print_status "Runtime coverage data generated successfully: .gcda files created during execution"
    fi
}

# Generate coverage reports
generate_coverage_reports() {
    print_status "Generating coverage reports..."
    
    # Create coverage reports directory
    mkdir -p "$COVERAGE_DIR"
    
    # Find coverage data files - CMake 构建：覆盖率文件在 build-coverage 中
    cd "$SLMP_DIR"
    
    print_status "Searching for coverage files in CMake build directory..."
    GCNO_FILES=$(find "$SLMP_DIR/build-coverage" -name "*.gcno" 2>/dev/null | wc -l)
    GCDA_FILES=$(find "$SLMP_DIR/build-coverage" -name "*.gcda" 2>/dev/null | wc -l)
    
    print_status "Found $GCNO_FILES .gcno files in build-coverage (compile-time coverage data)"
    print_status "Found $GCDA_FILES .gcda files in build-coverage (runtime coverage data)"
    
    if [ "$GCNO_FILES" -eq 0 ]; then
        print_error "No .gcno files found in build-coverage. Coverage instrumentation failed."
        return 1
    fi
    
    # 设置 gcovr 的根目录和对象目录
    GCOVR_ROOT="$SLMP_DIR"
    GCOVR_OBJECT_DIR="$SLMP_DIR/build-coverage"
    
    if [ "$GCDA_FILES" -eq 0 ]; then
        print_warning "No .gcda files found. The coverage-enabled server may not have executed or no code was covered."
        print_status "Coverage reports will show 0% coverage since no runtime data is available."
    fi
    
    print_status "Coverage files summary: $GCNO_FILES .gcno files, $GCDA_FILES .gcda files"
    print_status "GCOVR_ROOT: $GCOVR_ROOT"
    print_status "GCOVR_OBJECT_DIR: $GCOVR_OBJECT_DIR"
    
    # Generate line coverage report only (不带 --branches，只显示行覆盖率)
    LINE_COVERAGE_FILE="$COVERAGE_DIR/coverage-line-libslmp2-${FUZZER}-${RUN_NUM}.txt"
    print_status "Generating line coverage report (Lines/Exec/Cover only)..."
    
    if gcovr --root "$GCOVR_ROOT" \
          --object-directory "$GCOVR_OBJECT_DIR" \
          --txt \
          -o "$LINE_COVERAGE_FILE" \
          --print-summary 2>/dev/null; then
        print_status "Line coverage report generated: $LINE_COVERAGE_FILE"
    elif cd "$GCOVR_OBJECT_DIR" && gcovr --root "$GCOVR_ROOT" \
          --txt \
          -o "$LINE_COVERAGE_FILE" \
          --print-summary 2>/dev/null; then
        print_status "Line coverage report generated (from object directory)"
        cd "$SLMP_DIR"
    else
        print_error "Line coverage report generation failed"
    fi
    
    # Generate branch coverage report only (带 --branches，只显示分支覆盖率)
    BRANCH_COVERAGE_FILE="$COVERAGE_DIR/coverage-branch-libslmp2-${FUZZER}-${RUN_NUM}.txt"
    print_status "Generating branch coverage report (Branches/Taken/Cover only)..."
    
    if gcovr --root "$GCOVR_ROOT" \
          --object-directory "$GCOVR_OBJECT_DIR" \
          --txt --branches \
          -o "$BRANCH_COVERAGE_FILE" \
          --print-summary 2>/dev/null; then
        print_status "Branch coverage report generated: $BRANCH_COVERAGE_FILE"
    elif cd "$GCOVR_OBJECT_DIR" && gcovr --root "$GCOVR_ROOT" \
          --txt --branches \
          -o "$BRANCH_COVERAGE_FILE" \
          --print-summary 2>/dev/null; then
        print_status "Branch coverage report generated (from object directory)"
        cd "$SLMP_DIR"
    else
        print_error "Branch coverage report generation failed"
    fi
    
    print_status "Coverage reports generated in: $COVERAGE_DIR"
    
    # 清理 .gcda 文件，避免影响下次分析
    print_status "Cleaning .gcda files to prevent contamination of next analysis..."
    find "$SLMP_DIR" -name "*.gcda" -delete 2>/dev/null || true
    print_status ".gcda files cleaned"
}

# Display coverage summary
display_summary() {
    print_status "Coverage Analysis Summary:"
    echo "=========================="
    echo "Target: libslmp2 | Fuzzer: $FUZZER | Run: #$RUN_NUM"
    echo ""
    
    LINE_COVERAGE_FILE="$COVERAGE_DIR/coverage-line-libslmp2-${FUZZER}-${RUN_NUM}.txt"
    BRANCH_COVERAGE_FILE="$COVERAGE_DIR/coverage-branch-libslmp2-${FUZZER}-${RUN_NUM}.txt"
    
    if [ -f "$LINE_COVERAGE_FILE" ]; then
        echo "=== Line Coverage ==="
        tail -5 "$LINE_COVERAGE_FILE"
        echo ""
    fi
    
    if [ -f "$BRANCH_COVERAGE_FILE" ]; then
        echo "=== Branch Coverage ==="
        tail -5 "$BRANCH_COVERAGE_FILE"
        echo ""
    fi
    
    echo ""
    print_status "Available reports:"
    echo "  - Line Coverage:   $LINE_COVERAGE_FILE"
    echo "  - Branch Coverage: $BRANCH_COVERAGE_FILE"
    
    echo ""
    print_status "Server monitoring statistics:"
    echo "  - Server restart attempts: $SERVER_RESTART_COUNT"
    echo "  - Max restart attempts allowed: $MAX_SERVER_RESTART_ATTEMPTS"
}

# Cleanup function
cleanup() {
    print_status "Cleaning up..."
    
    # Stop server monitoring
    stop_server_monitoring
    
    # Kill the coverage server gracefully first (to ensure .gcda flush)
    if [ ! -z "$SERVER_PID" ]; then
        print_status "Sending SIGTERM to server (PID: $SERVER_PID) to flush coverage data..."
        kill -TERM $SERVER_PID 2>/dev/null || true
        
        # Wait for server to flush .gcda files
        for i in {1..5}; do
            if ! ps -p $SERVER_PID > /dev/null 2>&1; then
                print_status "Server exited gracefully"
                break
            fi
            sleep 1
        done
        
        # Force kill if still running
        if ps -p $SERVER_PID > /dev/null 2>&1; then
            print_warning "Server didn't exit, forcing termination..."
            kill -9 $SERVER_PID 2>/dev/null || true
        fi
    fi
    
    # Kill any remaining server processes gracefully, then forcefully
    pkill -TERM -f "svrskel_afl_coverage $SERVER_PORT" 2>/dev/null || true
    pkill -TERM -f "svrskel_afl $SERVER_PORT" 2>/dev/null || true
    sleep 1
    pkill -9 -f "svrskel_afl_coverage" 2>/dev/null || true
    pkill -9 -f "svrskel_afl" 2>/dev/null || true
    
    # Ensure port is released
    fuser -k -9 $SERVER_PORT/tcp 2>/dev/null || true
    
    # Kill monitor process if still running
    if [ ! -z "$MONITOR_PID" ]; then
        kill $MONITOR_PID 2>/dev/null || true
    fi
}

# Set trap for cleanup on exit
trap cleanup EXIT

# Main execution
main() {
    echo -e "${BLUE}Starting coverage analysis with server monitoring...${NC}"
    
    check_prerequisites
    rebuild_with_coverage
    start_coverage_server
    run_replay_with_monitoring
    
    # Stop the server before generating reports
    print_status "Stopping coverage-enabled server..."
    stop_server_monitoring
    
    # Gracefully stop server to ensure .gcda files are written
    if [ ! -z "$SERVER_PID" ]; then
        print_status "Sending SIGTERM to server (PID: $SERVER_PID) to flush coverage data..."
        kill -TERM $SERVER_PID 2>/dev/null || true
        
        # Wait for server to gracefully exit and write .gcda files
        for i in {1..10}; do
            if ! ps -p $SERVER_PID > /dev/null 2>&1; then
                print_status "Server exited gracefully, .gcda files should be written"
                break
            fi
            print_status "Waiting for server to flush coverage data... ($i/10)"
            sleep 1
        done
        
        # If still running, force terminate
        if ps -p $SERVER_PID > /dev/null 2>&1; then
            print_warning "Server didn't exit gracefully after 10 seconds, forcing termination..."
            kill -9 $SERVER_PID 2>/dev/null || true
        fi
    fi
    
    sleep 2
    
    generate_coverage_reports
    display_summary
    
    print_status "Coverage analysis completed successfully!"
}

# Parse command line arguments
case "${1:-}" in
    --help|-h)
        echo "Usage: $0 [fuzzer] [run_number] [OPTIONS]"
        echo ""
        echo "Parameters:"
        echo "  fuzzer      : afl-ics, aflnet, chatafl, a2, a3 (默认: aflnet)"
        echo "  run_number  : 实验次数 (默认: 1)"
        echo ""
        echo "Options:"
        echo "  --help, -h     Show this help message"
        echo "  --rebuild-only Rebuild with coverage only"
        echo "  --report-only  Generate reports from existing coverage data"
        echo "  --monitor-only Start coverage server with monitoring only"
        echo ""
        echo "Examples:"
        echo "  $0 aflnet 1        # 分析 libslmp2 的 aflnet 第1次实验结果"
        echo "  $0 chatafl 2       # 分析 libslmp2 的 chatafl 第2次实验结果"
        echo "  $0 a2 1            # 分析 libslmp2 的 a2 第1次实验结果"
        echo ""
        echo "This script performs comprehensive coverage analysis with server monitoring by:"
        echo "1. Rebuilding target with coverage instrumentation (CMake)"
        echo "2. Starting a coverage-enabled server with automatic restart monitoring"
        echo "3. Replaying test cases using replay-libslmp.sh"
        echo "4. Generating coverage reports using gcovr"
        echo ""
        echo "Server monitoring features:"
        echo "- Checks server status every $SERVER_CHECK_INTERVAL seconds"
        echo "- Automatically restarts server if it crashes"
        echo "- Maximum $MAX_SERVER_RESTART_ATTEMPTS restart attempts"
        exit 0
        ;;
    --rebuild-only)
        check_prerequisites
        rebuild_with_coverage
        print_status "Rebuild completed. Use '$0' to run full analysis."
        exit 0
        ;;
    --report-only)
        check_prerequisites
        generate_coverage_reports
        display_summary
        exit 0
        ;;
    --monitor-only)
        check_prerequisites
        if [ ! -f "$SLMP_DIR/build-coverage/samples/svrskel/svrskel_afl_coverage" ]; then
            print_error "Coverage server binary not found. Run '$0 --rebuild-only' first."
            exit 1
        fi
        start_coverage_server
        print_status "Coverage server started with monitoring. Press Ctrl+C to stop."
        monitor_coverage_server
        exit 0
        ;;
    "")
        # 没有参数，使用默认值运行
        main
        ;;
    *)
        # 第一个参数不是选项，当作 fuzzer 参数处理
        if [[ ! "$1" =~ ^-- ]]; then
            # 正常参数，运行主程序
            main
        else
            # 未知的选项
            print_error "Unknown option: $1"
            echo "Use '$0 --help' for usage information"
            exit 1
        fi
        ;;
esac

