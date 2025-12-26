#!/bin/bash

# Coverage Analysis Script for IEC104 Fuzzing
# This script uses gcovr to analyze code coverage after replaying test cases
# Includes server monitoring and automatic restart functionality
# 使用方法: ./coverage-iec104.sh [target] [fuzzer] [run_number]
# 示例: ./coverage-iec104.sh iec104 aflnet 1
#       ./coverage-iec104.sh freyrscada-iec104 afl-ics 1

set -e

# 参数解析（可选，默认为 iec104）
TARGET_IMPL="${1:-iec104}"     # iec104 或 freyrscada-iec104
FUZZER="${2:-aflnet}"          # afl-ics, aflnet, chatafl, a2, a3
RUN_NUM="${3:-1}"              # 实验次数

# Configuration - 根据目标调整（使用绝对路径）
BASE_DIR="/home/ecs-user/LLM_fuzz_experiment"

if [ "$TARGET_IMPL" = "freyrscada-iec104" ]; then
    IEC104_DIR="$BASE_DIR/freyrscada-iec104"
    OUTPUT_DIR="$BASE_DIR/results/freyrscada-iec104-${FUZZER}-${RUN_NUM}"
    COVERAGE_DIR="$BASE_DIR/coverage-reports"
    REPLAY_SCRIPT="$BASE_DIR/coverage-analysis/replay-iec104.sh"
    SERVER_PORT="2404"
else
    IEC104_DIR="$BASE_DIR/IEC104"
    OUTPUT_DIR="$BASE_DIR/results/iec104-${FUZZER}-${RUN_NUM}"
    COVERAGE_DIR="$BASE_DIR/coverage-reports"
    REPLAY_SCRIPT="$BASE_DIR/coverage-analysis/replay-iec104.sh"
    SERVER_PORT="2404"  # iec104 也使用 2404 端口
fi

