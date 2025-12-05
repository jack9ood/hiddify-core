#!/bin/bash

# 检查 hiddify-sing-box 更新的脚本
# 用法: ./check_update.sh

# set -e  # 注释掉，避免因 API 调用失败而立即退出

REPO="jack9ood/hiddify-sing-box"
GOMOD_FILE="go.mod"
COLOR_GREEN='\033[0;32m'
COLOR_YELLOW='\033[1;33m'
COLOR_RED='\033[0;31m'
COLOR_BLUE='\033[0;34m'
COLOR_RESET='\033[0m'

echo -e "${COLOR_BLUE}检查 github.com/${REPO} 的更新...${COLOR_RESET}"
echo ""

# 检查 go.mod 文件是否存在
if [ ! -f "$GOMOD_FILE" ]; then
    echo -e "${COLOR_RED}错误: 找不到 $GOMOD_FILE 文件${COLOR_RESET}"
    exit 1
fi

# 从 go.mod 中提取当前版本信息
CURRENT_VERSION=$(grep -E "github.com/jack9ood/hiddify-sing-box" "$GOMOD_FILE" | head -1)
if [ -z "$CURRENT_VERSION" ]; then
    echo -e "${COLOR_RED}错误: 在 $GOMOD_FILE 中找不到 hiddify-sing-box 的版本信息${COLOR_RESET}"
    exit 1
fi

# 提取 commit hash (伪版本格式: v0.0.0-YYYYMMDDHHmmss-<commit-hash>)
CURRENT_COMMIT=$(echo "$CURRENT_VERSION" | grep -oE '[a-f0-9]{12}' | tail -1)
CURRENT_DATE=$(echo "$CURRENT_VERSION" | grep -oE '[0-9]{14}' | head -1)

if [ -z "$CURRENT_COMMIT" ] || [ -z "$CURRENT_DATE" ]; then
    echo -e "${COLOR_RED}错误: 无法解析当前版本信息${COLOR_RESET}"
    echo "当前版本行: $CURRENT_VERSION"
    exit 1
fi

echo -e "${COLOR_BLUE}当前版本:${COLOR_RESET}"
echo "  Commit: ${CURRENT_COMMIT}"
echo "  日期: ${CURRENT_DATE:0:4}-${CURRENT_DATE:4:2}-${CURRENT_DATE:6:2} ${CURRENT_DATE:8:2}:${CURRENT_DATE:10:2}:${CURRENT_DATE:12:2}"
echo ""

# 获取最新版本信息
echo "正在查询 GitHub 仓库..."

# 方法1: 使用 git ls-remote (更可靠)
LATEST_COMMIT_FULL=$(git ls-remote "https://github.com/${REPO}.git" HEAD 2>/dev/null | awk '{print $1}')

if [ -z "$LATEST_COMMIT_FULL" ]; then
    # 方法2: 如果 git ls-remote 失败，尝试使用 GitHub API
    echo "尝试使用 GitHub API..."
    API_RESPONSE=$(curl -s "https://api.github.com/repos/${REPO}/commits/HEAD" 2>&1)
    
    if [ $? -eq 0 ] && [ -n "$API_RESPONSE" ] && ! echo "$API_RESPONSE" | grep -q '"message"'; then
        LATEST_COMMIT_FULL=$(echo "$API_RESPONSE" | grep -oE '"sha":"[a-f0-9]{40}"' | head -1 | cut -d'"' -f4)
    fi
fi

if [ -z "$LATEST_COMMIT_FULL" ]; then
    echo -e "${COLOR_RED}错误: 无法获取最新版本信息，请检查网络连接${COLOR_RESET}"
    exit 1
fi

LATEST_COMMIT_SHORT=${LATEST_COMMIT_FULL:0:12}

# 获取最新 commit 的详细信息（使用 GitHub API）
LATEST_INFO=$(curl -s "https://api.github.com/repos/${REPO}/commits/${LATEST_COMMIT_FULL}" 2>&1)

