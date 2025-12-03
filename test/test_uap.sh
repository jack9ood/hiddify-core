#!/bin/bash

# UAP 协议支持测试脚本

# 获取脚本所在目录
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# 项目根目录（假设 test 目录在项目根目录下）
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$SCRIPT_DIR"

echo "========================================="
echo "UAP 协议支持测试"
echo "========================================="
echo ""

# 检查是否已编译
CLI_BIN="$PROJECT_ROOT/bin/hiddify-cli"
if [ ! -f "$CLI_BIN" ]; then
    echo "正在编译项目..."
    cd "$PROJECT_ROOT"
    go build -o ./bin/hiddify-cli ./cli
    if [ $? -ne 0 ]; then
        echo "编译失败！"
        exit 1
    fi
    echo "编译成功！"
    echo ""
    cd "$SCRIPT_DIR"
fi

# 测试 1: 基本 UAP 配置解析
echo "测试 1: 基本 UAP 配置解析"
echo "----------------------------------------"
"$CLI_BIN" parse "$SCRIPT_DIR/test_uap_config.json" 2>&1 | head -50
echo ""
echo ""

# 测试 2: UAP 配置 + Mux 支持
echo "测试 2: UAP 配置 + Mux 支持"
echo "----------------------------------------"
"$CLI_BIN" parse "$SCRIPT_DIR/test_uap_with_mux.json" 2>&1 | head -50
echo ""
echo ""

# 测试 3: 验证输出中是否包含 multiplex 配置
echo "测试 3: 验证 Mux 配置是否被添加"
echo "----------------------------------------"
OUTPUT=$("$CLI_BIN" parse "$SCRIPT_DIR/test_uap_config.json" 2>&1)
if echo "$OUTPUT" | grep -q "multiplex"; then
    echo "✓ Mux 配置已成功添加"
else
    echo "✗ Mux 配置未找到（可能需要启用 Mux 选项）"
fi
echo ""

# 测试 4: 验证 TLS tricks 支持
echo "测试 4: 验证 TLS tricks 支持"
echo "----------------------------------------"
if echo "$OUTPUT" | grep -q "tls_tricks\|tls_fragment"; then
    echo "✓ TLS tricks 配置存在"
else
    echo "ℹ TLS tricks 配置未找到（可能需要启用 TLS tricks 选项）"
fi
echo ""

# 测试 5: Reality 配置测试
echo "测试 5: UAP Reality 配置测试"
echo "----------------------------------------"
if [ -f "$SCRIPT_DIR/test_uap_reality.json" ]; then
    REALITY_OUTPUT=$("$CLI_BIN" parse "$SCRIPT_DIR/test_uap_reality.json" 2>&1)
    if echo "$REALITY_OUTPUT" | grep -q "reality"; then
        echo "✓ Reality 配置被正确保留"
        if echo "$REALITY_OUTPUT" | grep -q "tls_tricks"; then
            echo "✗ 警告：Reality 配置不应该应用 TLS tricks"
        else
            echo "✓ TLS tricks 正确跳过（Reality 模式）"
        fi
    else
        echo "ℹ Reality 配置未找到（检查配置文件）"
    fi
else
    echo "ℹ test_uap_reality.json 不存在，跳过 Reality 测试"
fi
echo ""

echo "========================================="
echo "测试完成！"
echo "========================================="

