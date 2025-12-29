#!/bin/bash

# 测试 libplctag 覆盖率修复是否生效
# 用法: ./test-libplctag-coverage-fix.sh

BASE_DIR="/home/ecs-user/LLM_fuzz_experiment"
COVERAGE_SCRIPT="$BASE_DIR/coverage-analysis/coverage-modbus.sh"

echo "=========================================="
echo "Testing libplctag Coverage Fix"
echo "=========================================="
echo ""

# 1. 测试两个不同的模糊器
echo "Step 1: Running coverage analysis for aflnet-1..."
$COVERAGE_SCRIPT libplctag aflnet 1

echo ""
echo "Step 2: Running coverage analysis for a2-1..."
$COVERAGE_SCRIPT libplctag a2 1

echo ""
echo "=========================================="
echo "Step 3: Comparing results..."
echo "=========================================="

# 比较覆盖率报告
REPORT1="/home/ecs-user/LLM_fuzz_experiment/coverage-reports/coverage-line-libplctag-aflnet-1.txt"
REPORT2="/home/ecs-user/LLM_fuzz_experiment/coverage-reports/coverage-line-libplctag-a2-1.txt"

if [ -f "$REPORT1" ] && [ -f "$REPORT2" ]; then
    echo ""
    echo "=== aflnet-1 coverage ==="
    tail -3 "$REPORT1"
    
    echo ""
    echo "=== a2-1 coverage ==="
    tail -3 "$REPORT2"
    
    echo ""
    echo "=== Checking if coverages are different ==="
    if diff -q "$REPORT1" "$REPORT2" > /dev/null; then
        echo "❌ FAILED: Coverage reports are identical!"
        echo "   The fix did not work. Coverage data is not being properly recorded."
    else
        echo "✅ SUCCESS: Coverage reports are different!"
        echo "   The fix is working. Each fuzzer produces unique coverage data."
    fi
else
    echo "❌ ERROR: One or both coverage reports not found"
fi

echo ""
echo "=========================================="
echo "Test completed"
echo "=========================================="

