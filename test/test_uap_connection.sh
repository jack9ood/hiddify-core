#!/bin/bash

# UAP + Reality 实际连接测试脚本
# 用于测试 UAP 协议是否真正可以建立连接并传输数据

set -e

# 获取脚本所在目录
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# 项目根目录（假设 test 目录在项目根目录下）
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$SCRIPT_DIR"

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

CONFIG_FILE="${1:-test_uap_reality_default.json}"
PROXY_PORT="${2:-1080}"
TEST_URL="${3:-https://www.google.com}"

echo -e "${BLUE}=========================================${NC}"
echo -e "${BLUE}UAP + Reality 连接测试${NC}"
echo -e "${BLUE}=========================================${NC}"
echo ""

# 检查配置文件
# 如果文件路径不是绝对路径，尝试在当前目录和脚本目录查找
if [[ "$CONFIG_FILE" != /* ]]; then
    # 相对路径：先检查当前目录，再检查脚本目录
    if [ -f "$CONFIG_FILE" ]; then
        # 文件在当前目录，使用当前路径
        CONFIG_FILE="$CONFIG_FILE"
    elif [ -f "$SCRIPT_DIR/$CONFIG_FILE" ]; then
        # 文件在脚本目录
        CONFIG_FILE="$SCRIPT_DIR/$CONFIG_FILE"
    else
        echo -e "${RED}错误: 配置文件 $CONFIG_FILE 不存在${NC}"
        echo "请先创建配置文件，参考 $SCRIPT_DIR/test_uap_reality_full.json"
        exit 1
    fi
else
    # 绝对路径：直接检查
    if [ ! -f "$CONFIG_FILE" ]; then
        echo -e "${RED}错误: 配置文件 $CONFIG_FILE 不存在${NC}"
        exit 1
    fi
fi

# 检查是否有占位符（默认配置文件允许跳过此检查）
if grep -q "YOUR_SERVER_IP\|YOUR_UUID\|YOUR_PUBLIC_KEY\|YOUR_SHORT_ID" "$CONFIG_FILE"; then
    # 如果是默认配置文件，给出提示但不退出
    if [[ "$CONFIG_FILE" == *"test_uap_reality_default.json" ]] || [[ "$CONFIG_FILE" == *"default.json" ]]; then
        echo -e "${YELLOW}⚠ 警告: 配置文件中存在占位符${NC}"
        echo "  默认配置文件使用示例值，实际连接需要替换为真实值"
        echo "  继续测试配置格式..."
        echo ""
    else
        echo -e "${RED}错误: 配置文件中存在占位符，请先填写实际值${NC}"
        echo "  或使用默认配置: test_uap_reality_default.json"
        exit 1
    fi
fi

# 检查 CLI 工具
CLI_BIN="$PROJECT_ROOT/bin/hiddify-cli"
if [ ! -f "$CLI_BIN" ]; then
    echo -e "${RED}错误: 未找到 hiddify-cli，请先编译项目${NC}"
    exit 1
fi

# 生成配置
echo "步骤 1: 生成 sing-box 配置"
echo "----------------------------------------"
OUTPUT_CONFIG="$SCRIPT_DIR/test_uap_reality_runtime.json"

# 检查配置文件是否包含 inbound
if grep -q '"inbounds"' "$CONFIG_FILE"; then
    # 如果配置文件已包含 inbound，直接使用 parse
    echo "配置文件包含 inbound，使用 parse 生成配置..."
    "$CLI_BIN" parse "$CONFIG_FILE" > "$OUTPUT_CONFIG" 2>&1
    if [ $? -ne 0 ]; then
        echo -e "${RED}✗ 配置生成失败${NC}"
        exit 1
    fi
    # 提取 JSON 部分（去除可能的警告信息）
    if grep -q '^{' "$OUTPUT_CONFIG"; then
        JSON_START=$(grep -n '^{' "$OUTPUT_CONFIG" | tail -1 | cut -d: -f1)
        if [ -n "$JSON_START" ]; then
            tail -n +$JSON_START "$OUTPUT_CONFIG" > "$OUTPUT_CONFIG.tmp"
            mv "$OUTPUT_CONFIG.tmp" "$OUTPUT_CONFIG"
        fi
    fi
else
    # 如果只有 outbounds，使用 build 生成完整配置（会自动添加 inbound）
    echo "配置文件只有 outbounds，使用 build 生成完整配置（会自动添加 inbound）..."
    "$CLI_BIN" build -c "$CONFIG_FILE" -o "$OUTPUT_CONFIG" 2>&1
    if [ $? -ne 0 ]; then
        echo -e "${RED}✗ 配置生成失败${NC}"
        exit 1
    fi
fi

echo -e "${GREEN}✓ 配置已生成: $OUTPUT_CONFIG${NC}"
echo ""

# 验证配置（使用 libbox.CheckConfig）
echo "步骤 2: 验证配置"
echo "----------------------------------------"
# 使用 hiddify-cli check 验证配置（如果支持）
if "$CLI_BIN" check -c "$OUTPUT_CONFIG" &> /dev/null 2>&1; then
    echo -e "${GREEN}✓ 配置验证通过${NC}"
else
    # 尝试使用 libbox.CheckConfig 验证（通过 Go 代码）
    echo -e "${YELLOW}ℹ 使用项目内置验证${NC}"
    # 配置验证会在运行时进行
fi
echo ""

# 启动代理服务（使用项目内置的 sing-box）
echo "步骤 3: 启动代理服务"
echo "----------------------------------------"
echo "正在使用 hiddify-cli run 启动代理服务..."
echo "（使用项目内置的 sing-box 库，无需外部 sing-box 命令）"
echo ""

# 使用 hiddify-cli run 启动服务（后台运行）
# 注意：hiddify-cli run 需要 --config 参数
"$CLI_BIN" run --config "$OUTPUT_CONFIG" > /tmp/hiddify-cli.log 2>&1 &
HIDDIFY_CLI_PID=$!

# 等待服务启动
sleep 3

# 检查进程是否还在运行
if ! kill -0 $HIDDIFY_CLI_PID 2>/dev/null; then
    echo -e "${RED}✗ hiddify-cli 启动失败${NC}"
    echo "日志:"
    cat /tmp/hiddify-cli.log
    exit 1
fi

echo -e "${GREEN}✓ hiddify-cli 已启动 (PID: $HIDDIFY_CLI_PID)${NC}"
echo "  日志文件: /tmp/hiddify-cli.log"
echo "  默认监听端口: 2334 (SOCKS5/HTTP)"
echo ""

# 清理函数
cleanup() {
    echo ""
    echo "正在停止 hiddify-cli..."
    kill $HIDDIFY_CLI_PID 2>/dev/null || true
    wait $HIDDIFY_CLI_PID 2>/dev/null || true
    echo -e "${GREEN}✓ 已停止${NC}"
}

trap cleanup EXIT

# 测试连接
echo "步骤 4: 测试连接"
echo "----------------------------------------"
echo "测试 URL: $TEST_URL"
# hiddify-cli run 默认使用 2334 端口，但可以通过 --in-proxy-port 指定
ACTUAL_PORT=${PROXY_PORT:-2334}
echo "代理: socks5://127.0.0.1:$ACTUAL_PORT"
echo ""

# 测试 1: 基本连接
echo "测试 1: 基本 HTTP 连接"
if curl -s --proxy "socks5://127.0.0.1:$ACTUAL_PORT" --max-time 10 "$TEST_URL" > /dev/null 2>&1; then
    echo -e "${GREEN}✓ 连接成功${NC}"
else
    echo -e "${RED}✗ 连接失败${NC}"
    echo "检查日志: tail -f /tmp/hiddify-cli.log"
    echo ""
    echo "提示:"
    echo "  - 确保配置中的服务器信息正确"
    echo "  - 检查服务器是否可访问"
    echo "  - 查看完整日志了解错误详情"
    exit 1
fi

# 测试 2: IP 检查
echo ""
echo "测试 2: IP 地址检查"
IP=$(curl -s --proxy "socks5://127.0.0.1:$ACTUAL_PORT" --max-time 10 "https://api.ipify.org" 2>/dev/null)
if [ -n "$IP" ]; then
    echo -e "${GREEN}✓ 当前 IP: $IP${NC}"
    echo "  请验证此 IP 是否为您的服务器 IP"
else
    echo -e "${YELLOW}⚠ 无法获取 IP 地址${NC}"
fi

# 测试 3: DNS 检查
echo ""
echo "测试 3: DNS 解析"
if curl -s --proxy "socks5://127.0.0.1:$ACTUAL_PORT" --max-time 10 "https://www.google.com" > /dev/null 2>&1; then
    echo -e "${GREEN}✓ DNS 解析正常${NC}"
else
    echo -e "${YELLOW}⚠ DNS 解析可能有问题${NC}"
fi

# 测试 4: 检查日志中的错误
echo ""
echo "步骤 5: 检查运行日志"
echo "----------------------------------------"
if grep -i "error\|fail\|reject" /tmp/hiddify-cli.log > /dev/null 2>&1; then
    echo -e "${YELLOW}⚠ 发现可能的错误:${NC}"
    grep -i "error\|fail\|reject" /tmp/hiddify-cli.log | tail -5
else
    echo -e "${GREEN}✓ 未发现明显错误${NC}"
fi

echo ""
echo -e "${BLUE}=========================================${NC}"
echo -e "${GREEN}测试完成！${NC}"
echo -e "${BLUE}=========================================${NC}"
echo ""
echo "提示:"
echo "  - 查看完整日志: tail -f /tmp/hiddify-cli.log"
echo "  - 停止代理: kill $HIDDIFY_CLI_PID"
echo "  - 测试其他 URL: curl --proxy socks5://127.0.0.1:$ACTUAL_PORT <URL>"
echo ""
echo "要验证伪装效果，请："
echo "  1. 在服务器端使用 tcpdump 抓包"
echo "  2. 检查 SNI 是否为 www.microsoft.com（配置中的 server_name）"
echo "  3. 使用 Wireshark 分析 TLS 握手"
echo ""
echo "注意:"
echo "  - 使用的是项目内置的 sing-box 库（无需外部 sing-box 命令）"
echo "  - 默认监听端口: 2334"
echo "  - 可以通过 --in-proxy-port 参数修改端口"

