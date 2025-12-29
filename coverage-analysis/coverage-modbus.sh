#!/bin/bash

# Coverage Analysis Script for Modbus Fuzzing
# This script uses gcovr to analyze code coverage after replaying test cases
# Includes server monitoring and automatic restart functionality
# 使用方法: ./coverage-modbus.sh [target] [fuzzer] [run_number]
# 示例: ./coverage-modbus.sh libmodbus aflnet 1
#       ./coverage-modbus.sh libplctag afl-ics 1

set -e

# 参数解析（可选，默认为 libmodbus）
TARGET_IMPL="${1:-libmodbus}"  # libmodbus 或 libplctag
FUZZER="${2:-aflnet}"          # afl-ics, aflnet, chatafl, a2, a3
RUN_NUM="${3:-1}"              # 实验次数

# Configuration - 根据目标调整（使用绝对路径）
BASE_DIR="/home/ecs-user/LLM_fuzz_experiment"

if [ "$TARGET_IMPL" = "libplctag" ]; then
    MODBUS_DIR="$BASE_DIR/libplctag"
    OUTPUT_DIR="$BASE_DIR/results/libplctag-${FUZZER}-${RUN_NUM}"
    COVERAGE_DIR="$BASE_DIR/coverage-reports"
    REPLAY_SCRIPT="$BASE_DIR/coverage-analysis/replay-modbus.sh"
    SERVER_PORT="5502"
    BUILD_TYPE="cmake"
else
    MODBUS_DIR="$BASE_DIR/libmodbus"
    OUTPUT_DIR="$BASE_DIR/results/libmodbus-${FUZZER}-${RUN_NUM}"
    COVERAGE_DIR="$BASE_DIR/coverage-reports"
    REPLAY_SCRIPT="$BASE_DIR/coverage-analysis/replay-modbus.sh"
    SERVER_PORT="1502"
    BUILD_TYPE="autotools"
fi

