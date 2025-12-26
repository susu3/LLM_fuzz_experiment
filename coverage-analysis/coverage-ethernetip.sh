#!/bin/bash

# Coverage Analysis Script for EtherNet/IP Fuzzing
# This script uses gcovr to analyze code coverage after replaying test cases
# Includes server monitoring and automatic restart functionality
# 使用方法: ./coverage-ethernetip.sh [target] [fuzzer] [run_number]
# 示例: ./coverage-ethernetip.sh opener aflnet 1
#       ./coverage-ethernetip.sh eipscanner afl-ics 1

set -e

# 参数解析（可选，默认为 opener）
TARGET_IMPL="${1:-opener}"     # opener 或 eipscanner
FUZZER="${2:-aflnet}"          # afl-ics, aflnet, chatafl, a2, a3
RUN_NUM="${3:-1}"              # 实验次数

# Configuration - 根据目标调整（使用绝对路径）
BASE_DIR="/home/ecs-user/LLM_fuzz_experiment"

if [ "$TARGET_IMPL" = "eipscanner" ]; then
    ETHERNETIP_DIR="$BASE_DIR/eipscanner"
    OUTPUT_DIR="$BASE_DIR/results/eipscanner-${FUZZER}-${RUN_NUM}"
    COVERAGE_DIR="$BASE_DIR/coverage-reports"
    REPLAY_SCRIPT="$BASE_DIR/coverage-analysis/replay-ethernetip.sh"
    SERVER_PORT="44818"
    SERVER_BINARY="eip_server_harness"
    SERVER_PATH="build/examples"
    SERVER_ARGS="$SERVER_PORT"
    BUILD_TYPE="cmake"
else
    ETHERNETIP_DIR="$BASE_DIR/OpENer"
    OUTPUT_DIR="$BASE_DIR/results/opener-${FUZZER}-${RUN_NUM}"
    COVERAGE_DIR="$BASE_DIR/coverage-reports"
    REPLAY_SCRIPT="$BASE_DIR/coverage-analysis/replay-ethernetip.sh"
    SERVER_PORT="44818"
    SERVER_BINARY="OpENer"
    SERVER_PATH="build-server/src/ports/POSIX"
    SERVER_ARGS="lo"  # OpENer需要网络接口参数
    BUILD_TYPE="cmake"
fi

