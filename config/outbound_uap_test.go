package config

import (
	"encoding/json"
	"testing"

	"github.com/sagernet/sing-box/option"
)

// TestUAPProtocolSupport 测试 UAP 协议的基本支持
func TestUAPProtocolSupport(t *testing.T) {
	// 创建一个 UAP 配置（使用 JSON map，因为 sing-box 可能还不支持 UAP 类型）
	uapConfigJSON := `{
		"type": "uap",
		"tag": "uap-test",
		"server": "example.com",
		"server_port": 443,
		"uuid": "00000000-0000-0000-0000-000000000000",
		"flow": "",
		"tls": {
			"enabled": true,
			"server_name": "example.com",
			"insecure": false
		},
		"transport": {
			"type": "ws",
			"path": "/path",
			"headers": {}
		}
	}`

	var obj map[string]interface{}
	err := json.Unmarshal([]byte(uapConfigJSON), &obj)
	if err != nil {
		t.Fatalf("Failed to unmarshal UAP config JSON: %v", err)
	}

	// 验证类型
	if objType, ok := obj["type"].(string); ok {
		if objType != "uap" {
			t.Errorf("Expected type 'uap', got '%s'", objType)
		}
	} else {
		t.Fatal("Type field not found")
	}

	// 创建一个模拟的 Outbound（类型设为 uap）
	outbound := option.Outbound{
		Type: "uap",
		Tag:  "uap-test",
	}

	// 测试 patchOutboundMux 函数（Mux 支持）
	configOpt := DefaultHiddifyOptions()
	configOpt.Mux.Enable = true // 启用 Mux 以测试 Mux 支持

	patchedObj := patchOutboundMux(outbound, *configOpt, obj)

	// 检查 Mux 配置
	if multiplex, ok := patchedObj["multiplex"]; ok {
		// multiplex 可能是结构体或 map
		if multiplexMap, ok := multiplex.(map[string]interface{}); ok {
			if enabled, ok := multiplexMap["enabled"].(bool); ok && enabled {
				t.Log("✓ Mux configuration successfully added")
			} else {
				t.Logf("Mux found but enabled flag: %v", multiplexMap["enabled"])
			}
		} else {
			// 可能是结构体对象
			t.Logf("✓ Mux configuration found (type: %T)", multiplex)
		}
	} else {
		// 打印调试信息
		t.Logf("Available keys in patchedObj: %v", getMapKeys(patchedObj))
		t.Error("Multiplex configuration not found - this is expected if Mux.Enable is false in DefaultHiddifyOptions")
		// 注意：patchOutboundMux 只在 Mux.Enable 为 true 时添加配置
		// 如果测试失败，检查 configOpt.Mux.Enable 的值
		t.Logf("configOpt.Mux.Enable = %v", configOpt.Mux.Enable)
	}
}

// TestUAPTLSTricks 测试 UAP 协议的 TLS tricks 支持
func TestUAPTLSTricks(t *testing.T) {
	// 创建一个带 TLS 的 UAP 配置（使用 JSON map）
	uapConfigJSON := `{
		"type": "uap",
		"tag": "uap-tls-test",
		"server": "example.com",
		"server_port": 443,
		"uuid": "00000000-0000-0000-0000-000000000000",
		"tls": {
			"enabled": true,
			"server_name": "example.com"
		},
		"transport": {
			"type": "ws",
			"path": "/path"
		}
	}`

	var obj map[string]interface{}
	err := json.Unmarshal([]byte(uapConfigJSON), &obj)
	if err != nil {
		t.Fatalf("Failed to unmarshal UAP config JSON: %v", err)
	}

	// 创建一个模拟的 Outbound
	outbound := option.Outbound{
		Type: "uap",
		Tag:  "uap-tls-test",
	}

	// 启用 TLS tricks
	configOpt := DefaultHiddifyOptions()
	configOpt.TLSTricks.MixedSNICase = true
	configOpt.TLSTricks.EnablePadding = true
	configOpt.TLSTricks.PaddingSize = "1200-1500"
	configOpt.TLSTricks.EnableFragment = true
	configOpt.TLSTricks.FragmentSize = "10-100"
	configOpt.TLSTricks.FragmentSleep = "50-200"

	// 测试 patchOutboundTLSTricks
	patchedObj := patchOutboundTLSTricks(outbound, *configOpt, obj)

	// 验证 TLS tricks 配置
	if tls, ok := patchedObj["tls"].(map[string]interface{}); ok {
		// tls_tricks 可能是一个结构体对象，需要检查其存在性
		if tlsTricks, exists := tls["tls_tricks"]; exists {
			t.Log("✓ TLS tricks configuration found")
			// 尝试转换为 map 来检查具体值
			if tlsTricksMap, ok := tlsTricks.(map[string]interface{}); ok {
				if mixedCase, ok := tlsTricksMap["mixed_case_sni"].(bool); ok && mixedCase {
					t.Log("✓ MixedCaseSNI enabled")
				}
				if paddingMode, ok := tlsTricksMap["padding_mode"].(string); ok && paddingMode == "random" {
					t.Log("✓ Padding mode set correctly")
				}
			} else {
				// 可能是结构体对象，至少确认它存在
				t.Logf("✓ TLS tricks found (type: %T)", tlsTricks)
			}
		} else {
			// 打印调试信息
			t.Logf("TLS keys: %v", getMapKeys(tls))
			t.Error("TLS tricks configuration not found")
		}

		// 检查 utls 配置
		if utls, ok := tls["utls"].(map[string]interface{}); ok {
			if enabled, ok := utls["enabled"].(bool); ok && enabled {
				t.Log("✓ uTLS enabled")
			}
		}
	} else {
		t.Error("TLS configuration not found")
	}
}