SERVER_CHECK_INTERVAL=5  # Check server status every 5 seconds
MAX_SERVER_RESTART_ATTEMPTS=100  # 增加重启次数限制（从3改为100）

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}=== Modbus Coverage Analysis Tool ===${NC}"

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
    
    if [ ! -d "$MODBUS_DIR" ]; then
        print_error "$TARGET_IMPL directory not found: $MODBUS_DIR"
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
    
    cd "$MODBUS_DIR"
    
    # Configure with coverage flags
    export CFLAGS="-fprofile-arcs -ftest-coverage -O0 -g"
    export CXXFLAGS="-fprofile-arcs -ftest-coverage -O0 -g"
    export LDFLAGS="-fprofile-arcs -ftest-coverage"
    
    if [ "$BUILD_TYPE" = "cmake" ]; then
        # libplctag 使用 CMake
        print_status "Using CMake build system..."
        
        # 应用覆盖率修复patch（添加 __gcov_flush 支持）
        if [ -f "$BASE_DIR/dockerfiles-libplctag/libplctag-coverage-fix.patch" ]; then
            if ! grep -q "__gcov_flush" src/tests/modbus_server/modbus_server.c 2>/dev/null; then
                print_status "Applying libplctag coverage fix patch (adds __gcov_flush)..."
                patch -p1 < "$BASE_DIR/dockerfiles-libplctag/libplctag-coverage-fix.patch"
                print_status "Coverage patch applied successfully"
            else
                print_status "Coverage patch already applied, skipping..."
            fi
        else
            print_warning "Coverage patch not found. modbus_server may not flush .gcda files properly."
        fi
        
        # 彻底清理之前的覆盖率数据
        print_status "Cleaning previous coverage data..."
        OLD_GCDA=$(find . -name "*.gcda" 2>/dev/null | wc -l)
        OLD_GCNO=$(find . -name "*.gcno" 2>/dev/null | wc -l)
        print_status "Found $OLD_GCDA old .gcda files and $OLD_GCNO old .gcno files"
        
        rm -rf build-coverage
        find . -name "*.gcda" -delete 2>/dev/null || true
        find . -name "*.gcno" -delete 2>/dev/null || true
        
        print_status "Old coverage data cleaned. Starting fresh build..."
        
        mkdir -p build-coverage
        cd build-coverage
        
        cmake -DCMAKE_C_COMPILER=gcc \
              -DCMAKE_CXX_COMPILER=g++ \
              -DCMAKE_C_FLAGS="$CFLAGS" \
              -DCMAKE_CXX_FLAGS="$CXXFLAGS" \
              -DCMAKE_EXE_LINKER_FLAGS="$LDFLAGS" \
              -DCMAKE_BUILD_TYPE=Debug \
              -DBUILD_TESTS=1 \
              ..
        make -j$(nproc)
        cd ..
    else
        # libmodbus 使用 autotools
        print_status "Using autotools build system..."
        
        # 彻底清理之前的覆盖率数据
        print_status "Cleaning previous coverage data..."
        OLD_GCDA=$(find . -name "*.gcda" 2>/dev/null | wc -l)
        OLD_GCNO=$(find . -name "*.gcno" 2>/dev/null | wc -l)
        print_status "Found $OLD_GCDA old .gcda files and $OLD_GCNO old .gcno files"
        
        make clean || true
        find . -name "*.gcda" -delete 2>/dev/null || true
        find . -name "*.gcno" -delete 2>/dev/null || true
        
        print_status "Old coverage data cleaned. Starting fresh build..."
        
        # Ensure coverage flags are used
        print_status "Configuring with coverage flags: $CFLAGS"
        ./configure --enable-static CC=gcc CXX=g++ CFLAGS="$CFLAGS" CXXFLAGS="$CXXFLAGS" LDFLAGS="$LDFLAGS"
        
        # Clean and rebuild with coverage
        make clean
        
        # Force rebuild with coverage flags
        print_status "Building with coverage instrumentation..."
        make all CFLAGS="$CFLAGS" CXXFLAGS="$CXXFLAGS" LDFLAGS="$LDFLAGS" V=1
    fi
    
    # Check if .gcno files were created during library build
    print_status "Checking for .gcno files after library build..."
    GCNO_LIB_COUNT=$(find src -name "*.gcno" 2>/dev/null | wc -l)
    print_status "Found $GCNO_LIB_COUNT .gcno files in src directory"
    
    # If no coverage files found, try manual compilation
    if [ "$GCNO_LIB_COUNT" -eq 0 ]; then
        print_warning "No .gcno files found in library. Trying manual compilation with coverage..."
        cd src
        for c_file in *.c; do
            if [ -f "$c_file" ]; then
                print_status "Compiling $c_file with coverage..."
                gcc $CFLAGS -c "$c_file" -o "${c_file%.c}.o" 2>/dev/null || true
            fi
        done
        # Rebuild the library
        ar rcs .libs/libmodbus.a *.o 2>/dev/null || true
        cd ..
        
        # Check again for .gcno files
        GCNO_LIB_COUNT=$(find src -name "*.gcno" 2>/dev/null | wc -l)
        print_status "After manual compilation: Found $GCNO_LIB_COUNT .gcno files"
    fi
    
    # Rebuild the server with coverage
    if [ "$BUILD_TYPE" = "cmake" ]; then
        # libplctag 的服务器已经在 CMake 构建中编译好了
        print_status "modbus_server built by CMake in build-coverage/bin_dist/"
        
        # Verify .gcno files
        print_status "Checking for .gcno files after compilation..."
        GCNO_COUNT=$(find build-coverage -name "*.gcno" 2>/dev/null | wc -l)
        GCNO_COUNT_ALL=$(find . -name "*.gcno" 2>/dev/null | wc -l)
        print_status "Found $GCNO_COUNT .gcno files in build-coverage directory"
        print_status "Found $GCNO_COUNT_ALL .gcno files total in $TARGET_IMPL"
    else
        # libmodbus 需要单独编译服务器
        cd tests
        print_status "Building coverage-enabled server with flags: $CFLAGS"
        gcc $CFLAGS $LDFLAGS random-test-server.c -I../src ../src/.libs/libmodbus.a -o server-coverage
        
        # Verify .gcno files are generated (compile-time coverage data)
        print_status "Checking for .gcno files after server compilation..."
        GCNO_COUNT=$(find . -name "*.gcno" 2>/dev/null | wc -l)
        GCNO_COUNT_ALL=$(find .. -name "*.gcno" 2>/dev/null | wc -l)
        print_status "Found $GCNO_COUNT .gcno files in tests directory"
        print_status "Found $GCNO_COUNT_ALL .gcno files total in $TARGET_IMPL"
        cd ..
    fi
    
    if [ "$GCNO_COUNT" -eq 0 ] && [ "$GCNO_COUNT_ALL" -eq 0 ]; then
        print_warning "No .gcno files found. Coverage instrumentation may have failed."
        print_status "Trying alternative build approach with explicit gcov linking..."
        gcc -fprofile-arcs -ftest-coverage -O0 -g -lgcov random-test-server.c -I../src ../src/.libs/libmodbus.a -o server-coverage
        
        # Check again after alternative build
        GCNO_COUNT_RETRY=$(find . -name "*.gcno" 2>/dev/null | wc -l)
        if [ "$GCNO_COUNT_RETRY" -gt 0 ]; then
            print_status "Alternative build successful: Found $GCNO_COUNT_RETRY .gcno files"
        else
            print_error "Coverage instrumentation failed. .gcno files not generated."
        fi
    else
        print_status "Coverage instrumentation successful: .gcno files generated at compile time"
    fi
    
    print_status "$TARGET_IMPL rebuilt with coverage instrumentation"
}

