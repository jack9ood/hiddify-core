# UAP 协议支持测试指南

本文档说明如何测试 UAP 协议在本项目中的支持情况。

## 测试方法

### 方法 1: 使用 Go 单元测试（推荐）

运行单元测试来验证 UAP 协议的各种功能：

```bash
# 运行所有 UAP 相关测试
go test ./config -v -run TestUAP

# 运行特定测试
go test ./config -v -run TestUAPTLSTricks
go test ./config -v -run TestUAPProtocolSupport
go test ./config -v -run TestUAPWithGRPCTransport
```

### 方法 2: 使用命令行工具测试

1. **编译项目**（如果还没有编译）：
```bash
go build -o ./bin/hiddify-cli ./cli
```

2. **创建测试配置文件**：
   - `test_uap_config.json` - 基本 UAP 配置
   - `test_uap_with_mux.json` - 带 Mux 的 UAP 配置

3. **运行解析测试**：
```bash
# 解析基本 UAP 配置
./bin/hiddify-cli parse test_uap_config.json

# 解析带 Mux 的 UAP 配置
./bin/hiddify-cli parse test_uap_with_mux.json

# 输出到文件
./bin/hiddify-cli parse test_uap_config.json -o output.json
```

4. **使用测试脚本**：
```bash
chmod +x test_uap.sh
./test_uap.sh
```

### 方法 3: 手动测试配置文件

创建一个包含 UAP 协议的完整配置文件：

```json
{
  "outbounds": [
    {
      "type": "uap",
      "tag": "uap-server",
      "server": "your-server.com",
      "server_port": 443,
      "uuid": "your-uuid-here",
      "flow": "",
      "tls": {
        "enabled": true,
        "server_name": "your-server.com",
        "insecure": false
      },
      "transport": {
        "type": "ws",
        "path": "/path",
        "headers": {}
      }
    }
  ]
}
```

然后使用命令行工具解析：
```bash
./bin/hiddify-cli parse your_config.json
```

## 测试要点

### 1. Mux 支持测试
- 确保配置中启用了 Mux 选项
- 解析后的配置应该包含 `multiplex` 字段
- 检查 `multiplex.enabled` 是否为 `true`

### 2. TLS Tricks 支持测试
- 测试 MixedCaseSNI（混合大小写 SNI）
- 测试 Padding（填充）
- 测试 Fragment（分片）
- 验证 `tls_tricks` 配置是否正确添加

### 3. Transport 支持测试
- WebSocket (ws)
- gRPC (grpc)
- HTTP Upgrade (httpupgrade)

### 4. Reality 支持测试 ✅
- UAP 协议支持 Reality（与 VLESS 相同）
- 检查 Reality 配置是否正确处理
- 验证 Reality 模式下 TLS tricks 被正确跳过
- 测试 Reality 检测功能

## 预期结果

### 成功标志
- ✅ 配置文件能够成功解析
- ✅ Mux 配置被正确添加（如果启用）
- ✅ TLS tricks 配置被正确应用（如果启用）
- ✅ 输出配置通过 sing-box 验证

### 验证输出配置

解析后的配置应该包含：
1. **Mux 配置**（如果启用）：
```json
{
  "multiplex": {
    "enabled": true,
    "padding": true,
    "max_streams": 8,
    "protocol": "h2mux"
  }
}
```

2. **TLS Tricks 配置**（如果启用）：
```json
{
  "tls": {
    "enabled": true,
    "tls_tricks": {
      "mixed_case_sni": true,
      "padding_mode": "random",
      "padding_size": "1200-1500"
    },
    "utls": {
      "enabled": true,
      "fingerprint": "custom"
    }
  }
}
```

## 故障排除

### 问题：解析失败，提示 "unknown outbound type: uap"
**原因**：sing-box 的 option 包可能还不支持 UAP 类型的直接解析。

**解决方案**：
- 我们的代码通过 JSON map 方式处理 UAP，这是正常的
- 确保使用 `ParseConfigContent` 函数而不是直接 unmarshal

### 问题：Mux 配置未添加
**检查**：
- 确保 `HiddifyOptions.Mux.Enable = true`
- 检查 `patchOutbound` 函数中的 switch 语句是否包含 `case "uap"`

### 问题：TLS Tricks 未应用
**检查**：
- 确保 TLS 已启用 (`tls.enabled = true`)
- 确保 Transport 类型是 ws、grpc 或 httpupgrade
- 检查 `patchOutboundTLSTricks` 函数中的 UAP 处理逻辑

## 测试覆盖

当前测试覆盖：
- ✅ UAP 协议基本解析
- ✅ Mux 支持
- ✅ TLS Tricks 支持（MixedCaseSNI, Padding）
- ✅ gRPC Transport 支持
- ✅ WebSocket Transport 支持
- ✅ **Reality 支持**（新增）
- ✅ **Reality 检测功能**（新增）
- ✅ **Reality 模式下 TLS tricks 跳过**（新增）

待测试：
- ⏳ HTTP Upgrade Transport
- ⏳ Fragment 支持
- ⏳ 完整的端到端连接测试

## Reality 测试示例

### 使用命令行工具测试 Reality

创建包含 Reality 的 UAP 配置：

```bash
./bin/hiddify-cli parse test_uap_reality.json
```

### Reality 配置格式

```json
{
  "type": "uap",
  "tls": {
    "enabled": true,
    "reality": {
      "enabled": true,
      "handshake": {
        "server": "www.microsoft.com",
        "server_port": 443
      },
      "private_key": "your-private-key",
      "short_id": ["your-short-id"],
      "max_time_difference": "1m"
    }
  }
}
```

### Reality 测试要点

1. **Reality 配置保留**：验证 Reality 配置在解析后完整保留
2. **TLS Tricks 跳过**：Reality 模式下不应该应用 TLS tricks
3. **检测功能**：`isOutboundRealityFromMap` 函数能正确检测 Reality 状态

## 相关文件

- `config/outbound.go` - UAP 协议处理逻辑（包含 Reality 支持）
- `config/outbound_uap_test.go` - UAP 协议单元测试（包含 Reality 测试）
- `test_uap_config.json` - 基本 UAP 测试配置文件
- `test_uap_reality.json` - Reality UAP 测试配置文件（新增）
- `test_uap.sh` - 自动化测试脚本（已更新支持 Reality 测试）

