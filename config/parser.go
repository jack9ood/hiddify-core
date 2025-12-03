package config

import (
	"bytes"
	"context"
	_ "embed"
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"

	"github.com/hiddify/ray2sing/ray2sing"
	"github.com/sagernet/sing-box/experimental/libbox"
	C "github.com/sagernet/sing-box/constant"
	"github.com/sagernet/sing-box/option"
	"github.com/sagernet/sing/common/batch"
	SJ "github.com/sagernet/sing/common/json"
	"github.com/xmdhs/clash2singbox/convert"
	"github.com/xmdhs/clash2singbox/model/clash"
	"gopkg.in/yaml.v3"
)

//go:embed config.json.template
var configByte []byte

func ParseConfig(path string, debug bool) ([]byte, error) {
	content, err := os.ReadFile(path)
	os.Chdir(filepath.Dir(path))
	if err != nil {
		return nil, err
	}
	return ParseConfigContent(string(content), debug, nil, false)
}

func ParseConfigContentToOptions(contentstr string, debug bool, configOpt *HiddifyOptions, fullConfig bool) (*option.Options, error) {
	content, err := ParseConfigContent(contentstr, debug, configOpt, fullConfig)
	if err != nil {
		return nil, err
	}
	var options option.Options
	err = json.Unmarshal(content, &options)
	if err != nil {
		return nil, err
	}
	return &options, nil
}

func ParseConfigContent(contentstr string, debug bool, configOpt *HiddifyOptions, fullConfig bool) ([]byte, error) {
	if configOpt == nil {
		configOpt = DefaultHiddifyOptions()
	}
	content := []byte(contentstr)
	var jsonObj map[string]interface{} = make(map[string]interface{})

	fmt.Printf("Convert using json\n")
	var tmpJsonResult any
	jsonDecoder := json.NewDecoder(SJ.NewCommentFilter(bytes.NewReader(content)))
	if err := jsonDecoder.Decode(&tmpJsonResult); err == nil {
		if tmpJsonObj, ok := tmpJsonResult.(map[string]interface{}); ok {
			if tmpJsonObj["outbounds"] == nil {
				jsonObj["outbounds"] = []interface{}{jsonObj}
			} else {
				if fullConfig || (configOpt != nil && configOpt.EnableFullConfig) {
					jsonObj = tmpJsonObj
				} else {
					jsonObj["outbounds"] = tmpJsonObj["outbounds"]
				}
			}
		} else if jsonArray, ok := tmpJsonResult.([]map[string]interface{}); ok {
			jsonObj["outbounds"] = jsonArray
		} else {
			return nil, fmt.Errorf("[SingboxParser] Incorrect Json Format")
		}

		newContent, _ := json.MarshalIndent(jsonObj, "", "  ")

		return patchConfig(newContent, "SingboxParser", configOpt)
	}

	v2rayStr, err := ray2sing.Ray2Singbox(string(content), configOpt.UseXrayCoreWhenPossible)
	if err == nil {
		return patchConfig([]byte(v2rayStr), "V2rayParser", configOpt)
	}
	fmt.Printf("Convert using clash\n")
	clashObj := clash.Clash{}
	if err := yaml.Unmarshal(content, &clashObj); err == nil && clashObj.Proxies != nil {
		if len(clashObj.Proxies) == 0 {
			return nil, fmt.Errorf("[ClashParser] no outbounds found")
		}
		converted, err := convert.Clash2sing(clashObj)
		if err != nil {
			return nil, fmt.Errorf("[ClashParser] converting clash to sing-box error: %w", err)
		}
		output := configByte
		output, err = convert.Patch(output, converted, "", "", nil)
		if err != nil {
			return nil, fmt.Errorf("[ClashParser] patching clash config error: %w", err)
		}
		return patchConfig(output, "ClashParser", configOpt)
	}

	return nil, fmt.Errorf("unable to determine config format")
}

