package config

import (
	"encoding/json"
	"fmt"
	"net"

	C "github.com/sagernet/sing-box/constant"
	"github.com/sagernet/sing-box/option"
)

type outboundMap map[string]interface{}

func patchOutboundMux(base option.Outbound, configOpt HiddifyOptions, obj outboundMap) outboundMap {
	if configOpt.Mux.Enable {
		multiplex := option.OutboundMultiplexOptions{
			Enabled:    true,
			Padding:    configOpt.Mux.Padding,
			MaxStreams: configOpt.Mux.MaxStreams,
			Protocol:   configOpt.Mux.Protocol,
		}
		obj["multiplex"] = multiplex
		// } else {
		// 	delete(obj, "multiplex")
	}
	return obj
}

func patchOutboundTLSTricks(base option.Outbound, configOpt HiddifyOptions, obj outboundMap) outboundMap {
	if base.Type == C.TypeSelector || base.Type == C.TypeURLTest || base.Type == C.TypeBlock || base.Type == C.TypeDNS {
		return obj
	}
	if isOutboundReality(base) {
		return obj
	}

	var tls *option.OutboundTLSOptions
	var transport *option.V2RayTransportOptions
	
	// Handle UAP protocol through JSON map (UAP is a sibling protocol of VLESS)
	if base.Type == "uap" {
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
						obj = patchOutboundFragment(base, configOpt, obj)
						tlsTricks := &option.TLSTricksOptions{}
						if existingTricks, ok := uapTls["tls_tricks"].(map[string]interface{}); ok {
							if mixedCase, ok := existingTricks["mixed_case_sni"].(bool); ok {
								tlsTricks.MixedCaseSNI = mixedCase
							}
						}
						tlsTricks.MixedCaseSNI = tlsTricks.MixedCaseSNI || configOpt.TLSTricks.MixedSNICase

						if configOpt.TLSTricks.EnablePadding {
							tlsTricks.PaddingMode = "random"
							tlsTricks.PaddingSize = configOpt.TLSTricks.PaddingSize
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
	
	if base.VLESSOptions.OutboundTLSOptionsContainer.TLS != nil {
		tls = base.VLESSOptions.OutboundTLSOptionsContainer.TLS
		transport = base.VLESSOptions.Transport
	} else if base.TrojanOptions.OutboundTLSOptionsContainer.TLS != nil {
		tls = base.TrojanOptions.OutboundTLSOptionsContainer.TLS
		transport = base.TrojanOptions.Transport
	} else if base.VMessOptions.OutboundTLSOptionsContainer.TLS != nil {
		tls = base.VMessOptions.OutboundTLSOptionsContainer.TLS
		transport = base.VMessOptions.Transport
	}
	if base.Type == C.TypeXray {
		if configOpt.TLSTricks.EnableFragment {
			if obj["xray_fragment"] == nil || obj["xray_fragment"].(map[string]any)["packets"] == "" {
				obj["xray_fragment"] = map[string]any{
					"packets":  "tlshello",
					"length":   configOpt.TLSTricks.FragmentSize,
					"interval": configOpt.TLSTricks.FragmentSleep,
				}
			}
		}
	}
	if base.Type == C.TypeDirect {
		return patchOutboundFragment(base, configOpt, obj)
	}

	if tls == nil || !tls.Enabled || transport == nil {
		return obj
	}

	if transport.Type != C.V2RayTransportTypeWebsocket && transport.Type != C.V2RayTransportTypeGRPC && transport.Type != C.V2RayTransportTypeHTTPUpgrade {
		return obj
	}

	if outtls, ok := obj["tls"].(map[string]interface{}); ok {
		obj = patchOutboundFragment(base, configOpt, obj)
		tlsTricks := tls.TLSTricks
		if tlsTricks == nil {
			tlsTricks = &option.TLSTricksOptions{}
		}
		tlsTricks.MixedCaseSNI = tlsTricks.MixedCaseSNI || configOpt.TLSTricks.MixedSNICase

		if configOpt.TLSTricks.EnablePadding {
			tlsTricks.PaddingMode = "random"
			tlsTricks.PaddingSize = configOpt.TLSTricks.PaddingSize
			// fmt.Printf("--------------------%+v----%+v", tlsTricks.PaddingSize, configOpt)
			outtls["utls"] = map[string]interface{}{
				"enabled":     true,
				"fingerprint": "custom",
			}
		}

		outtls["tls_tricks"] = tlsTricks
		// if tlsTricks.MixedCaseSNI || tlsTricks.PaddingMode != "" {
		// 	// } else {
		// 	// 	tls["tls_tricks"] = nil
		// }
		// fmt.Printf("-------%+v------------- ", tlsTricks)
	}
	return obj
}

func patchOutboundFragment(base option.Outbound, configOpt HiddifyOptions, obj outboundMap) outboundMap {
	if configOpt.TLSTricks.EnableFragment {
		obj["tcp_fast_open"] = false
		obj["tls_fragment"] = option.TLSFragmentOptions{
			Enabled: configOpt.TLSTricks.EnableFragment,
			Size:    configOpt.TLSTricks.FragmentSize,
			Sleep:   configOpt.TLSTricks.FragmentSleep,
		}

	}

	return obj
}

func isOutboundReality(base option.Outbound) bool {
	// this function checks reality status FOR VLESS and UAP.
	// Some other protocols can also use reality, but it's discouraged as stated in the reality document
	if base.Type == C.TypeVLESS {
		if base.VLESSOptions.OutboundTLSOptionsContainer.TLS == nil {
			return false
		}
		if base.VLESSOptions.OutboundTLSOptionsContainer.TLS.Reality == nil {
			return false
		}
		return base.VLESSOptions.OutboundTLSOptionsContainer.TLS.Reality.Enabled
	}
	// UAP is a sibling protocol of VLESS
	// Note: UAP Reality check is done through JSON map in patchOutboundTLSTricks
	// since UAPOptions might not be available in the struct yet
	return false
}

// isOutboundRealityFromMap checks Reality status from JSON map (for UAP protocol)
func isOutboundRealityFromMap(obj outboundMap) bool {
	if tls, ok := obj["tls"].(map[string]interface{}); ok {
		if reality, ok := tls["reality"].(map[string]interface{}); ok {
			if enabled, ok := reality["enabled"].(bool); ok {
				return enabled
			}
		}
	}
	return false
}

func patchOutbound(base option.Outbound, configOpt HiddifyOptions, staticIpsDns map[string][]string) (*option.Outbound, string, error) {
	formatErr := func(err error) error {
		return fmt.Errorf("error patching outbound[%s][%s]: %w", base.Tag, base.Type, err)
	}
	err := patchWarp(&base, &configOpt, true, staticIpsDns)
	if err != nil {
		return nil, "", formatErr(err)
	}
	var outbound option.Outbound

	jsonData, err := base.MarshalJSON()
	if err != nil {
		return nil, "", formatErr(err)
	}

	var obj outboundMap
	err = json.Unmarshal(jsonData, &obj)
	if err != nil {
		return nil, "", formatErr(err)
	}
	var serverDomain string
	if detour, ok := obj["detour"].(string); !ok || detour == "" {
		if server, ok := obj["server"].(string); ok {
			if server != "" && net.ParseIP(server) == nil {
				serverDomain = fmt.Sprintf("full:%s", server)
			}
		}
	}

	obj = patchOutboundTLSTricks(base, configOpt, obj)

	switch base.Type {
	case C.TypeVMess, C.TypeVLESS, C.TypeTrojan, C.TypeShadowsocks:
		obj = patchOutboundMux(base, configOpt, obj)
	case "uap":
		// UAP is a sibling protocol of VLESS, support Mux
		obj = patchOutboundMux(base, configOpt, obj)
	}

	modifiedJson, err := json.Marshal(obj)
	if err != nil {
		return nil, "", formatErr(err)
	}

	err = outbound.UnmarshalJSON(modifiedJson)
	if err != nil {
		return nil, "", formatErr(err)
	}

	return &outbound, serverDomain, nil
}

// func (o outboundMap) transportType() string {
// 	if transport, ok := o["transport"].(map[string]interface{}); ok {
// 		if transportType, ok := transport["type"].(string); ok {
// 			return transportType
// 		}
// 	}
// 	return ""
// }