SERVER_CHECK_INTERVAL=5  # Check server status every 5 seconds
MAX_SERVER_RESTART_ATTEMPTS=100  # 增加重启次数限制

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}=== EtherNet/IP Coverage Analysis Tool ===${NC}"
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
    
    if [ ! -d "$ETHERNETIP_DIR" ]; then
        print_error "EtherNet/IP directory not found: $ETHERNETIP_DIR"
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
    
    cd "$ETHERNETIP_DIR"
    
    # Configure with coverage flags
    export CFLAGS="-fprofile-arcs -ftest-coverage -O0 -g"
    export CXXFLAGS="-fprofile-arcs -ftest-coverage -O0 -g"
    export LDFLAGS="-fprofile-arcs -ftest-coverage"
    
    # 彻底清理之前的覆盖率数据
    print_status "Cleaning previous coverage data..."
    find . -name "*.gcda" -delete 2>/dev/null || true
    find . -name "*.gcno" -delete 2>/dev/null || true
    
    if [ "$TARGET_IMPL" = "eipscanner" ]; then
        # EIPScanner uses CMake
        print_status "Rebuilding EIPScanner with coverage..."
        
        # 复制harness文件（如果不存在）
        if [ ! -f "examples/EIPServerHarness.cpp" ] && [ -f "$BASE_DIR/dockerfiles-eipscanner/EIPServerHarness.cpp" ]; then
            print_status "Copying EIPServerHarness.cpp..."
            cp "$BASE_DIR/dockerfiles-eipscanner/EIPServerHarness.cpp" examples/
        fi
        
        # 检查是否需要应用patch
        if [ -f "$BASE_DIR/dockerfiles-eipscanner/eipscanner-cmake.patch" ]; then
            if ! grep -q "eip_server_harness" examples/CMakeLists.txt 2>/dev/null; then
                print_status "Applying EIPScanner patch..."
                patch -p1 < "$BASE_DIR/dockerfiles-eipscanner/eipscanner-cmake.patch" || true
            fi
        fi
        
        rm -rf build
        mkdir -p build
        cd build
        cmake -DEXAMPLE_ENABLED=ON \
              -DCMAKE_C_FLAGS="$CFLAGS" \
              -DCMAKE_CXX_FLAGS="$CXXFLAGS" \
              -DCMAKE_EXE_LINKER_FLAGS="$LDFLAGS" \
              -DCMAKE_BUILD_TYPE=Debug \
              ..
        make -j$(nproc) eip_server_harness
    else
        # OpENer uses CMake, source code in 'source' subdirectory
        print_status "Rebuilding OpENer with coverage..."
        
        # 应用fuzzing patch
        if [ -f "$BASE_DIR/dockerfiles-opener/opener-fuzzing-fix.patch" ]; then
            if ! grep -q "OpENer.*Fuzzing" source/src/ports/POSIX/CMakeLists.txt 2>/dev/null; then
                print_status "Applying OpENer fuzzing patch..."
                cd source
                patch -p1 < "$BASE_DIR/dockerfiles-opener/opener-fuzzing-fix.patch" || true
                cd ..
            fi
        fi
        
        # 应用coverage patch（添加SIGTERM处理和__gcov_flush）
        if [ -f "$BASE_DIR/dockerfiles-opener/opener-coverage-fix.patch" ]; then
            if ! grep -q "__gcov_flush" source/src/ports/POSIX/main.c 2>/dev/null; then
                print_status "Applying OpENer coverage patch (adds SIGTERM handler with __gcov_flush)..."
                patch -p1 < "$BASE_DIR/dockerfiles-opener/opener-coverage-fix.patch"
                print_status "Coverage patch applied successfully"
            else
                print_status "Coverage patch already applied, skipping..."
            fi
        else
            print_warning "Coverage patch not found. OpENer may not flush .gcda files properly."
        fi
        
        rm -rf build-server
        mkdir -p build-server
        cd build-server
        cmake -DCMAKE_C_FLAGS="$CFLAGS" \
              -DCMAKE_CXX_FLAGS="$CXXFLAGS" \
              -DCMAKE_EXE_LINKER_FLAGS="$LDFLAGS" \
              -DCMAKE_BUILD_TYPE=Debug \
              -DOpENer_PLATFORM:STRING=POSIX \
              ../source
        make -j$(nproc)
    fi
    
    # Check if .gcno files were created during build
    print_status "Checking for .gcno files after build..."
    GCNO_COUNT=$(find "$ETHERNETIP_DIR" -name "*.gcno" 2>/dev/null | wc -l)
    print_status "Found $GCNO_COUNT .gcno files"
    
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
    
    if [ "$TARGET_IMPL" = "opener" ]; then
        # OpENer使用"lo"参数，不包含端口
        pid=$(pgrep -f "$SERVER_BINARY.*lo" 2>/dev/null | head -1)
    else
        # EIPScanner使用端口参数
        pid=$(pgrep -f "$SERVER_BINARY.*$SERVER_PORT" 2>/dev/null | head -1)
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
    
    # Kill any existing servers
    pkill -f "$SERVER_BINARY $SERVER_PORT" || true
    pkill -f "\\./$SERVER_BINARY" || true
    sleep 2
    
    # Start the coverage-enabled server
    cd "$ETHERNETIP_DIR/$SERVER_PATH"
    
    if [ ! -f "./$SERVER_BINARY" ]; then
        print_error "$SERVER_BINARY binary not found. Please run rebuild first."
        exit 1
    fi
    
    ./$SERVER_BINARY $SERVER_ARGS &
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
                pkill -9 -f "$SERVER_BINARY $SERVER_PORT" 2>/dev/null || true
                
                # 等待端口释放
                sleep 2
                
                cd "$ETHERNETIP_DIR/$SERVER_PATH"
                if [ "$TARGET_IMPL" = "opener" ]; then
                    ./$SERVER_BINARY lo &
                else
                    ./$SERVER_BINARY $SERVER_PORT &
                fi
                SERVER_PID=$!
                
                # 等待服务器启动
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
    
    # Check if .gcda files were generated during execution
    print_status "Checking for .gcda files after server execution..."
    GCDA_COUNT=$(find "$ETHERNETIP_DIR" -name "*.gcda" 2>/dev/null | wc -l)
    print_status "Found $GCDA_COUNT .gcda files total"
    
    if [ "$GCDA_COUNT" -eq 0 ]; then
        print_warning "No .gcda files found. The coverage-enabled server may not have executed properly or no code was covered."
    else
        print_status "Runtime coverage data generated successfully"
    fi
}

