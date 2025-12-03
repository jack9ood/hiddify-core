# UAP + Reality 伪装测试指南

本指南说明如何测试 UAP 协议是否真正可以带伪装（Reality）使用。

## 前置要求

1. **服务器端配置**：
   - 已部署支持 UAP + Reality 的服务器
   - 获取以下信息：
     - 服务器 IP 地址
     - UAP UUID
     - Reality 公钥（public_key）
     - Reality short_id

2. **客户端环境**：
   - 已编译的 `hiddify-cli`
   - 可选：安装 `sing-box` 用于实际运行测试

## 测试步骤

### 步骤 1: 准备配置文件

1. 复制模板配置文件：
   ```bash
   cp test_uap_reality_full.json my_uap_reality_config.json
   ```

2. 编辑配置文件，替换以下占位符：
   - `YOUR_SERVER_IP`: 服务器 IP 地址
   - `YOUR_UUID`: UAP 协议的 UUID
   - `YOUR_PUBLIC_KEY`: Reality 的公钥（从服务器获取）
   - `YOUR_SHORT_ID`: Reality 的 short_id（从服务器获取）

### 步骤 2: 运行测试脚本

```bash
./test_uap_reality.sh my_uap_reality_config.json
```

测试脚本会：
1. ✅ 验证配置格式
2. ✅ 检查 Reality 配置
3. ✅ 生成完整的 sing-box 配置
4. ✅ 验证配置是否可以启动

### 步骤 3: 实际运行测试

#### 方法 1: 使用 sing-box 直接运行

```bash
# 生成配置
./bin/hiddify-cli parse my_uap_reality_config.json > output.json

# 运行 sing-box
sing-box run -c output.json
```

#### 方法 2: 使用 hiddify-cli build

```bash
# 构建配置
./bin/hiddify-cli build -c my_uap_reality_config.json -o output.json

# 运行 sing-box
sing-box run -c output.json
```

### 步骤 4: 测试连接

在另一个终端中测试连接：

```bash
# 测试 HTTP 连接
curl --proxy socks5://127.0.0.1:1080 https://www.google.com

# 测试 IP 检查
curl --proxy socks5://127.0.0.1:1080 https://api.ipify.org

# 使用代理测试浏览器
# 设置 SOCKS5 代理: 127.0.0.1:1080
```

### 步骤 5: 验证伪装效果

#### 5.1 检查 TLS 握手

在服务器端使用 tcpdump 抓包：

```bash
# 在服务器上运行
sudo tcpdump -i any -A -s 0 'tcp port 443' | grep -i "server_name\|sni"
```

应该看到：
- SNI (Server Name Indication) 为 `www.microsoft.com`（伪装目标）
- 而不是实际的服务器域名

#### 5.2 检查流量特征

使用 Wireshark 分析：
1. 打开抓包文件
2. 过滤 `tls.handshake.extensions_server_name`
3. 检查 SNI 字段是否为伪装目标

#### 5.3 在线验证

访问以下网站验证：
- https://www.whatismyip.com/ - 检查 IP 是否为服务器 IP
- https://browserleaks.com/ssl - 检查 TLS 指纹和 SNI
- https://www.dnsleaktest.com/ - 检查 DNS 泄漏

### 步骤 6: 验证 Reality 配置

检查生成的配置文件中 Reality 部分：

```json
{
  "tls": {
    "enabled": true,
    "reality": {
      "enabled": true,
      "public_key": "你的公钥",
      "short_id": "你的short_id"
    }
  }
}
```

**重要**：
- ✅ 客户端配置应该包含 `public_key`（不是 `private_key`）
- ✅ 客户端配置应该包含 `short_id`
- ✅ 不应该包含 `handshake`、`private_key`、`max_time_difference`（这些是服务器端配置）

## 故障排除

### 问题 1: 连接失败

**可能原因**：
- Reality 配置错误（public_key 或 short_id 不正确）
- UUID 不正确
- 服务器防火墙未开放端口
- 服务器端未正确配置

**解决方法**：
1. 检查服务器端日志
2. 验证 public_key 和 short_id 是否正确
3. 确认 UUID 匹配
4. 检查服务器防火墙规则

### 问题 2: 配置解析失败

**可能原因**：
- 配置文件格式错误
- 缺少必需字段

**解决方法**：
```bash
# 检查配置格式
./bin/hiddify-cli parse my_uap_reality_config.json
```

### 问题 3: TLS 握手失败

**可能原因**：
- Reality 配置不匹配
- 服务器端 Reality 配置错误

**解决方法**：
1. 确认服务器端和客户端的 public_key 匹配
2. 确认 short_id 正确
3. 检查服务器端 Reality 配置

### 问题 4: 流量未被伪装

**验证方法**：
1. 使用 tcpdump 检查 SNI
2. 使用 Wireshark 分析 TLS 握手
3. 检查是否显示为伪装目标网站

## 测试检查清单

- [ ] 配置文件格式正确
- [ ] Reality 配置存在且正确
- [ ] public_key 和 short_id 已填写
- [ ] 配置可以成功解析
- [ ] sing-box 可以启动
- [ ] 可以建立连接
- [ ] IP 地址正确（服务器 IP）
- [ ] TLS 握手成功
- [ ] SNI 显示为伪装目标
- [ ] 流量可以正常传输

## 示例配置

完整的 UAP + Reality 配置示例：

```json
{
  "outbounds": [
    {
      "type": "uap",
      "tag": "uap-reality",
      "server": "1.2.3.4",
      "server_port": 443,
      "uuid": "12345678-1234-1234-1234-123456789abc",
      "flow": "",
      "tls": {
        "enabled": true,
        "server_name": "www.microsoft.com",
        "reality": {
          "enabled": true,
          "public_key": "你的公钥（base64编码）",
          "short_id": "你的short_id"
        }
      },
      "transport": {
        "type": "tcp"
      }
    }
  ]
}
```

## 相关文件

- `test_uap_reality_full.json` - 完整测试配置模板
- `test_uap_reality.sh` - 自动化测试脚本
- `test_uap_reality.json` - 简单配置示例

## 注意事项

1. **安全性**：
   - 不要在公共仓库中提交包含真实密钥的配置文件
   - 使用环境变量或配置文件管理敏感信息

2. **服务器端配置**：
   - 确保服务器端已正确配置 UAP + Reality
   - 服务器端需要 `private_key`，客户端需要 `public_key`

3. **网络环境**：
   - 某些网络环境可能阻止 Reality 流量
   - 如果连接失败，尝试更换伪装目标网站

