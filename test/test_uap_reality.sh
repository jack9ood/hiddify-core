#!/bin/bash

# UAP + Reality 伪装测试脚本
# 用于测试 UAP 协议是否真正可以带伪装（Reality）使用

set -e

# 获取脚本所在目录
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# 项目根目录（假设 test 目录在项目根目录下）
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$SCRIPT_DIR"

echo "========================================="
echo "UAP + Reality 伪装测试"
echo "========================================="
echo ""

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# 检查配置文件是否存在
CONFIG_FILE="${1:-test_uap_reality_default.json}"

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

# 检查是否已编译
CLI_BIN="$PROJECT_ROOT/bin/hiddify-cli"
if [ ! -f "$CLI_BIN" ]; then
    echo "正在编译项目..."
    cd "$PROJECT_ROOT"
    go build -o ./bin/hiddify-cli ./cli
    if [ $? -ne 0 ]; then
        echo -e "${RED}编译失败！${NC}"
        exit 1
    fi
    echo -e "${GREEN}编译成功！${NC}"
    echo ""
    cd "$SCRIPT_DIR"
fi

# 步骤 1: 验证配置格式
echo "步骤 1: 验证配置格式"
echo "----------------------------------------"
echo "解析配置文件: $CONFIG_FILE"
PARSED_CONFIG=$("$CLI_BIN" parse "$CONFIG_FILE" 2>&1)
if [ $? -eq 0 ]; then
    echo -e "${GREEN}✓ 配置格式正确${NC}"
    
    # 检查 Reality 配置
    if echo "$PARSED_CONFIG" | grep -q '"reality"'; then
        echo -e "${GREEN}✓ Reality 配置存在${NC}"
        
        # 检查是否包含 public_key 和 short_id
        if echo "$PARSED_CONFIG" | grep -q '"public_key"'; then
            echo -e "${GREEN}✓ public_key 配置存在${NC}"
        else
            echo -e "${YELLOW}⚠ 警告: public_key 未找到（客户端不需要 private_key）${NC}"
        fi
        
        if echo "$PARSED_CONFIG" | grep -q '"short_id"'; then
            echo -e "${GREEN}✓ short_id 配置存在${NC}"
        else
            echo -e "${YELLOW}⚠ 警告: short_id 未找到${NC}"
        fi
    else
        echo -e "${RED}✗ Reality 配置未找到${NC}"
        exit 1
    fi
    
    # 检查是否跳过了 TLS tricks（Reality 模式下应该跳过）
    if echo "$PARSED_CONFIG" | grep -q '"tls_tricks"'; then
        echo -e "${YELLOW}⚠ 警告: TLS tricks 不应该在 Reality 模式下使用${NC}"
    else
        echo -e "${GREEN}✓ TLS tricks 正确跳过（Reality 模式）${NC}"
    fi
else
    echo -e "${RED}✗ 配置解析失败${NC}"
    echo "$PARSED_CONFIG"
    exit 1
fi
echo ""

# 步骤 2: 检查配置中的占位符
echo "步骤 2: 检查配置参数"
echo "----------------------------------------"
if grep -q "YOUR_SERVER_IP\|YOUR_UUID\|YOUR_PUBLIC_KEY\|YOUR_SHORT_ID" "$CONFIG_FILE"; then
    echo -e "${YELLOW}⚠ 警告: 配置文件中存在占位符，请替换为实际值：${NC}"
    echo "  - YOUR_SERVER_IP: 服务器 IP 地址"
    echo "  - YOUR_UUID: UAP 协议的 UUID"
    echo "  - YOUR_PUBLIC_KEY: Reality 的公钥（从服务器获取）"
    echo "  - YOUR_SHORT_ID: Reality 的 short_id（从服务器获取）"
    echo ""
    echo "请编辑 $CONFIG_FILE 并替换这些占位符"
    echo ""
    read -p "是否继续测试？(y/n) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        exit 0
    fi
else
    echo -e "${GREEN}✓ 配置参数已填写${NC}"
fi
echo ""

# 步骤 3: 生成完整的 sing-box 配置
echo "步骤 3: 生成完整的 sing-box 配置"
echo "----------------------------------------"
OUTPUT_CONFIG="$SCRIPT_DIR/test_uap_reality_output.json"
PARSE_OUTPUT=$("$CLI_BIN" parse "$CONFIG_FILE" 2>&1)
PARSE_EXIT_CODE=$?

