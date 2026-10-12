package config

import (
	"encoding/json"
	"regexp"
	"testing"

	C "github.com/sagernet/sing-box/constant"
)

func TestProgramPathsMatchOnlySelectedExecutable(t *testing.T) {
	paths := []string{`C:\Program Files\Alfa [PRO]+\Terminal.exe`, `C:/Users/Тестовый пользователь/Telegram.exe`}
	expressions, err := programPathExpressions(paths)
	if err != nil {
		t.Fatal(err)
	}
	cases := []struct {
		path string
		want bool
	}{
		{paths[0], true},
		{`c:\program files\alfa [pro]+\TERMINAL.EXE`, true},
		{`C:\Other\Terminal.exe`, false},
		{paths[0] + ".old", false},
		{`C:\Program Files\Alfa [PRO]+\Helper.exe`, false},
		{`C:\Users\Тестовый пользователь\Telegram.exe`, true},
		{`C:\Users\Тестовый пользователь\TelegramXexe`, false},
	}
	for _, tc := range cases {
		matched := false
		for _, exp := range expressions {
			matched = matched || regexp.MustCompile(exp).MatchString(tc.path)
		}
		if matched != tc.want {
			t.Errorf("%q match=%v, want=%v", tc.path, matched, tc.want)
		}
	}
}

func TestProgramPathsRejectRelativeOrNonExecutable(t *testing.T) {
	for _, path := range []string{"", "Terminal.exe", `C:\app.dll`, `\app.exe`, "C:\\app.exe\n", "C:\\app\x00.exe"} {
		if _, err := programPathExpressions([]string{path}); err == nil {
			t.Errorf("accepted %q", path)
		}
	}
}

func TestProgramPathsDeduplicateAndLimit(t *testing.T) {
	expressions, err := programPathExpressions([]string{`C:\App.exe`, `c:\APP.exe`})
	if err != nil || len(expressions) != 1 {
		t.Fatalf("duplicates: %v %v", expressions, err)
	}
	paths := make([]string, 201)
	if _, err := programPathExpressions(paths); err == nil {
		t.Fatal("limit was not enforced")
	}
}

func TestProgramExclusionsOnlyInWindowsVPN(t *testing.T) {
	for _, opts := range []*HiddifyOptions{
		{DirectProcessPaths: []string{`C:\App.exe`}},
		{InboundOptions: InboundOptions{EnableTun: true}},
		{InboundOptions: InboundOptions{EnableTunService: true}},
	} {
		routes, dns, err := programExclusionRules(opts)
		if err != nil || len(routes) != 0 || len(dns) != 0 {
			t.Fatalf("unexpected routing: %v %v %v", routes, dns, err)
		}
	}
	for _, service := range []bool{false, true} {
		opts := &HiddifyOptions{DirectProcessPaths: []string{`C:\App.exe`}, InboundOptions: InboundOptions{EnableTun: !service, EnableTunService: service}}
		routes, dns, err := windowsProgramExclusionRules(opts)
		if err != nil {
			t.Fatal(err)
		}
		if len(routes) != 1 || len(dns) != 1 {
			t.Fatal("missing Windows rules")
		}
		data, _ := json.Marshal(routes[0])
		var rule map[string]any
		if err := json.Unmarshal(data, &rule); err != nil {
			t.Fatal(err)
		}
		// sing-box omits action for its default route action.
		if (rule["action"] != nil && rule["action"] != "route") || rule["outbound"] != OutboundDirectTag {
			t.Fatalf("not direct: %s", data)
		}
		if _, ok := rule["process_path_regex"]; !ok {
			t.Fatal("process criterion missing")
		}
	}
	if !C.IsWindows {
		routes, _, err := programExclusionRules(&HiddifyOptions{
			DirectProcessPaths: []string{`C:\App.exe`}, InboundOptions: InboundOptions{EnableTun: true},
		})
		if err != nil || len(routes) != 0 {
			t.Fatal("rules enabled outside Windows")
		}
	}
}
