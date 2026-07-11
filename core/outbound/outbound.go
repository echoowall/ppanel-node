package outbound

import (
	"encoding/json"
	"fmt"

	"github.com/xtls/xray-core/core"
	coreConf "github.com/xtls/xray-core/infra/conf"
)

// build default freedom outbund
func buildDefaultOutbound() (*core.OutboundHandlerConfig, error) {
	outboundDetourConfig := &coreConf.OutboundDetourConfig{}
	outboundDetourConfig.Protocol = "freedom"
	outboundDetourConfig.Tag = DefaultTag
	// Source-in-source-out: bind the outbound source IP to the local IP the
	// client connected to (for host-network multi-IP servers). Relies on the
	// xray-core "origin" sendThrough, whose UDP handling was fixed in
	// xtls/xray-core#5030 (v25.8.29).
	//
	// For XHTTP (splithttp) inbounds this also requires the xray-core fork to
	// derive the connection's local address per-request (LocalAddrContextKey)
	// rather than from the listener's wildcard address; without that fix a
	// wildcard "[::]" listener collapses every entry IP onto one (often IPv6)
	// source. The pinned echoowall/xray-core replace carries that patch.
	sendthrough := "origin"
	outboundDetourConfig.SendThrough = &sendthrough

	proxySetting := &coreConf.FreedomConfig{
		DomainStrategy: "UseIPv4v6",
	}
	var setting json.RawMessage
	setting, err := json.Marshal(proxySetting)
	if err != nil {
		return nil, fmt.Errorf("marshal proxy config error: %s", err)
	}
	outboundDetourConfig.Settings = &setting
	return outboundDetourConfig.Build()
}

// build block outbund
func buildBlockOutbound() (*core.OutboundHandlerConfig, error) {
	outboundDetourConfig := &coreConf.OutboundDetourConfig{}
	outboundDetourConfig.Protocol = "blackhole"
	outboundDetourConfig.Tag = BlockTag
	return outboundDetourConfig.Build()
}

// build dns outbound
func buildDnsOutbound() (*core.OutboundHandlerConfig, error) {
	outboundDetourConfig := &coreConf.OutboundDetourConfig{}
	outboundDetourConfig.Protocol = "dns"
	outboundDetourConfig.Tag = DNSTag
	return outboundDetourConfig.Build()
}