func patchConfig(content []byte, name string, configOpt *HiddifyOptions) ([]byte, error) {
	var jsonObj map[string]interface{}
	err := json.Unmarshal(content, &jsonObj)
	if err != nil {
		return nil, fmt.Errorf("[SingboxParser] unmarshal error: %w", err)
	}

	// Separate UAP outbounds from regular outbounds
	var uapOutbounds []map[string]interface{}
	var regularOutbounds []interface{}
	
	if outbounds, ok := jsonObj["outbounds"].([]interface{}); ok {
		for _, outbound := range outbounds {
			if outboundMap, ok := outbound.(map[string]interface{}); ok {
				if outboundType, ok := outboundMap["type"].(string); ok && outboundType == "uap" {
					// Clean up UAP Reality configuration: remove unsupported fields (same as VLESS handling)
					if tls, ok := outboundMap["tls"].(map[string]interface{}); ok {
						if reality, ok := tls["reality"].(map[string]interface{}); ok {
							// Remove unsupported fields for sing-box option parsing
							delete(reality, "handshake")
							delete(reality, "max_time_difference")
							// Remove private_key (server-side only, not supported in outbound)
							if _, hasPrivateKey := reality["private_key"]; hasPrivateKey {
								delete(reality, "private_key")
							}
							// Convert short_id array to string if needed
							if shortIDArray, ok := reality["short_id"].([]interface{}); ok && len(shortIDArray) > 0 {
								if shortIDStr, ok := shortIDArray[0].(string); ok {
									reality["short_id"] = shortIDStr
								}
							}
						}
					}
					// Remove "tcp" transport type (default, not needed in config)
					if transport, ok := outboundMap["transport"].(map[string]interface{}); ok {
						if transportType, ok := transport["type"].(string); ok && transportType == "tcp" {
							delete(outboundMap, "transport")
						}
					}
					uapOutbounds = append(uapOutbounds, outboundMap)
				} else {
					regularOutbounds = append(regularOutbounds, outbound)
				}
			}
		}
	}

	// Process regular outbounds through option.Options
	var options option.Options
	if len(regularOutbounds) > 0 {
		// Create a temporary JSON object with only regular outbounds
		tempJsonObj := make(map[string]interface{})
		for k, v := range jsonObj {
			if k != "outbounds" {
				tempJsonObj[k] = v
			}
		}
		tempJsonObj["outbounds"] = regularOutbounds
		
		modifiedContent, err := json.Marshal(tempJsonObj)
		if err != nil {
			return nil, fmt.Errorf("[SingboxParser] marshal error: %w", err)
		}

		err = json.Unmarshal(modifiedContent, &options)
		if err != nil {
			return nil, fmt.Errorf("[SingboxParser] unmarshal error: %w", err)
		}

		// Process regular outbounds
		b, _ := batch.New(context.Background(), batch.WithConcurrencyNum[*option.Outbound](2))
		for _, base := range options.Outbounds {
			out := base
			b.Go(base.Tag, func() (*option.Outbound, error) {
				err := patchWarp(&out, configOpt, false, nil)
				if err != nil {
					return nil, fmt.Errorf("[Warp] patch warp error: %w", err)
				}
				return &out, nil
			})
		}
		if res, err := b.WaitAndGetResult(); err != nil {
			return nil, err
		} else {
			for i, base := range options.Outbounds {
				options.Outbounds[i] = *res[base.Tag].Value
			}
		}
	}

	// Process UAP outbounds separately using JSON map manipulation
	for i := range uapOutbounds {
		// Create a temporary Outbound struct for processing
		tempOutbound := option.Outbound{
			Type: "uap",
			Tag:  getStringFromMap(uapOutbounds[i], "tag"),
		}

		// Apply TLS tricks and Mux patches using JSON map manipulation
		uapOutbounds[i] = patchOutboundTLSTricksForMap(tempOutbound, *configOpt, uapOutbounds[i])
		uapOutbounds[i] = patchOutboundMuxForMap(tempOutbound, *configOpt, uapOutbounds[i])
	}

	// Marshal options to JSON
	content, err = json.MarshalIndent(options, "", "  ")
	if err != nil {
		return nil, fmt.Errorf("[SingboxParser] marshal options error: %w", err)
	}

	// Merge UAP outbounds into the final JSON output
	if len(uapOutbounds) > 0 {
		var finalJsonObj map[string]interface{}
		if err := json.Unmarshal(content, &finalJsonObj); err != nil {
			return nil, fmt.Errorf("[SingboxParser] unmarshal final JSON error: %w", err)
		}
		if existingOutbounds, ok := finalJsonObj["outbounds"].([]interface{}); ok {
			// Add UAP outbounds as raw JSON objects
			for _, uapOutbound := range uapOutbounds {
				existingOutbounds = append(existingOutbounds, uapOutbound)
			}
			finalJsonObj["outbounds"] = existingOutbounds
			content, err = json.MarshalIndent(finalJsonObj, "", "  ")
			if err != nil {
				return nil, fmt.Errorf("[SingboxParser] marshal final JSON error: %w", err)
			}
		} else {
			// If outbounds doesn't exist, create it
			finalJsonObj["outbounds"] = uapOutbounds
			content, err = json.MarshalIndent(finalJsonObj, "", "  ")
			if err != nil {
				return nil, fmt.Errorf("[SingboxParser] marshal final JSON error: %w", err)
			}
		}
	}

	fmt.Printf("%s\n", content)
	return validateResult(content, name)
}