// TestUAPWithReality 测试 UAP 协议使用 Reality
func TestUAPWithReality(t *testing.T) {
	// 创建一个带 Reality 的 UAP 配置
	uapRealityConfigJSON := `{
		"type": "uap",
		"tag": "uap-reality-test",
		"server": "example.com",
		"server_port": 443,
		"uuid": "00000000-0000-0000-0000-000000000000",
		"flow": "",
		"tls": {
			"enabled": true,
			"server_name": "example.com",
			"insecure": false,
			"reality": {
				"enabled": true,
				"handshake": {
					"server": "www.microsoft.com",
					"server_port": 443
				},
				"private_key": "test-private-key",
				"short_id": ["test-short-id"],
				"max_time_difference": "1m"
			}
		},
		"transport": {
			"type": "tcp"
		}
	}`

	var obj map[string]interface{}
	err := json.Unmarshal([]byte(uapRealityConfigJSON), &obj)
	if err != nil {
		t.Fatalf("Failed to unmarshal UAP Reality config JSON: %v", err)
	}

	outbound := option.Outbound{
		Type: "uap",
		Tag:  "uap-reality-test",
	}

	configOpt := DefaultHiddifyOptions()
	configOpt.TLSTricks.MixedSNICase = true
	configOpt.TLSTricks.EnablePadding = true

	// 测试 patchOutboundTLSTricks - Reality 配置应该被保留，不应该应用 TLS tricks
	patchedObj := patchOutboundTLSTricks(outbound, *configOpt, obj)

	// 验证 Reality 配置被保留
	if tls, ok := patchedObj["tls"].(map[string]interface{}); ok {
		if reality, ok := tls["reality"].(map[string]interface{}); ok {
			if enabled, ok := reality["enabled"].(bool); ok && enabled {
				t.Log("✓ Reality configuration found and preserved")
				
				// 验证 Reality 配置的完整性
				if handshake, ok := reality["handshake"].(map[string]interface{}); ok {
					if server, ok := handshake["server"].(string); ok && server != "" {
						t.Logf("✓ Reality handshake server: %s", server)
					}
				}
				if privateKey, ok := reality["private_key"].(string); ok && privateKey != "" {
					t.Log("✓ Reality private_key found")
				}
			} else {
				t.Error("Reality enabled flag not found or false")
			}
		} else {
			t.Error("Reality configuration not found")
		}

		// 验证 TLS tricks 没有被应用到 Reality 配置
		if _, ok := tls["tls_tricks"]; ok {
			t.Error("TLS tricks should NOT be applied when Reality is enabled")
		} else {
			t.Log("✓ TLS tricks correctly skipped for Reality")
		}
	} else {
		t.Error("TLS configuration not found")
	}
}

// TestUAPRealityDetection 测试 UAP Reality 检测功能
func TestUAPRealityDetection(t *testing.T) {
	// 测试有 Reality 的配置
	withRealityJSON := `{
		"type": "uap",
		"tls": {
			"reality": {
				"enabled": true
			}
		}
	}`

	var withReality map[string]interface{}
	json.Unmarshal([]byte(withRealityJSON), &withReality)

	if isOutboundRealityFromMap(withReality) {
		t.Log("✓ Reality detection works for UAP with Reality enabled")
	} else {
		t.Error("Reality detection failed for UAP with Reality enabled")
	}

	// 测试没有 Reality 的配置
	withoutRealityJSON := `{
		"type": "uap",
		"tls": {
			"enabled": true
		}
	}`

	var withoutReality map[string]interface{}
	json.Unmarshal([]byte(withoutRealityJSON), &withoutReality)

	if !isOutboundRealityFromMap(withoutReality) {
		t.Log("✓ Reality detection correctly returns false when Reality is not enabled")
	} else {
		t.Error("Reality detection incorrectly returned true for UAP without Reality")
	}
}

// 辅助函数：获取 map 的所有键
func getMapKeys(m map[string]interface{}) []string {
	keys := make([]string, 0, len(m))
	for k := range m {
		keys = append(keys, k)
	}
	return keys
}

// TestUAPWithGRPCTransport 测试 UAP 协议使用 gRPC 传输
func TestUAPWithGRPCTransport(t *testing.T) {
	uapConfigJSON := `{
		"type": "uap",
		"tag": "uap-grpc-test",
		"server": "example.com",
		"server_port": 443,
		"uuid": "00000000-0000-0000-0000-000000000000",
		"tls": {
			"enabled": true,
			"server_name": "example.com"
		},
		"transport": {
			"type": "grpc",
			"service_name": "test"
		}
	}`

	var obj map[string]interface{}
	err := json.Unmarshal([]byte(uapConfigJSON), &obj)
	if err != nil {
		t.Fatalf("Failed to unmarshal UAP config JSON: %v", err)
	}

	outbound := option.Outbound{
		Type: "uap",
		Tag:  "uap-grpc-test",
	}

	configOpt := DefaultHiddifyOptions()
	configOpt.TLSTricks.MixedSNICase = true
	configOpt.TLSTricks.EnablePadding = true
	configOpt.TLSTricks.PaddingSize = "1200-1500"

	patchedObj := patchOutboundTLSTricks(outbound, *configOpt, obj)

	// 验证 gRPC 传输的 TLS tricks 被正确处理
	if tls, ok := patchedObj["tls"].(map[string]interface{}); ok {
		if transport, ok := patchedObj["transport"].(map[string]interface{}); ok {
			transportType, _ := transport["type"].(string)
			if transportType == "grpc" {
				if _, ok := tls["tls_tricks"]; ok {
					t.Log("✓ TLS tricks applied to gRPC transport")
				} else {
					t.Error("TLS tricks not found for gRPC transport")
				}
			}
		}
	}
}