# Generate coverage reports
generate_coverage_reports() {
    print_status "Generating coverage reports..."
    
    # Create coverage reports directory
    mkdir -p "$COVERAGE_DIR"
    
    # Find coverage data files
    cd "$ETHERNETIP_DIR"
    
    print_status "Searching for coverage files..."
    GCNO_FILES=$(find "$ETHERNETIP_DIR" -name "*.gcno" 2>/dev/null | wc -l)
    GCDA_FILES=$(find "$ETHERNETIP_DIR" -name "*.gcda" 2>/dev/null | wc -l)
    
    print_status "Found $GCNO_FILES .gcno files (compile-time coverage data)"
    print_status "Found $GCDA_FILES .gcda files (runtime coverage data)"
    
    if [ "$GCNO_FILES" -eq 0 ]; then
        print_error "No .gcno files found. Coverage instrumentation failed."
        return 1
    fi
    
    GCOVR_ROOT="$ETHERNETIP_DIR"
    
    if [ "$GCDA_FILES" -eq 0 ]; then
        print_warning "No .gcda files found. The coverage-enabled server may not have executed or no code was covered."
        print_status "Coverage reports will show 0% coverage since no runtime data is available."
    fi
    
    # Generate line coverage report
    LINE_COVERAGE_FILE="$COVERAGE_DIR/coverage-line-${TARGET_IMPL}-${FUZZER}-${RUN_NUM}.txt"
    print_status "Generating line coverage report..."
    
    if gcovr --root "$GCOVR_ROOT" \
          --txt \
          -o "$LINE_COVERAGE_FILE" \
          --print-summary 2>/dev/null; then
        print_status "Line coverage report generated: $LINE_COVERAGE_FILE"
    else
        print_error "Line coverage report generation failed"
    fi
    
    # Generate branch coverage report
    BRANCH_COVERAGE_FILE="$COVERAGE_DIR/coverage-branch-${TARGET_IMPL}-${FUZZER}-${RUN_NUM}.txt"
    print_status "Generating branch coverage report..."
    
    if gcovr --root "$GCOVR_ROOT" \
          --txt --branches \
          -o "$BRANCH_COVERAGE_FILE" \
          --print-summary 2>/dev/null; then
        print_status "Branch coverage report generated: $BRANCH_COVERAGE_FILE"
    else
        print_error "Branch coverage report generation failed"
    fi
    
    print_status "Coverage reports generated in: $COVERAGE_DIR"
    
    # 清理 .gcda 文件
    print_status "Cleaning .gcda files to prevent contamination of next analysis..."
    find "$ETHERNETIP_DIR" -name "*.gcda" -delete 2>/dev/null || true
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
    
    # Kill the coverage server
    if [ ! -z "$SERVER_PID" ]; then
        kill $SERVER_PID 2>/dev/null || true
    fi
    
    # Kill any remaining server processes
    pkill -f "$SERVER_BINARY $SERVER_PORT" || true
    pkill -f "\\./$SERVER_BINARY" || true
    
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
    kill $SERVER_PID 2>/dev/null || true
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
        echo "  target      : opener 或 eipscanner (默认: opener)"
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
        echo "  $0 opener aflnet 1        # 分析 OpENer 的 aflnet 结果"
        echo "  $0 eipscanner afl-ics 1   # 分析 EIPScanner 的 afl-ics 结果"
        echo "  $0 opener a2 2            # 分析 OpENer 第2次实验"
        echo ""
        echo "Supported targets:"
        echo "  - opener:     OpENer EtherNet/IP implementation"
        echo "  - eipscanner: EIPScanner EtherNet/IP implementation"
        echo ""
        echo "This script performs comprehensive coverage analysis with server monitoring by:"
        echo "1. Rebuilding the target implementation with coverage instrumentation"
        echo "2. Starting a coverage-enabled server with automatic restart monitoring"
        echo "3. Replaying test cases using replay-ethernetip.sh"
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
        SERVER_EXEC="$ETHERNETIP_DIR/$SERVER_PATH/$SERVER_BINARY"
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
