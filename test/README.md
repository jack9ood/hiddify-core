# UAP 协议测试目录

本目录包含所有 UAP 协议相关的测试文件和脚本。

## 文件说明

### 配置文件

- `test_uap_config.json` - 基本 UAP 配置示例
- `test_uap_with_mux.json` - UAP + Mux 配置示例
- `test_uap_reality.json` - UAP + Reality 简单配置示例
- `test_uap_reality_full.json` - UAP + Reality 完整配置模板（包含 inbound）
- `test_uap_reality_default.json` - 默认测试配置（IP: 127.0.0.1，用于本地测试）

### 测试脚本

- `test_uap.sh` - UAP 协议基本功能测试脚本
- `test_uap_reality.sh` - UAP + Reality 配置验证脚本
- `test_uap_connection.sh` - UAP + Reality 实际连接测试脚本

### 文档

- `TEST_UAP.md` - UAP 协议测试指南
- `TEST_UAP_REALITY.md` - UAP + Reality 伪装测试详细指南
- `TEST_WITH_HIDDIFY_CLI.md` - 使用项目内置功能指南

## 使用方法

### 从 test 目录运行

```bash
cd test
./test_uap.sh                    # 基本功能测试
./test_uap_reality.sh            # Reality 配置验证
./test_uap_connection.sh          # 实际连接测试
```

### 从项目根目录运行

```bash
./test/test_uap.sh
./test/test_uap_reality.sh
./test/test_uap_connection.sh
```

## 快速开始

### 使用默认配置（本地测试，IP: 127.0.0.1）

```bash
cd test

# 直接运行测试（使用默认配置）
./test_uap_connection.sh

# 或验证配置
./test_uap_reality.sh
```

**注意**：默认配置使用 `127.0.0.1` 和示例值，可以直接运行测试：
- 服务器 IP: `127.0.0.1`
- UUID: `12345678-1234-1234-1234-123456789abc` (示例值)
- Reality public_key: `dQw4w9WgXcQ` (示例值)
- Reality short_id: `0123456789abcdef` (示例值)

实际连接时需要替换为真实的服务器配置。

### 使用自定义配置

1. **准备配置文件**：
   ```bash
   cd test
   cp test_uap_reality_full.json my_config.json
   # 编辑 my_config.json，替换占位符：
   # - YOUR_SERVER_IP: 服务器 IP
   # - YOUR_UUID: UAP UUID
   # - YOUR_PUBLIC_KEY: Reality 公钥
   # - YOUR_SHORT_ID: Reality short_id
   ```

2. **验证配置**：
   ```bash
   ./test_uap_reality.sh my_config.json
   ```

3. **测试连接**（使用项目内置的 sing-box）：
   ```bash
   # 方法 1: 使用测试脚本（推荐，自动测试连接）
   ./test_uap_connection.sh my_config.json
   
   # 方法 2: 手动运行（先生成配置）
   ../bin/hiddify-cli parse my_config.json > output.json
   ../bin/hiddify-cli run --config output.json
   ```

## 使用项目内置功能

**重要**：项目已内置 sing-box 功能，无需安装外部 sing-box 命令！

- ✅ 使用 `hiddify-cli run` 运行配置（项目内置）
- ✅ 自动支持 uTLS（Reality 需要）
- ✅ 自动添加 inbound、DNS、路由等配置

详细说明请查看：[TEST_WITH_HIDDIFY_CLI.md](./TEST_WITH_HIDDIFY_CLI.md)

## 注意事项

- 所有脚本会自动检测项目根目录和 bin/hiddify-cli 的位置
- 配置文件路径可以是相对路径或绝对路径
- 脚本生成的临时输出文件（如 `*_output.json`, `*_runtime.json`）会被自动忽略（.gitignore）
- 用户创建的测试配置文件（如 `my_*.json`）也会被忽略，建议使用模板文件创建