SERVER_CHECK_INTERVAL=5  # Check server status every 5 seconds
MAX_SERVER_RESTART_ATTEMPTS=100  # 增加重启次数限制

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}=== IEC104 Coverage Analysis Tool ===${NC}"
echo -e "${BLUE}Target: $TARGET_IMPL | Fuzzer: $FUZZER | Run: #$RUN_NUM${NC}"

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
    
    if [ ! -d "$IEC104_DIR" ]; then
        print_error "IEC104 directory not found: $IEC104_DIR"
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
    print_status "Rebuilding $TARGET_IMPL with coverage instrumentation..."
    
    # Configure with coverage flags
    export CFLAGS="-fprofile-arcs -ftest-coverage -O0 -g"
    export CXXFLAGS="-fprofile-arcs -ftest-coverage -O0 -g"
    export LDFLAGS="-fprofile-arcs -ftest-coverage"
    
    if [ "$TARGET_IMPL" = "freyrscada-iec104" ]; then
        # FreyrSCADA IEC104 has different directory structure
        cd "$IEC104_DIR/IEC104-Linux-SDK/LinuxSDK/x86_64"
        
        # 彻底清理之前的覆盖率数据
        print_status "Cleaning previous coverage data..."
        find . -name "*.gcda" -delete 2>/dev/null || true
        find . -name "*.gcno" -delete 2>/dev/null || true
        
        # 检查是否需要应用patch（检查main函数签名）
        print_status "Checking if patch needs to be applied..."
        if ! grep -q "int main(int argc" source/simpleIEC104server.c 2>/dev/null; then
            print_status "Applying FreyrSCADA IEC104 fuzzing patch..."
            
            if [ -f "$BASE_DIR/dockerfiles-freyrscada-iec104/freyrscada-iec104-fuzzing.patch" ]; then
                # 先转换行尾
                sed -i 's/\r$//' source/simpleIEC104server.c project/iec104servertest.mak 2>/dev/null || true
                # 应用patch（使用--forward跳过已应用的部分）
                patch -p1 --forward < "$BASE_DIR/dockerfiles-freyrscada-iec104/freyrscada-iec104-fuzzing.patch" || true
                print_status "Patch processing completed"
            else
                print_error "Patch file not found"
                exit 1
            fi
        else
            print_status "Patch already applied, skipping..."
        fi
        
        # 修改Makefile添加覆盖率标志并使用gcc
        cd project
        print_status "Configuring Makefile with coverage flags..."
        print_warning "Note: FreyrSCADA uses precompiled library (libx86_x64-iec104.a) without source code."
        print_warning "Coverage will only be available for wrapper code, not core IEC104 protocol implementation."
        
        # 恢复使用gcc而不是afl-clang-fast
        sed -i 's/^CC = .*/CC = gcc/' iec104servertest.mak
        sed -i 's/^CXX = .*/CXX = g++/' iec104servertest.mak
        sed -i 's/^LD = .*/LD = g++/' iec104servertest.mak
        sed -i 's/^AR = .*/AR = ar/' iec104servertest.mak
        
        # 添加CFLAGS_RELEASE和LDFLAGS_RELEASE定义（Makefile中没有这些）
        sed -i '/^CFLAGS_RELEASE = /d' iec104servertest.mak 2>/dev/null || true
        sed -i '/^LDFLAGS_RELEASE = /d' iec104servertest.mak 2>/dev/null || true
        sed -i '/^INC_RELEASE = /a CFLAGS_RELEASE = -Wall -fprofile-arcs -ftest-coverage -O0 -g' iec104servertest.mak
        sed -i '/^RCFLAGS_RELEASE = /a LDFLAGS_RELEASE = -fprofile-arcs -ftest-coverage' iec104servertest.mak
        
        # Clean and rebuild
        print_status "Building with coverage instrumentation..."
        make -f iec104servertest.mak clean || true
        make -f iec104servertest.mak
        
    else
        # Original IEC104
        cd "$IEC104_DIR/test"
        
        # 彻底清理之前的覆盖率数据
        print_status "Cleaning previous coverage data..."
        make clean || true
        find . -name "*.gcda" -delete 2>/dev/null || true
        find . -name "*.gcno" -delete 2>/dev/null || true
        
        # 检查是否需要应用patch
        print_status "Checking if patch needs to be applied..."
        if ! grep -q "pthread_testcancel" main.c 2>/dev/null; then
            print_status "Applying IEC104 fuzzing patch..."
            
            if [ -f "$BASE_DIR/dockerfiles-iec104/iec104-fuzzing.patch" ]; then
                patch -p2 < "$BASE_DIR/dockerfiles-iec104/iec104-fuzzing.patch"
                print_status "Patch applied successfully"
            else
                print_error "Patch file not found"
                exit 1
            fi
        else
            print_status "Patch already applied, skipping..."
        fi
        
        # 修改Makefile来使用覆盖率标志
        print_status "Configuring with coverage flags: $CFLAGS"
        sed -i 's/^CC = .*/CC = gcc/' Makefile
        sed -i '/^CFLAGS +=/d' Makefile
        sed -i '/^LDFLAGS +=/d' Makefile
        echo "CFLAGS +=-I\$(MODULE_PATH) -I. -lpthread" >> Makefile
        echo "CFLAGS +=-Wno-return-type -fprofile-arcs -ftest-coverage -O0 -g" >> Makefile
        echo "LDFLAGS +=-fprofile-arcs -ftest-coverage" >> Makefile
        
        # Clean and rebuild
        make clean
        
        # Force rebuild with coverage flags
        print_status "Building with coverage instrumentation..."
        make all V=1
    fi
    
    # Check if .gcno files were created during build
    print_status "Checking for .gcno files after build..."
    GCNO_COUNT=$(find . -name "*.gcno" 2>/dev/null | wc -l)
    print_status "Found $GCNO_COUNT .gcno files in test directory"
    
    if [ "$GCNO_COUNT" -eq 0 ]; then
        print_warning "No .gcno files found. Coverage instrumentation may have failed."
    else
        print_status "Coverage instrumentation successful: .gcno files generated at compile time"
    fi
    
    print_status "$TARGET_IMPL rebuilt with coverage instrumentation"
}

