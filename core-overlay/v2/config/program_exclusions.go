package config

import (
	"fmt"
	"regexp"
	"strings"

	C "github.com/sagernet/sing-box/constant"
	"github.com/sagernet/sing-box/option"
)

var windowsAbsoluteExecutable = regexp.MustCompile(`(?i)^(?:[a-z]:\\|\\\\[^\\]+\\[^\\]+\\).+\.exe$`)

// Match the entire path, case-insensitively, without treating characters in
// filenames as regular expressions. Selecting one EXE never excludes every
// process with the same basename, nor its unselected helper processes.
func programPathExpressions(paths []string) ([]string, error) {
	if len(paths) > 200 {
		return nil, fmt.Errorf("too many program exclusions (maximum 200)")
	}
	seen := make(map[string]bool)
	expressions := make([]string, 0, len(paths))
	for _, path := range paths {
		path = strings.ReplaceAll(path, "/", `\`)
		if strings.ContainsAny(path, "\x00\r\n") || !windowsAbsoluteExecutable.MatchString(path) {
			return nil, fmt.Errorf("program exclusion requires a full Windows .exe path: %q", path)
		}
		key := strings.ToLower(path)
		if seen[key] {
			continue
		}
		seen[key] = true
		expressions = append(expressions, "(?i)^"+regexp.QuoteMeta(path)+"$")
	}
	return expressions, nil
}

func programExclusionRules(hopt *HiddifyOptions) ([]option.Rule, []option.DefaultDNSRule, error) {
	if !C.IsWindows {
		return nil, nil, nil
	}
	return windowsProgramExclusionRules(hopt)
}

func windowsProgramExclusionRules(hopt *HiddifyOptions) ([]option.Rule, []option.DefaultDNSRule, error) {
	if (!hopt.EnableTun && !hopt.EnableTunService) || len(hopt.DirectProcessPaths) == 0 {
		return nil, nil, nil
	}
	expressions, err := programPathExpressions(hopt.DirectProcessPaths)
	if err != nil {
		return nil, nil, err
	}
	route := option.Rule{
		Type: C.RuleTypeDefault,
		DefaultOptions: option.DefaultRule{
			RawDefaultRule: option.RawDefaultRule{ProcessPathRegex: expressions},
			RuleAction: option.RuleAction{
				Action:       C.RuleActionTypeRoute,
				RouteOptions: option.RouteActionOptions{Outbound: OutboundDirectTag},
			},
		},
	}
	dns := option.DefaultDNSRule{
		RawDefaultDNSRule: option.RawDefaultDNSRule{ProcessPathRegex: expressions},
		DNSRuleAction: option.DNSRuleAction{
			Action: C.RuleActionTypeRoute,
			RouteOptions: option.DNSRouteActionOptions{
				Server:   DNSMultiDirectTag,
				Strategy: hopt.DirectDnsDomainStrategy,
			},
		},
	}
	return []option.Rule{route}, []option.DefaultDNSRule{dns}, nil
}
