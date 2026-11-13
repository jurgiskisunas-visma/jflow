package main

import (
	"bytes"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"
)

func pp(t *testing.T, root string, args ...string) string {
	t.Helper()
	var out bytes.Buffer
	if err := run(args, root, &out); err != nil {
		t.Fatalf("pp %v: %v", args, err)
	}
	return out.String()
}

func TestNewSetLsIndex(t *testing.T) {
	root := t.TempDir()
	pp(t, root, "new", "ato", "ATO-1", "title=Fix the thing", "type=investigate")
	pp(t, root, "new", "personal", "ledger")
	pp(t, root, "set", "ato-1", "status=active", "next=read the logs")
	pp(t, root, "set", "ledger", "status=done")

	ls := pp(t, root, "ls")
	if !strings.Contains(ls, "ATO-1") || !strings.Contains(ls, "read the logs") || strings.Contains(ls, "ledger") {
		t.Fatalf("ls hides closed tasks and shows next:\n%s", ls)
	}
	if all := pp(t, root, "ls", "all"); !strings.Contains(all, "ledger") {
		t.Fatalf("ls all shows closed tasks:\n%s", all)
	}
	index, err := os.ReadFile(filepath.Join(root, "INDEX.md"))
	if err != nil || !strings.Contains(string(index), "1 open, 1 closed") {
		t.Fatalf("index: %v\n%s", err, index)
	}
	for _, f := range []string{"task.json", "task.md", "plan.md"} {
		if _, err := os.Stat(filepath.Join(root, "ato", "ATO-1", f)); err != nil {
			t.Fatalf("missing %s", f)
		}
	}
}

func TestRejectsBadInput(t *testing.T) {
	root := t.TempDir()
	pp(t, root, "new", "ato", "ATO-1")
	for _, args := range [][]string{
		{"set", "ATO-1", "status=finished"},
		{"set", "ATO-1", "type=fun"},
		{"set", "ATO-1", "id=other"},
		{"set", "nope", "status=done"},
		{"new", "ato", "ATO-1"},
		{"new", "ato", "bad name"},
	} {
		if err := run(args, root, &bytes.Buffer{}); err == nil {
			t.Fatalf("pp %v must fail", args)
		}
	}
}

func TestUnknownFieldsSurviveAndEventsCount(t *testing.T) {
	root := t.TempDir()
	for _, id := range []string{"A", "B", "C"} {
		pp(t, root, "new", "p", id)
		pp(t, root, "event", id, "correction", "scope too wide")
	}
	pp(t, root, "event", "A", "rework")
	pp(t, root, "event", "A", "rework")
	pp(t, root, "set", "A", "custom=kept")
	pp(t, root, "set", "A", "status=active")
	if show := pp(t, root, "show", "A"); !strings.Contains(show, `"custom": "kept"`) || !strings.Contains(show, "scope too wide") {
		t.Fatalf("unknown fields and events survive a set:\n%s", show)
	}
	stats := pp(t, root, "stats")
	var correction, rework string
	for _, line := range strings.Split(stats, "\n") {
		if strings.HasPrefix(line, "correction") {
			correction = line
		}
		if strings.HasPrefix(line, "rework") {
			rework = line
		}
	}
	if !strings.Contains(correction, "yes") || strings.Contains(rework, "yes") {
		t.Fatalf("a class in 3 tasks is a pattern, 2 events in one task are not:\n%s", stats)
	}
}

func TestCleanRemovesOnlyOldClosedScratch(t *testing.T) {
	root := t.TempDir()
	scratch := func(id string) string { return filepath.Join(root, "p", id, "scratch", "big.bin") }
	for _, id := range []string{"open", "closed-old", "closed-new"} {
		pp(t, root, "new", "p", id)
		os.MkdirAll(filepath.Dir(scratch(id)), 0o755)
		os.WriteFile(scratch(id), make([]byte, 2048), 0o644)
	}
	real := now
	now = func() time.Time { return real().AddDate(0, 0, -30) }
	pp(t, root, "set", "closed-old", "status=done")
	now = real
	pp(t, root, "set", "closed-new", "status=done")

	pp(t, root, "clean")
	if _, err := os.Stat(scratch("closed-old")); err != nil {
		t.Fatal("dry run must not delete")
	}
	pp(t, root, "clean", "apply")
	if _, err := os.Stat(scratch("closed-old")); err == nil {
		t.Fatal("old closed scratch must go")
	}
	for _, id := range []string{"open", "closed-new"} {
		if _, err := os.Stat(scratch(id)); err != nil {
			t.Fatalf("scratch of %s must stay", id)
		}
	}
	if _, err := os.Stat(filepath.Join(root, "p", "closed-old", "task.md")); err != nil {
		t.Fatal("durable files must stay")
	}
}

func TestIdea(t *testing.T) {
	root := t.TempDir()
	pp(t, root, "idea", "try", "slots", "per", "project")
	data, _ := os.ReadFile(filepath.Join(root, "IDEAS.md"))
	if !strings.Contains(string(data), "try slots per project") {
		t.Fatalf("idea parked:\n%s", data)
	}
}
