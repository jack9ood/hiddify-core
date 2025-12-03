# 使用 hiddify-cli 测试 UAP + Reality

项目已内置 sing-box 功能，无需安装外部 sing-box 命令即可测试 UAP + Reality 配置。

## 快速开始

### 方法 1: 使用测试脚本（推荐）

```bash
cd test

# 1. 准备配置文件
cp test_uap_reality_full.json my_config.json
# 编辑 my_config.json，替换占位符

# 2. 运行连接测试（自动启动和测试）
./test_uap_connection.sh my_config.json
```

### 方法 2: 手动运行

```bash
# 1. 生成配置
./bin/hiddify-cli parse test/test_uap_reality_full.json > test/output.json

# 2. 运行代理服务
./bin/hiddify-cli run --config test/output.json
```

## 配置说明

### 使用包含 inbound 的完整配置

如果配置文件包含 `inbounds`（如 `test_uap_reality_full.json`），可以直接使用：

```bash
./bin/hiddify-cli run --config test/test_uap_reality_full.json
```

### 使用只有 outbounds 的配置

如果配置文件只有 `outbounds`，`hiddify-cli run` 会自动添加默认的 inbound：

```bash
# 默认会添加 mixed inbound，监听端口 2334
./bin/hiddify-cli run --config test/test_uap_reality.json --in-proxy-port 2334
```

## 测试连接

启动服务后，在另一个终端测试：

```bash
# 默认端口是 2334
curl --proxy socks5://127.0.0.1:2334 https://www.google.com
curl --proxy socks5://127.0.0.1:2334 https://api.ipify.org
```

## 修改监听端口

```bash
./bin/hiddify-cli run --config test/output.json --in-proxy-port 1080
```

## 优势

使用项目内置的 `hiddify-cli run` 的优势：

1. ✅ **无需安装外部工具**：项目已包含 sing-box 库
2. ✅ **自动支持 uTLS**：项目使用的 `github.com/jack9ood/hiddify-sing-box` 已包含 uTLS 支持
3. ✅ **自动添加配置**：会自动添加 inbound、DNS、路由等配置
4. ✅ **统一管理**：使用项目统一的配置管理

## 与外部 sing-box 的区别

- **外部 sing-box**：需要单独安装，可能需要编译时包含 `-tags with_utls`
- **hiddify-cli run**：使用项目内置库，已包含所有必要的功能

## 故障排除

如果连接失败：

1. **检查配置**：
   ```bash
   ./bin/hiddify-cli parse test/my_config.json
   ```

2. **查看日志**：
   ```bash
   # hiddify-cli run 会输出日志到控制台
   # 检查是否有错误信息
   ```

3. **验证服务器**：
   - 确保服务器 IP、UUID、public_key、short_id 正确
   - 检查服务器防火墙是否开放 443 端口

4. **测试基本连接**：
   ```bash
   # 先测试服务器是否可达
   ping YOUR_SERVER_IP
   telnet YOUR_SERVER_IP 443
   ```