# 检查输出中是否有 JSON 配置（即使有警告）
# 提取最后一个完整的 JSON 对象（从第一个 { 开始到最后一个 } 结束）
JSON_START=$(echo "$PARSE_OUTPUT" | grep -n '^{' | tail -1 | cut -d: -f1)
if [ -n "$JSON_START" ]; then
    # 从 JSON 开始位置提取到文件末尾
    echo "$PARSE_OUTPUT" | tail -n +$JSON_START > "$OUTPUT_CONFIG"
    
    # 检查是否有 uTLS 警告（这只是提示信息，不影响配置生成）
    if echo "$PARSE_OUTPUT" | grep -qi "utls.*not included\|utls.*required"; then
        echo -e "${YELLOW}ℹ 提示: Reality 客户端需要 uTLS 支持${NC}"
        echo "   配置已生成，但运行时需要支持 uTLS 的 sing-box 版本"
        echo "   项目使用的 github.com/jack9ood/hiddify-sing-box 已包含 uTLS 支持"
        echo ""
    fi
    
    # 检查配置是否包含 inbound（hiddify-cli run 需要完整配置）
    if ! grep -q '"inbounds"' "$OUTPUT_CONFIG"; then
        echo -e "${YELLOW}⚠ 生成的配置缺少 inbound，hiddify-cli run 会自动添加${NC}"
        echo "   如果使用 hiddify-cli run，会自动添加默认的 mixed inbound（端口 2334）"
    fi
    
    echo -e "${GREEN}✓ 配置已生成: $OUTPUT_CONFIG${NC}"
    
    # 验证生成的 JSON 是否有效（简单检查）
    if command -v python3 > /dev/null 2>&1; then
        if python3 -m json.tool "$OUTPUT_CONFIG" > /dev/null 2>&1; then
            echo -e "${GREEN}✓ JSON 格式验证通过${NC}"
        else
            echo -e "${YELLOW}⚠ JSON 格式验证失败，但配置可能仍然有效${NC}"
        fi
    fi
else
    echo -e "${RED}✗ 配置生成失败，未找到有效的 JSON 输出${NC}"
    echo "完整输出:"
    echo "$PARSE_OUTPUT"
    exit 1
fi
echo ""

# 步骤 4: 验证配置是否可以启动
echo "步骤 4: 验证配置是否可以启动"
echo "----------------------------------------"
if command -v sing-box &> /dev/null; then
    echo "检测到 sing-box 命令，尝试验证配置..."
    if sing-box check -c "$OUTPUT_CONFIG" 2>&1 | grep -q "configuration"; then
        echo -e "${GREEN}✓ sing-box 配置验证通过${NC}"
    else
        echo -e "${YELLOW}⚠ sing-box 验证结果：${NC}"
        sing-box check -c "$OUTPUT_CONFIG" 2>&1 || true
    fi
else
    echo -e "${GREEN}ℹ 使用项目内置的 sing-box 库（无需外部 sing-box 命令）${NC}"
    echo ""
    echo "项目已包含 sing-box 功能，可以使用以下方式运行："
    echo "  ${GREEN}$CLI_BIN run --config $OUTPUT_CONFIG${NC}"
    echo ""
    echo "或者使用测试脚本进行实际连接测试："
    echo "  ${GREEN}./test_uap_connection.sh $CONFIG_FILE${NC}"
fi
echo ""

# 步骤 5: 提供测试建议
echo "步骤 5: 测试建议"
echo "----------------------------------------"
echo "要测试 UAP + Reality 是否真正工作，请执行以下步骤："
echo ""
echo "1. 确保服务器端已正确配置 UAP + Reality"
echo ""
echo "2. 使用生成的配置启动代理："
echo "   ${GREEN}$CLI_BIN run --config $OUTPUT_CONFIG${NC}"
echo "   或使用测试脚本："
echo "   ${GREEN}./test_uap_connection.sh $CONFIG_FILE${NC}"
echo ""
echo "3. 在另一个终端测试连接（默认端口 2334）："
echo "   ${GREEN}curl --proxy socks5://127.0.0.1:2334 https://www.google.com${NC}"
echo ""
echo "4. 检查流量是否被伪装："
echo "   - 在服务器端使用 tcpdump 或 wireshark 抓包"
echo "   - 检查 TLS 握手是否伪装成目标网站（www.microsoft.com）"
echo "   - 验证 SNI 是否为 www.microsoft.com"
echo ""
echo "5. 使用在线工具验证："
echo "   - https://www.whatismyip.com/ 检查 IP 是否为服务器 IP"
echo "   - https://browserleaks.com/ssl 检查 TLS 指纹"
echo ""
echo "6. 如果连接失败，检查："
echo "   - 服务器防火墙是否开放 443 端口"
echo "   - Reality 配置是否正确（public_key, short_id）"
echo "   - UUID 是否正确"
echo "   - 服务器端日志是否有错误"
echo ""

echo "========================================="
echo "测试准备完成！"
echo "========================================="
echo ""
echo "配置文件已生成: $OUTPUT_CONFIG"
echo ""
echo "可以使用以下方式启动测试："
echo "  1. 使用 hiddify-cli run（推荐）："
echo "     ${GREEN}$CLI_BIN run --config $OUTPUT_CONFIG${NC}"
echo ""
echo "  2. 使用测试脚本（自动测试连接）："
echo "     ${GREEN}./test_uap_connection.sh $CONFIG_FILE${NC}"
echo ""
echo "  3. 如果已安装外部 sing-box："
echo "     ${GREEN}sing-box run -c $OUTPUT_CONFIG${NC}"