# Check if coverage server is running
is_coverage_server_running() {
    local pid=""
    
    if [ "$TARGET_IMPL" = "freyrscada-iec104" ]; then
        # FreyrSCADA 使用 iec104servertest
        pid=$(pgrep -f "iec104servertest.*$SERVER_PORT" 2>/dev/null)
    else
        # 原始IEC104 使用 iec104_monitor
        pid=$(pgrep -f "iec104_monitor.*$SERVER_PORT" 2>/dev/null)
    fi
    
    if [ ! -z "$pid" ]; then
        SERVER_PID=$pid
        return 0
    else
        return 1
    fi
}

# Start coverage-enabled server with monitoring
start_coverage_server() {
    print_status "Starting coverage-enabled $TARGET_IMPL server with monitoring..."
    
    if [ "$TARGET_IMPL" = "freyrscada-iec104" ]; then
        # FreyrSCADA IEC104
        # Kill any existing servers
        pkill -f "iec104servertest $SERVER_PORT" || true
        pkill -f "\./iec104servertest" || true
        sleep 2
        
        # Start the server
        cd "$IEC104_DIR/IEC104-Linux-SDK/LinuxSDK/x86_64/output"
        
        if [ ! -f "./iec104servertest" ]; then
            print_error "iec104servertest binary not found. Please run rebuild first."
            exit 1
        fi
        
        # 设置GCOV环境变量，让.gcda文件生成在intermediate目录
        export GCOV_PREFIX="../intermediate"
        export GCOV_PREFIX_STRIP=99
        
        ./iec104servertest $SERVER_PORT &
        SERVER_PID=$!
    else
        # Original IEC104
        # Kill any existing servers
        pkill -f "iec104_monitor $SERVER_PORT" || true
        pkill -f "\./iec104_monitor" || true
        sleep 2
        
        # Start the server
        cd "$IEC104_DIR/test"
        
        if [ ! -f "./iec104_monitor" ]; then
            print_error "iec104_monitor binary not found. Please run rebuild first."
            exit 1
        fi
        
        ./iec104_monitor $SERVER_PORT &
        SERVER_PID=$!
    fi
    
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
                if [ "$TARGET_IMPL" = "freyrscada-iec104" ]; then
                    pkill -9 -f "iec104servertest $SERVER_PORT" 2>/dev/null || true
                else
                    pkill -9 -f "iec104_monitor $SERVER_PORT" 2>/dev/null || true
                fi
                
                # 等待端口释放
                sleep 2
                
                # 重启服务器
                if [ "$TARGET_IMPL" = "freyrscada-iec104" ]; then
                    cd "$IEC104_DIR/IEC104-Linux-SDK/LinuxSDK/x86_64/output"
                    export GCOV_PREFIX="../intermediate"
                    export GCOV_PREFIX_STRIP=99
                    ./iec104servertest $SERVER_PORT &
                else
                    cd "$IEC104_DIR/test"
                    ./iec104_monitor $SERVER_PORT &
                fi
                SERVER_PID=$!
                
                # 等待服务器启动（增加等待时间）
                sleep 3
                
                if is_coverage_server_running; then
                    print_status "Coverage server restarted successfully with PID: $SERVER_PID"
                else
                    print_error "Failed to restart coverage server (attempt $SERVER_RESTART_COUNT)"
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
    "$REPLAY_SCRIPT" "$TARGET_IMPL" "$FUZZER" "$RUN_NUM"
    
    # Stop server monitoring
    stop_server_monitoring
    
    print_status "Test case replay completed"
    
    # Check if .gcda files were generated during execution (runtime coverage data)
    print_status "Checking for .gcda files after server execution..."
    
    # 等待一下确保.gcda文件写入完成
    sleep 2
    
    GCDA_COUNT=$(find "$IEC104_DIR" -name "*.gcda" 2>/dev/null | wc -l)
    
    if [ "$TARGET_IMPL" = "freyrscada-iec104" ]; then
        GCDA_COUNT_BUILD=$(find "$IEC104_DIR/IEC104-Linux-SDK/LinuxSDK/x86_64" -name "*.gcda" 2>/dev/null | wc -l)
        print_status "Found $GCDA_COUNT .gcda files total"
        print_status "Found $GCDA_COUNT_BUILD .gcda files in build directory"
        
        # 列出找到的.gcda文件
        if [ "$GCDA_COUNT_BUILD" -gt 0 ]; then
            print_status ".gcda files found:"
            find "$IEC104_DIR/IEC104-Linux-SDK/LinuxSDK/x86_64" -name "*.gcda" 2>/dev/null | while read f; do
                print_status "  - $f"
            done
        fi
    else
        GCDA_COUNT_TEST=$(find "$IEC104_DIR/test" -name "*.gcda" 2>/dev/null | wc -l)
        print_status "Found $GCDA_COUNT .gcda files total in IEC104"
        print_status "Found $GCDA_COUNT_TEST .gcda files in test directory"
    fi
    
    if [ "$GCDA_COUNT" -eq 0 ]; then
        print_warning "No .gcda files found. The coverage-enabled server may not have executed properly or no code was covered."
        print_status "This means either:"
        print_status "  1. The server didn't run successfully"
        print_status "  2. No test cases were executed"
        print_status "  3. The executed code paths didn't trigger coverage data generation"
        print_status "  4. The server was killed before .gcda files could be written"
    else
        print_status "Runtime coverage data generated successfully: .gcda files created during execution"
    fi
}