# Check if coverage server is running
is_coverage_server_running() {
    local pid=""
    
    if [ "$BUILD_TYPE" = "cmake" ]; then
        # libplctag 使用 modbus_server
        pid=$(pgrep -f "modbus_server.*$SERVER_PORT" 2>/dev/null)
    else
        # libmodbus 使用 server-coverage
        pid=$(pgrep -f "server-coverage $SERVER_PORT" 2>/dev/null)
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
    print_status "Starting coverage-enabled modbus server with monitoring..."
    
    # Kill any existing servers more aggressively
    pkill -9 -f "server-coverage" 2>/dev/null || true
    pkill -9 -f "modbus_server" 2>/dev/null || true
    
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
    cd "$MODBUS_DIR"
    
    if [ "$BUILD_TYPE" = "cmake" ]; then
        # libplctag 使用 CMake 构建的服务器
        # 从 build-coverage 目录启动以确保 .gcda 文件写入正确位置
        cd build-coverage
        
        if [ ! -f "./bin_dist/modbus_server" ]; then
            print_error "modbus_server binary not found. Please run rebuild first."
            exit 1
        fi
        
        # Start server with correct working directory for .gcda files
        ./bin_dist/modbus_server --listen 127.0.0.1:$SERVER_PORT &
        SERVER_PID=$!
    else
        # libmodbus 使用单独编译的服务器
        cd tests
        
        if [ ! -f "./server-coverage" ]; then
            print_error "Coverage-enabled server binary not found. Please run rebuild first."
            exit 1
        fi
        
        ./server-coverage $SERVER_PORT &
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
                pkill -9 -f "server-coverage" 2>/dev/null || true
                pkill -9 -f "modbus_server" 2>/dev/null || true
                
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
                
                cd "$MODBUS_DIR"
                if [ "$BUILD_TYPE" = "cmake" ]; then
                    cd build-coverage
                    ./bin_dist/modbus_server --listen 127.0.0.1:$SERVER_PORT &
                else
                    cd tests
                    ./server-coverage $SERVER_PORT &
                fi
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
    "$REPLAY_SCRIPT" "$TARGET_IMPL" "$FUZZER" "$RUN_NUM"
    
    # Stop server monitoring
    stop_server_monitoring
    
    print_status "Test case replay completed"
    
    # Check if .gcda files were generated during execution (runtime coverage data)
    print_status "Checking for .gcda files after server execution..."
    GCDA_COUNT=$(find "$MODBUS_DIR" -name "*.gcda" 2>/dev/null | wc -l)
    
    if [ "$BUILD_TYPE" = "cmake" ]; then
        # libplctag: 检查 build-coverage 目录
        GCDA_COUNT_BUILD=$(find "$MODBUS_DIR/build-coverage" -name "*.gcda" 2>/dev/null | wc -l)
        print_status "Found $GCDA_COUNT .gcda files total in $TARGET_IMPL"
        print_status "Found $GCDA_COUNT_BUILD .gcda files in build-coverage directory"
    else
        # libmodbus: 检查 tests 目录
        GCDA_COUNT_TESTS=$(find "$MODBUS_DIR/tests" -name "*.gcda" 2>/dev/null | wc -l)
        print_status "Found $GCDA_COUNT .gcda files total in $TARGET_IMPL"
        print_status "Found $GCDA_COUNT_TESTS .gcda files in tests directory"
    fi
    
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
    
    # Find coverage data files - 路径根据构建类型不同
    cd "$MODBUS_DIR"
    
    if [ "$BUILD_TYPE" = "cmake" ]; then
        # CMake 构建：覆盖率文件在 build-coverage 中
        print_status "Searching for coverage files in CMake build directory..."
        GCNO_FILES=$(find "$MODBUS_DIR/build-coverage" -name "*.gcno" 2>/dev/null | wc -l)
        GCDA_FILES=$(find "$MODBUS_DIR/build-coverage" -name "*.gcda" 2>/dev/null | wc -l)
        
        print_status "Found $GCNO_FILES .gcno files in build-coverage (compile-time coverage data)"
        print_status "Found $GCDA_FILES .gcda files in build-coverage (runtime coverage data)"
        
        if [ "$GCNO_FILES" -eq 0 ]; then
            print_error "No .gcno files found in build-coverage. Coverage instrumentation failed."
            return 1
        fi
        
        # 设置 gcovr 的根目录和对象目录
        GCOVR_ROOT="$MODBUS_DIR"
        GCOVR_OBJECT_DIR="$MODBUS_DIR/build-coverage"
    else
        # autotools 构建：覆盖率文件在 src 中
        print_status "Searching for coverage files in src directory..."
        GCNO_FILES=$(find "$MODBUS_DIR/src" -name "*.gcno" 2>/dev/null | wc -l)
        GCDA_FILES=$(find "$MODBUS_DIR/src" -name "*.gcda" 2>/dev/null | wc -l)
        
        print_status "Found $GCNO_FILES .gcno files in src directory (compile-time coverage data)"
        print_status "Found $GCDA_FILES .gcda files in src directory (runtime coverage data)"
        
        if [ "$GCNO_FILES" -eq 0 ]; then
            print_warning "No .gcno files found in src directory."
            # Check tests directory
            GCNO_FILES_TESTS=$(find "$MODBUS_DIR/tests" -name "*.gcno" 2>/dev/null | wc -l)
            if [ "$GCNO_FILES_TESTS" -gt 0 ]; then
                print_status "Found coverage data in tests directory"
                cd "$MODBUS_DIR/tests"
            fi
        fi
        
        # 设置 gcovr 的根目录和对象目录
        GCOVR_ROOT="$MODBUS_DIR"
        GCOVR_OBJECT_DIR="$MODBUS_DIR/src"
    fi
    
    if [ "$GCDA_FILES" -eq 0 ]; then
        print_warning "No .gcda files found. The coverage-enabled server may not have executed or no code was covered."
        print_status "Coverage reports will show 0% coverage since no runtime data is available."
    fi
    
    print_status "Coverage files summary: $GCNO_FILES .gcno files, $GCDA_FILES .gcda files"
    print_status "GCOVR_ROOT: $GCOVR_ROOT"
    print_status "GCOVR_OBJECT_DIR: $GCOVR_OBJECT_DIR"
    
    # Generate HTML coverage report (single summary page with branch coverage)
    # HTML_FILE="$COVERAGE_DIR/coverage-${TARGET_IMPL}-${FUZZER}-${RUN_NUM}.html"
    # print_status "Generating HTML coverage summary..."
    # 
    # # Use the correct root and object directory
    # if gcovr --root "$GCOVR_ROOT" \
    #       --object-directory "$GCOVR_OBJECT_DIR" \
    #       --html --branches \
    #       -o "$HTML_FILE" \
    #       --print-summary 2>/dev/null; then
    #     print_status "HTML report generated successfully: $HTML_FILE"
    # elif cd "$GCOVR_OBJECT_DIR" && gcovr --root "$GCOVR_ROOT" \
    #       --html --branches \
    #       -o "$HTML_FILE" \
    #       --print-summary 2>/dev/null; then
    #     print_status "HTML report generated (from object directory)"
    #     cd "$MODBUS_DIR"
    # else
    #     print_error "HTML report generation failed"
    # fi
    print_status "HTML report generation skipped (commented out)"
    
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
        cd "$MODBUS_DIR"
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
        cd "$MODBUS_DIR"
    else
        print_error "Branch coverage report generation failed"
    fi
    
    # Generate detailed text report
    # print_status "Generating detailed text coverage report..."
    # if gcovr --root "$GCOVR_ROOT" \
    #       --object-directory "$GCOVR_OBJECT_DIR" \
    #       --txt --show-branch -o "$COVERAGE_DIR/coverage-detailed.txt" 2>/dev/null; then
    #     print_status "Detailed text report generated successfully"
    # elif cd "$GCOVR_OBJECT_DIR" && gcovr --root "$GCOVR_ROOT" \
    #       --txt --show-branch -o "$COVERAGE_DIR/coverage-detailed.txt" 2>/dev/null; then
    #     print_status "Detailed text report generated (from src directory)"
    #     cd "$MODBUS_DIR"
    # else
    #     print_warning "Detailed text report generation failed"
    # fi
    print_status "Detailed text report generation skipped (commented out)"
    
    print_status "Coverage reports generated in: $COVERAGE_DIR"
    
    # 清理 .gcda 文件，避免影响下次分析
    print_status "Cleaning .gcda files to prevent contamination of next analysis..."
    find "$MODBUS_DIR" -name "*.gcda" -delete 2>/dev/null || true
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
    # echo "  - HTML Report:     $HTML_FILE (commented out)"
    
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
    pkill -TERM -f "server-coverage $SERVER_PORT" 2>/dev/null || true
    pkill -TERM -f "modbus_server --listen" 2>/dev/null || true
    sleep 1
    pkill -9 -f "server-coverage" 2>/dev/null || true
    pkill -9 -f "modbus_server" 2>/dev/null || true
    
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
    print_status "Use './fuzz-modbus.sh' to restart normal fuzzing"
}