// Helper function to get string value from map
func getStringFromMap(m map[string]interface{}, key string) string {
	if val, ok := m[key].(string); ok {
		return val
	}
	return ""
}

// patchOutboundTLSTricksForMap processes TLS tricks for UAP outbound using JSON map
func patchOutboundTLSTricksForMap(base option.Outbound, configOpt HiddifyOptions, obj outboundMap) outboundMap {
	if base.Type != "uap" {
		return obj
	}

	// Check if UAP uses Reality (Reality should skip TLS tricks)
	if isOutboundRealityFromMap(obj) {
		return obj
	}

	if uapTls, ok := obj["tls"].(map[string]interface{}); ok {
		if enabled, ok := uapTls["enabled"].(bool); ok && enabled {
			// UAP has TLS enabled, process it
			if uapTransport, ok := obj["transport"].(map[string]interface{}); ok {
				transportType, _ := uapTransport["type"].(string)
				if transportType == C.V2RayTransportTypeWebsocket || transportType == C.V2RayTransportTypeGRPC || transportType == C.V2RayTransportTypeHTTPUpgrade {
					// Process UAP TLS tricks
					obj = patchOutboundFragmentForMap(base, configOpt, obj)
					tlsTricks := map[string]interface{}{}
					mixedCaseSNI := false
					if existingTricks, ok := uapTls["tls_tricks"].(map[string]interface{}); ok {
						if mixedCase, ok := existingTricks["mixed_case_sni"].(bool); ok {
							mixedCaseSNI = mixedCase
							tlsTricks["mixed_case_sni"] = mixedCase
						}
					}
					if !mixedCaseSNI && configOpt.TLSTricks.MixedSNICase {
						tlsTricks["mixed_case_sni"] = true
					}

					if configOpt.TLSTricks.EnablePadding {
						tlsTricks["padding_mode"] = "random"
						tlsTricks["padding_size"] = configOpt.TLSTricks.PaddingSize
						uapTls["utls"] = map[string]interface{}{
							"enabled":     true,
							"fingerprint": "custom",
						}
					}

					uapTls["tls_tricks"] = tlsTricks
					obj["tls"] = uapTls
				}
			}
		}
	}
	return obj
}

// patchOutboundMuxForMap processes Mux for UAP outbound using JSON map
func patchOutboundMuxForMap(base option.Outbound, configOpt HiddifyOptions, obj outboundMap) outboundMap {
	if base.Type != "uap" {
		return obj
	}

	if configOpt.Mux.Enable {
		multiplex := map[string]interface{}{
			"enabled":     true,
			"padding":     configOpt.Mux.Padding,
			"max_streams": configOpt.Mux.MaxStreams,
			"protocol":    configOpt.Mux.Protocol,
		}
		obj["multiplex"] = multiplex
	}
	return obj
}

// patchOutboundFragmentForMap processes Fragment for UAP outbound using JSON map
func patchOutboundFragmentForMap(base option.Outbound, configOpt HiddifyOptions, obj outboundMap) outboundMap {
	if configOpt.TLSTricks.EnableFragment {
		obj["tcp_fast_open"] = false
		obj["tls_fragment"] = map[string]interface{}{
			"enabled": configOpt.TLSTricks.EnableFragment,
			"size":    configOpt.TLSTricks.FragmentSize,
			"sleep":   configOpt.TLSTricks.FragmentSleep,
		}
	}
	return obj
}

func validateResult(content []byte, name string) ([]byte, error) {
	// github.com/jack9ood/hiddify-sing-box 的 main 分支已经全面支持 UAP 协议
	// 包括 libbox.CheckConfig 验证函数，可以直接进行验证
	err := libbox.CheckConfig(string(content))
	if err != nil {
		return nil, fmt.Errorf("[%s] invalid sing-box config: %w", name, err)
	}
	return content, nil
}