# Generate coverage reports
generate_coverage_reports() {
    print_status "Generating coverage reports..."
    
    # Create coverage reports directory
    mkdir -p "$COVERAGE_DIR"
    
    # Find coverage data files
    cd "$IEC104_DIR"
    
    print_status "Searching for coverage files..."
    if [ "$TARGET_IMPL" = "freyrscada-iec104" ]; then
        # FreyrSCADA的文件在intermediate和output目录
        SEARCH_DIR="$IEC104_DIR/IEC104-Linux-SDK/LinuxSDK/x86_64"
        GCOVR_ROOT="$IEC104_DIR"
        GCOVR_OBJECT_DIR="$SEARCH_DIR"
    else
        # 原始IEC104的文件在test目录
        SEARCH_DIR="$IEC104_DIR/test"
        GCOVR_ROOT="$IEC104_DIR"
        GCOVR_OBJECT_DIR="$IEC104_DIR/test"
    fi
    
    GCNO_FILES=$(find "$SEARCH_DIR" -name "*.gcno" 2>/dev/null | wc -l)
    GCDA_FILES=$(find "$SEARCH_DIR" -name "*.gcda" 2>/dev/null | wc -l)
    
    print_status "Found $GCNO_FILES .gcno files (compile-time coverage data)"
    print_status "Found $GCDA_FILES .gcda files (runtime coverage data)"
    
    if [ "$GCNO_FILES" -eq 0 ]; then
        print_error "No .gcno files found. Coverage instrumentation failed."
        return 1
    fi
    
    if [ "$GCDA_FILES" -eq 0 ]; then
        print_warning "No .gcda files found. The coverage-enabled server may not have executed or no code was covered."
        print_status "Coverage reports will show 0% coverage since no runtime data is available."
    fi
    
    print_status "Coverage files summary: $GCNO_FILES .gcno files, $GCDA_FILES .gcda files"
    print_status "GCOVR_ROOT: $GCOVR_ROOT"
    print_status "GCOVR_OBJECT_DIR: $GCOVR_OBJECT_DIR"
    
    # Generate line coverage report only (不带 --branches，只显示行覆盖率)
    LINE_COVERAGE_FILE="$COVERAGE_DIR/coverage-line-${TARGET_IMPL}-${FUZZER}-${RUN_NUM}.txt"
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
        cd "$IEC104_DIR"
    else
        print_error "Line coverage report generation failed"
    fi
    
    # Generate branch coverage report only (带 --branches，只显示分支覆盖率)
    BRANCH_COVERAGE_FILE="$COVERAGE_DIR/coverage-branch-${TARGET_IMPL}-${FUZZER}-${RUN_NUM}.txt"
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
        cd "$IEC104_DIR"
    else
        print_error "Branch coverage report generation failed"
    fi
    
    print_status "Coverage reports generated in: $COVERAGE_DIR"
    
    # 清理 .gcda 文件，避免影响下次分析
    print_status "Cleaning .gcda files to prevent contamination of next analysis..."
    find "$IEC104_DIR" -name "*.gcda" -delete 2>/dev/null || true
    print_status ".gcda files cleaned"
}