if [ $? -eq 0 ] && [ -n "$LATEST_INFO" ] && ! echo "$LATEST_INFO" | grep -q '"message".*"Not Found"'; then
    # 尝试从 commit 对象中提取信息
    COMMIT_DATE=$(echo "$LATEST_INFO" | grep -oE '"date":"[^"]+"' | head -1 | cut -d'"' -f4)
    COMMIT_MESSAGE=$(echo "$LATEST_INFO" | grep -oE '"message":"[^"]+"' | head -1 | cut -d'"' -f4 | sed 's/\\n/ /g' | sed 's/\\"/"/g' | head -c 80)
    
    if [ -n "$COMMIT_DATE" ] && [ "$COMMIT_DATE" != "null" ]; then
        LATEST_DATE="$COMMIT_DATE"
        # 格式化日期为 YYYYMMDDHHmmss
        # 输入格式: 2025-12-05T05:57:15Z
        LATEST_DATE_FORMATTED=$(echo "$LATEST_DATE" | sed 's/T//' | sed 's/Z//' | sed 's/-//g' | sed 's/://g' | cut -c1-14)
    else
        LATEST_DATE="未知"
        LATEST_DATE_FORMATTED=$(date +%Y%m%d%H%M%S)
    fi
    
    if [ -n "$COMMIT_MESSAGE" ] && [ "$COMMIT_MESSAGE" != "null" ]; then
        LATEST_MESSAGE="$COMMIT_MESSAGE"
    else
        LATEST_MESSAGE="无法获取"
    fi
else
    # 如果 API 失败，使用当前时间作为占位符
    LATEST_DATE="未知"
    LATEST_MESSAGE="无法获取（可能需要 GitHub token）"
    LATEST_DATE_FORMATTED=$(date +%Y%m%d%H%M%S)
fi

echo -e "${COLOR_BLUE}最新版本:${COLOR_RESET}"
echo "  Commit: ${LATEST_COMMIT_SHORT}"
echo "  日期: ${LATEST_DATE}"
echo "  提交信息: ${LATEST_MESSAGE}"
echo ""

# 比较版本
if [ "$CURRENT_COMMIT" = "$LATEST_COMMIT_SHORT" ]; then
    echo -e "${COLOR_GREEN}✓ 已是最新版本！${COLOR_RESET}"
    exit 0
else
    echo -e "${COLOR_YELLOW}⚠ 发现新版本！${COLOR_RESET}"
    echo ""
    echo "更新方法："
    echo "1. 手动更新 go.mod 文件："
    echo -e "   ${COLOR_BLUE}replace github.com/sagernet/sing-box => github.com/jack9ood/hiddify-sing-box v0.0.0-${LATEST_DATE_FORMATTED}-${LATEST_COMMIT_SHORT}${COLOR_RESET}"
    echo ""
    echo "2. 或者运行以下命令自动更新："
    echo -e "   ${COLOR_BLUE}sed -i '' 's|github.com/jack9ood/hiddify-sing-box v0.0.0-[0-9]*-[a-f0-9]*|github.com/jack9ood/hiddify-sing-box v0.0.0-${LATEST_DATE_FORMATTED}-${LATEST_COMMIT_SHORT}|g' go.mod${COLOR_RESET}"
    echo ""
    echo "3. 然后运行："
    echo -e "   ${COLOR_BLUE}go mod tidy${COLOR_RESET}"
    echo ""
    
    # 询问是否自动更新
    read -p "是否自动更新到最新版本? (y/N): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        # 备份 go.mod
        cp "$GOMOD_FILE" "${GOMOD_FILE}.bak"
        echo "已备份 go.mod 为 ${GOMOD_FILE}.bak"
        
        # 更新 go.mod
        if [[ "$OSTYPE" == "darwin"* ]]; then
            # macOS
            sed -i '' "s|github.com/jack9ood/hiddify-sing-box v0.0.0-[0-9]*-[a-f0-9]*|github.com/jack9ood/hiddify-sing-box v0.0.0-${LATEST_DATE_FORMATTED}-${LATEST_COMMIT_SHORT}|g" "$GOMOD_FILE"
        else
            # Linux
            sed -i "s|github.com/jack9ood/hiddify-sing-box v0.0.0-[0-9]*-[a-f0-9]*|github.com/jack9ood/hiddify-sing-box v0.0.0-${LATEST_DATE_FORMATTED}-${LATEST_COMMIT_SHORT}|g" "$GOMOD_FILE"
        fi
        
        echo -e "${COLOR_GREEN}✓ 已更新 go.mod${COLOR_RESET}"
        
        # 运行 go mod tidy
        echo "正在运行 go mod tidy..."
        go mod tidy
        
        echo -e "${COLOR_GREEN}✓ 更新完成！${COLOR_RESET}"
    else
        echo "已取消更新"
    fi
    
    exit 1
fi

