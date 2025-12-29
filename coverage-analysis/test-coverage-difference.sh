#!/bin/bash

echo "=========================================="
echo "Testing Coverage Difference Between Fuzzers"
echo "=========================================="

BASE_DIR="/home/ecs-user/LLM_fuzz_experiment"
cd "$BASE_DIR/libplctag/build-coverage"

# Clean everything
echo ""
echo "1. Cleaning old data..."
pkill -9 modbus_server 2>/dev/null || true
fuser -k -9 5502/tcp 2>/dev/null || true
sleep 2
rm -f src/tests/modbus_server/CMakeFiles/modbus_server.dir/*.gcda

# Test with aflnet-1
echo ""
echo "2. Testing with aflnet-1 (first 10 test cases)..."
./bin_dist/modbus_server --listen 127.0.0.1:5502 > /tmp/server1.log 2>&1 &
SERVER_PID=$!
sleep 2

SUCCESS_COUNT=0
for i in {0..9}; do
    testcase=$(ls "$BASE_DIR/results/libplctag-aflnet-1/replayable-queue/id:*" 2>/dev/null | sed -n "$((i+1))p")
    if [ -n "$testcase" ]; then
        if /home/ecs-user/AFL-ICS/aflnet-replay "$testcase" MODBUS 5502 > /dev/null 2>&1; then
            SUCCESS_COUNT=$((SUCCESS_COUNT + 1))
        fi
    fi
done

echo "   Replayed 10 test cases, $SUCCESS_COUNT succeeded"
kill -TERM $SERVER_PID
wait $SERVER_PID 2>/dev/null || true
sleep 2

GCDA_COUNT1=$(find src/tests/modbus_server/CMakeFiles/modbus_server.dir -name "*.gcda" | wc -l)
echo "   Generated $GCDA_COUNT1 .gcda files"

# Save the .gcda files
mkdir -p /tmp/gcda_test1
cp src/tests/modbus_server/CMakeFiles/modbus_server.dir/*.gcda /tmp/gcda_test1/ 2>/dev/null
rm -f src/tests/modbus_server/CMakeFiles/modbus_server.dir/*.gcda

# Test with a2-1
echo ""
echo "3. Testing with a2-1 (first 10 test cases)..."
./bin_dist/modbus_server --listen 127.0.0.1:5502 > /tmp/server2.log 2>&1 &
SERVER_PID=$!
sleep 2

SUCCESS_COUNT=0
for i in {0..9}; do
    testcase=$(ls "$BASE_DIR/results/libplctag-a2-1/replayable-queue/id:*" 2>/dev/null | sed -n "$((i+1))p")
    if [ -n "$testcase" ]; then
        if /home/ecs-user/AFL-ICS/aflnet-replay "$testcase" MODBUS 5502 > /dev/null 2>&1; then
            SUCCESS_COUNT=$((SUCCESS_COUNT + 1))
        fi
    fi
done

echo "   Replayed 10 test cases, $SUCCESS_COUNT succeeded"
kill -TERM $SERVER_PID
wait $SERVER_PID 2>/dev/null || true
sleep 2

GCDA_COUNT2=$(find src/tests/modbus_server/CMakeFiles/modbus_server.dir -name "*.gcda" | wc -l)
echo "   Generated $GCDA_COUNT2 .gcda files"

# Compare .gcda files
echo ""
echo "4. Comparing .gcda files..."
mkdir -p /tmp/gcda_test2
cp src/tests/modbus_server/CMakeFiles/modbus_server.dir/*.gcda /tmp/gcda_test2/ 2>/dev/null

DIFF_COUNT=0
for file in /tmp/gcda_test1/*.gcda; do
    filename=$(basename "$file")
    if [ -f "/tmp/gcda_test2/$filename" ]; then
        if ! cmp -s "$file" "/tmp/gcda_test2/$filename"; then
            DIFF_COUNT=$((DIFF_COUNT + 1))
            echo "   Different: $filename"
        fi
    fi
done

echo ""
echo "=========================================="
echo "Results:"
echo "  - aflnet-1: $GCDA_COUNT1 .gcda files"
echo "  - a2-1: $GCDA_COUNT2 .gcda files"
echo "  - Different files: $DIFF_COUNT"
echo ""

if [ "$DIFF_COUNT" -gt 0 ]; then
    echo "✓ SUCCESS: Test cases trigger different code paths!"
else
    echo "✗ PROBLEM: Test cases trigger identical code paths"
    echo ""
    echo "Possible reasons:"
    echo "1. Test cases are too similar"
    echo "2. Only basic server code is being executed"
    echo "3. Most test cases are failing"
fi
echo "=========================================="

# Cleanup
rm -rf /tmp/gcda_test1 /tmp/gcda_test2
pkill -9 modbus_server 2>/dev/null || true