# Display coverage summary
display_summary() {
    print_status "Coverage Analysis Summary:"
    echo "=========================="
    echo "Target: $TARGET_IMPL | Fuzzer: $FUZZER | Run: #$RUN_NUM"
    echo ""
    
    LINE_COVERAGE_FILE="$COVERAGE_DIR/coverage-line-${TARGET_IMPL}-${FUZZER}-${RUN_NUM}.txt"
    BRANCH_COVERAGE_FILE="$COVERAGE_DIR/coverage-branch-${TARGET_IMPL}-${FUZZER}-${RUN_NUM}.txt"
    
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
    
    # Kill the coverage server gracefully first
    if [ ! -z "$SERVER_PID" ]; then
        # 使用SIGTERM让程序正常退出以写入.gcda
        kill -TERM $SERVER_PID 2>/dev/null || true
        sleep 3
        # 如果还在运行才强制终止
        if ps -p $SERVER_PID > /dev/null 2>&1; then
            kill -9 $SERVER_PID 2>/dev/null || true
        fi
    fi
    
    # Kill any remaining server processes (gracefully)
    if [ "$TARGET_IMPL" = "freyrscada-iec104" ]; then
        pkill -TERM -f "iec104servertest $SERVER_PORT" 2>/dev/null || true
        sleep 2
        pkill -9 -f "iec104servertest $SERVER_PORT" 2>/dev/null || true
    else
        pkill -TERM -f "iec104_monitor $SERVER_PORT" 2>/dev/null || true
        sleep 2
        pkill -9 -f "iec104_monitor $SERVER_PORT" 2>/dev/null || true
    fi
    
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
    
    # 优雅地停止服务器以确保.gcda文件被写入
    if [ ! -z "$SERVER_PID" ]; then
        print_status "Sending SIGTERM to server (PID: $SERVER_PID)..."
        kill -TERM $SERVER_PID 2>/dev/null || true
        
        # 等待服务器正常退出
        for i in {1..10}; do
            if ! ps -p $SERVER_PID > /dev/null 2>&1; then
                print_status "Server exited gracefully"
                break
            fi
            sleep 1
        done
        
        # 如果还在运行，强制终止
        if ps -p $SERVER_PID > /dev/null 2>&1; then
            print_warning "Server didn't exit gracefully, forcing termination..."
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
        echo "Usage: $0 [target] [fuzzer] [run_number] [OPTIONS]"
        echo ""
        echo "Parameters:"
        echo "  target      : iec104 或 freyrscada-iec104 (默认: iec104)"
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
        echo "  $0 iec104 aflnet 1              # 分析 iec104 的 aflnet 结果"
        echo "  $0 freyrscada-iec104 afl-ics 1  # 分析 freyrscada-iec104 的 afl-ics 结果"
        echo "  $0 iec104 a2 2                  # 分析 iec104 第2次实验"
        echo ""
        echo "Supported targets:"
        echo "  - iec104:            Original lib60870 IEC104 implementation"
        echo "  - freyrscada-iec104: FreyrSCADA IEC104 implementation"
        echo ""
        echo "This script performs comprehensive coverage analysis with server monitoring by:"
        echo "1. Rebuilding the target implementation with coverage instrumentation"
        echo "2. Starting a coverage-enabled server with automatic restart monitoring"
        echo "3. Replaying test cases using replay-iec104.sh"
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
        if [ "$TARGET_IMPL" = "freyrscada-iec104" ]; then
            SERVER_EXEC="$IEC104_DIR/IEC104-Linux-SDK/LinuxSDK/x86_64/output/iec104servertest"
        else
            SERVER_EXEC="$IEC104_DIR/test/iec104_monitor"
        fi
        
        if [ ! -f "$SERVER_EXEC" ]; then
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
        # 第一个参数不是选项，当作目标参数处理
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

