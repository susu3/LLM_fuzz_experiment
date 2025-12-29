#!/bin/bash

echo "=========================================="
echo "Diagnosing .gcda File Generation Issue"
echo "=========================================="
echo ""

cd /home/ecs-user/LLM_fuzz_experiment/libplctag

# 1. Check if patch is applied
echo "1. Checking if coverage patch is applied..."
if grep -q "__gcov_flush" src/tests/modbus_server/modbus_server.c; then
    echo "   ✓ Patch applied in source"
else
    echo "   ✗ Patch NOT applied!"
    exit 1
fi

# 2. Check if binary has gcov symbols
echo "2. Checking if binary has gcov support..."
if strings build-coverage/bin_dist/modbus_server | grep -q "__gcov_flush"; then
    echo "   ✓ Binary has __gcov_flush symbol"
else
    echo "   ✗ Binary missing gcov support!"
    exit 1
fi

# 3. Check .gcno files
echo "3. Checking for .gcno files..."
GCNO_COUNT=$(find build-coverage -name "*.gcno" | wc -l)
echo "   Found $GCNO_COUNT .gcno files"
if [ "$GCNO_COUNT" -eq 0 ]; then
    echo "   ✗ No .gcno files! Coverage instrumentation failed."
    exit 1
fi

# 4. Clean and test
echo "4. Testing .gcda generation..."
cd build-coverage
rm -f src/tests/modbus_server/CMakeFiles/modbus_server.dir/*.gcda

# Kill any existing servers
pkill -9 modbus_server 2>/dev/null
fuser -k -9 5502/tcp 2>/dev/null
sleep 2

echo "   Starting server from $(pwd)..."
./bin_dist/modbus_server --listen 127.0.0.1:5502 > /tmp/modbus_test.log 2>&1 &
SERVER_PID=$!
echo "   Server PID: $SERVER_PID"
sleep 3

# Send a test request
echo "   Sending test request..."
echo -ne '\x00\x01\x00\x00\x00\x06\x01\x03\x00\x00\x00\x0a' | nc -w 1 127.0.0.1 5502 > /dev/null 2>&1
sleep 1

# Gracefully stop
echo "   Stopping server with SIGTERM..."
kill -TERM $SERVER_PID

# Wait and check
for i in {1..10}; do
    if ! ps -p $SERVER_PID > /dev/null 2>&1; then
        echo "   Server exited after $i seconds"
        break
    fi
    sleep 1
done

if ps -p $SERVER_PID > /dev/null 2>&1; then
    echo "   ✗ Server did not exit, force killing..."
    kill -9 $SERVER_PID
else
    echo "   ✓ Server exited gracefully"
fi

sleep 2

# Check for .gcda files
echo "5. Checking for .gcda files..."
GCDA_FILES=$(find src/tests/modbus_server/CMakeFiles/modbus_server.dir -name "*.gcda" 2>/dev/null)
GCDA_COUNT=$(echo "$GCDA_FILES" | grep -c "\.gcda$" || echo 0)

if [ "$GCDA_COUNT" -gt 0 ]; then
    echo "   ✓ SUCCESS! Found $GCDA_COUNT .gcda files:"
    echo "$GCDA_FILES" | head -5 | sed 's/^/     /'
else
    echo "   ✗ FAILED! No .gcda files generated"
    echo ""
    echo "   Possible causes:"
    echo "   - Server not built with coverage flags"
    echo "   - __gcov_flush() not working"
    echo "   - Wrong working directory"
    echo "   - Process killed before data written"
    echo ""
    echo "   Server log:"
    cat /tmp/modbus_test.log | tail -10 | sed 's/^/     /'
fi

echo ""
echo "=========================================="
echo "Diagnosis Complete"
echo "=========================================="