# Parse command line arguments
case "${1:-}" in
    --help|-h)
        echo "Usage: $0 [target] [fuzzer] [run_number] [OPTIONS]"
        echo ""
        echo "Parameters:"
        echo "  target      : libmodbus 或 libplctag (默认: libmodbus)"
        echo "  fuzzer      : afl-ics, aflnet, chatafl, a2 (默认: aflnet)"
        echo "  run_number  : 实验次数 (默认: 1)"
        echo ""
        echo "Options:"
        echo "  --help, -h     Show this help message"
        echo "  --rebuild-only Rebuild with coverage only"
        echo "  --report-only  Generate reports from existing coverage data"
        echo "  --monitor-only Start coverage server with monitoring only"
        echo ""
        echo "Examples:"
        echo "  $0 libmodbus aflnet 1           # 分析 libmodbus 的 aflnet 结果"
        echo "  $0 libplctag afl-ics 1          # 分析 libplctag 的 afl-ics 结果"
        echo "  $0 libmodbus a2 2               # 分析 libmodbus 第2次实验"
        echo ""
        echo "This script performs comprehensive coverage analysis with server monitoring by:"
        echo "1. Rebuilding target with coverage instrumentation (autotools or CMake)"
        echo "2. Starting a coverage-enabled server with automatic restart monitoring"
        echo "3. Replaying test cases using replay-modbus.sh"
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
        if [ ! -f "$MODBUS_DIR/tests/server-coverage" ] && [ ! -f "$MODBUS_DIR/build-coverage/bin_dist/modbus_server" ]; then
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