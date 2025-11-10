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
FUZZER="${2:-aflnet}"          # afl-ics, aflnet, chatafl, a2
RUN_NUM="${3:-1}"              # 实验次数

# Configuration - 根据目标调整
if [ "$TARGET_IMPL" = "libplctag" ]; then
    MODBUS_DIR="../libplctag"
    OUTPUT_DIR="../results/libplctag-${FUZZER}-${RUN_NUM}"
    COVERAGE_DIR="../coverage-reports/libplctag-${FUZZER}-${RUN_NUM}"
    REPLAY_SCRIPT="$(dirname $0)/replay-modbus.sh"
    SERVER_PORT="5502"
    BUILD_TYPE="cmake"
else
    MODBUS_DIR="../libmodbus"
    OUTPUT_DIR="../results/libmodbus-${FUZZER}-${RUN_NUM}"
    COVERAGE_DIR="../coverage-reports/libmodbus-${FUZZER}-${RUN_NUM}"
    REPLAY_SCRIPT="$(dirname $0)/replay-modbus.sh"
    SERVER_PORT="1502"
    BUILD_TYPE="autotools"
fi

SERVER_CHECK_INTERVAL=5  # Check server status every 5 seconds
MAX_SERVER_RESTART_ATTEMPTS=3

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
        print_error "Libmodbus directory not found: $MODBUS_DIR"
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
        rm -rf build-coverage
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
        make clean || true
        
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
    
    print_status "Libmodbus rebuilt with coverage instrumentation"
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
    
    # Kill any existing servers
    pkill -f "server" || true
    pkill -f "server-coverage" || true
    pkill -f "modbus_server" || true
    sleep 2
    
    # Start the coverage-enabled server
    cd "$MODBUS_DIR"
    
    if [ "$BUILD_TYPE" = "cmake" ]; then
        # libplctag 使用 CMake 构建的服务器
        cd build-coverage/bin_dist
        
        if [ ! -f "./modbus_server" ]; then
            print_error "modbus_server binary not found. Please run rebuild first."
            exit 1
        fi
        
        ./modbus_server --listen 127.0.0.1:$SERVER_PORT &
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
                
                cd "$MODBUS_DIR"
                if [ "$BUILD_TYPE" = "cmake" ]; then
                    cd build-coverage/bin_dist
                    ./modbus_server --listen 127.0.0.1:$SERVER_PORT &
                else
                    cd tests
                    ./server-coverage $SERVER_PORT &
                fi
                SERVER_PID=$!
                sleep 5
                
                if is_coverage_server_running; then
                    print_status "Coverage server restarted successfully with PID: $SERVER_PID"
                else
                    print_error "Failed to restart coverage server (attempt $SERVER_RESTART_COUNT)"
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
    GCDA_COUNT_TESTS=$(find "$MODBUS_DIR/tests" -name "*.gcda" 2>/dev/null | wc -l)
    print_status "Found $GCDA_COUNT .gcda files total in libmodbus"
    print_status "Found $GCDA_COUNT_TESTS .gcda files in tests directory"
    
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
    
    # Find coverage data files starting from libmodbus directory
    cd "$MODBUS_DIR"
    
    # Find .gcno files (compile-time) and .gcda files (runtime) for coverage analysis
    # Check in src directory first (where they should be)
    GCNO_FILES=$(find "$MODBUS_DIR/src" -name "*.gcno" 2>/dev/null | wc -l)
    GCDA_FILES=$(find "$MODBUS_DIR/src" -name "*.gcda" 2>/dev/null | wc -l)
    
    print_status "Found $GCNO_FILES .gcno files in src directory (compile-time coverage data)"
    print_status "Found $GCDA_FILES .gcda files in src directory (runtime coverage data)"
    
    if [ "$GCNO_FILES" -eq 0 ]; then
        print_warning "No .gcno files found in src directory."
        print_status "Checking other directories..."
        
        # Check tests directory
        GCNO_FILES_TESTS=$(find "$MODBUS_DIR/tests" -name "*.gcno" 2>/dev/null | wc -l)
        GCDA_FILES_TESTS=$(find "$MODBUS_DIR/tests" -name "*.gcda" 2>/dev/null | wc -l)
        print_status "In tests directory: $GCNO_FILES_TESTS .gcno files, $GCDA_FILES_TESTS .gcda files"
        
        # Check entire libmodbus directory
        GCNO_FILES_ALL=$(find "$MODBUS_DIR" -name "*.gcno" 2>/dev/null | wc -l)
        print_status "Total in libmodbus: $GCNO_FILES_ALL .gcno files"
        
        if [ "$GCNO_FILES_ALL" -eq 0 ]; then
            print_error "No .gcno files found anywhere. Coverage instrumentation was not successful during compilation."
            return 1
        fi
        
        if [ "$GCNO_FILES_TESTS" -gt 0 ]; then
            print_status "Found coverage data in tests directory, will use that"
            cd "$MODBUS_DIR/tests"
        fi
    else
        print_status "Found compile-time coverage data in src directory (correct location)"
    fi
    
    if [ "$GCDA_FILES" -eq 0 ]; then
        print_warning "No .gcda files found in src directory. The coverage-enabled server may not have executed or no code was covered."
        print_status "Coverage reports will show 0% coverage since no runtime data is available."
    fi
    
    print_status "Coverage files summary: $GCNO_FILES .gcno files, $GCDA_FILES .gcda files"
    
    # Debug: Show current directory and coverage files
    CURRENT_DIR=$(pwd)
    print_status "Current directory: $CURRENT_DIR"
    print_status "Sample .gcno files (compile-time):"
    find . -name "*.gcno" | head -3
    print_status "Sample .gcda files (runtime):"
    find . -name "*.gcda" | head -3
    
    # Debug: Show what gcovr can see
    print_status "Checking gcovr version and capabilities..."
    gcovr --version 2>/dev/null || print_warning "Could not get gcovr version"
    
    # Set up gcovr to find coverage files in the src directory
    print_status "Coverage files are located in: $MODBUS_DIR/src"
    print_status "Setting up gcovr to use libmodbus root with src as object directory"
    
    # Always use libmodbus root as the base, and specify src as object directory
    GCOVR_ROOT="$MODBUS_DIR"
    GCOVR_OBJECT_DIR="$MODBUS_DIR/src"
    
    print_status "GCOVR_ROOT: $GCOVR_ROOT"
    print_status "GCOVR_OBJECT_DIR: $GCOVR_OBJECT_DIR"
    
    # Verify the coverage files exist in src directory
    SRC_GCNO_COUNT=$(find "$MODBUS_DIR/src" -name "*.gcno" 2>/dev/null | wc -l)
    SRC_GCDA_COUNT=$(find "$MODBUS_DIR/src" -name "*.gcda" 2>/dev/null | wc -l)
    print_status "Verified: $SRC_GCNO_COUNT .gcno files in src directory"
    print_status "Verified: $SRC_GCDA_COUNT .gcda files in src directory"
    
    # Generate HTML coverage report
    print_status "Generating HTML coverage report..."
    
    # Use the correct root and object directory
    if gcovr --root "$GCOVR_ROOT" \
          --object-directory "$GCOVR_OBJECT_DIR" \
          --html --html-details -o "$COVERAGE_DIR/coverage.html" \
          --print-summary 2>/dev/null; then
        print_status "HTML report generated successfully"
    elif gcovr --root "$GCOVR_ROOT" \
          --html --html-details -o "$COVERAGE_DIR/coverage.html" \
          --print-summary 2>/dev/null; then
        print_status "HTML report generated (without explicit object directory)"
    elif cd "$GCOVR_OBJECT_DIR" && gcovr --root "$GCOVR_ROOT" \
          --html --html-details -o "$COVERAGE_DIR/coverage.html" \
          --print-summary 2>/dev/null; then
        print_status "HTML report generated (from src directory)"
        cd "$MODBUS_DIR"
    else
        print_error "HTML report generation failed"
    fi
    
    # Generate text summary
    print_status "Generating text coverage summary..."
    
    # Try with verbose output to see what's happening
    if gcovr --root "$GCOVR_ROOT" \
          --object-directory "$GCOVR_OBJECT_DIR" \
          --txt -o "$COVERAGE_DIR/coverage.txt" \
          --print-summary 2>/dev/null; then
        print_status "Text summary generated successfully"
    elif cd "$GCOVR_OBJECT_DIR" && gcovr --root "$GCOVR_ROOT" \
          --txt -o "$COVERAGE_DIR/coverage.txt" \
          --print-summary 2>/dev/null; then
        print_status "Text summary generated (from src directory)"
        cd "$MODBUS_DIR"
    else
        print_error "Text summary generation failed"
    fi
    
    # Generate detailed text report
    print_status "Generating detailed text coverage report..."
    if gcovr --root "$GCOVR_ROOT" \
          --object-directory "$GCOVR_OBJECT_DIR" \
          --txt --show-branch -o "$COVERAGE_DIR/coverage-detailed.txt" 2>/dev/null; then
        print_status "Detailed text report generated successfully"
    elif cd "$GCOVR_OBJECT_DIR" && gcovr --root "$GCOVR_ROOT" \
          --txt --show-branch -o "$COVERAGE_DIR/coverage-detailed.txt" 2>/dev/null; then
        print_status "Detailed text report generated (from src directory)"
        cd "$MODBUS_DIR"
    else
        print_warning "Detailed text report generation failed"
    fi
    
    print_status "Coverage reports generated in: $COVERAGE_DIR"
}

# Display coverage summary
display_summary() {
    print_status "Coverage Analysis Summary:"
    echo "=========================="
    
    if [ -f "$COVERAGE_DIR/coverage.txt" ]; then
        cat "$COVERAGE_DIR/coverage.txt"
    fi
    
    echo ""
    print_status "Available reports:"
    echo "  - HTML Report: $COVERAGE_DIR/coverage.html"
    echo "  - Text Summary: $COVERAGE_DIR/coverage.txt"
    echo "  - Detailed Report: $COVERAGE_DIR/coverage-detailed.txt"
    
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
    pkill -f "server" || true
    pkill -f "server-coverage" || true
    
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
        if [ ! -f "$MODBUS_DIR/tests/server-coverage" ]; then
            print_error "Coverage server binary not found. Run '$0 --rebuild-only' first."
            exit 1
        fi
        start_coverage_server
        print_status "Coverage server started with monitoring. Press Ctrl+C to stop."
        monitor_coverage_server
        exit 0
        ;;
    "")
        main
        ;;
    *)
        print_error "Unknown option: $1"
        echo "Use '$0 --help' for usage information"
        exit 1
        ;;
esac 