// jplanis the task ledger tool: one folder per task under the planning root,
// task.json for structure, Markdown for notes, INDEX.md as a generated cache.
package main

import (
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"io/fs"
	"os"
	"path/filepath"
	"sort"
	"strconv"
	"strings"
	"text/tabwriter"
	"time"
)

const usage = `jplan- task ledger

  jplannew <project> <key-or-slug> [title=...] [type=implement|investigate|review] [field=value ...]
  jplanls [all] [project=<name>]
  jplanshow <key>
  jplanset <key> field=value [field=value ...]     fields: status, next, title, type, jira, branch, worktree, pr, tokens, any other
  jplanevent <key> <class> [note]                  record a retrospective event (correction, review-finding, rework, gate-failure, budget)
  jplanstats [last=20]                             event classes across the most recent tasks
  jplanidea <text>                                 park an idea in IDEAS.md
  jplanindex                                       regenerate INDEX.md
  jplanclean [apply] [days=14]                     sizes; removes scratch\ of done and dropped tasks (dry run without apply)

Root: %JPLAN_ROOT%, default D:\project-planning. Statuses: todo, active, waiting, review, done, dropped.
`

var (
	statuses = []string{"active", "review", "waiting", "todo", "done", "dropped"}
	types    = []string{"implement", "investigate", "review"}
	now      = func() time.Time { return time.Now() }
)

type task struct {
	dir string
	m   map[string]any
}

func (t task) s(key string) string {
	switch v := t.m[key].(type) {
	case string:
		return v
	case float64:
		return strconv.FormatInt(int64(v), 10)
	}
	return ""
}

func (t task) open() bool { return t.s("status") != "done" && t.s("status") != "dropped" }

func main() {
	root := os.Getenv("JPLAN_ROOT")
	if root == "" {
		root = `D:\project-planning`
	}
	if err := run(os.Args[1:], root, os.Stdout); err != nil {
		fmt.Fprintln(os.Stderr, "jplan:", err)
		os.Exit(1)
	}
}

func run(args []string, root string, out io.Writer) error {
	if len(args) == 0 {
		fmt.Fprint(out, usage)
		return nil
	}
	pos, kv := splitArgs(args[1:])
	switch args[0] {
	case "new":
		return cmdNew(root, pos, kv, out)
	case "ls":
		return cmdLs(root, pos, kv, out)
	case "show":
		return cmdShow(root, pos, out)
	case "set":
		return cmdSet(root, pos, kv, out)
	case "event":
		return cmdEvent(root, pos, out)
	case "stats":
		return cmdStats(root, kv, out)
	case "idea":
		return cmdIdea(root, pos, out)
	case "index":
		return writeIndex(root, out)
	case "clean":
		return cmdClean(root, pos, kv, out)
	case "help", "-h", "--help":
		fmt.Fprint(out, usage)
		return nil
	}
	return fmt.Errorf("unknown command %q; run jplanhelp", args[0])
}

func splitArgs(args []string) (pos []string, kv map[string]string) {
	kv = map[string]string{}
	for _, a := range args {
		if i := strings.Index(a, "="); i > 0 && !strings.ContainsAny(a[:i], " /\\:") {
			kv[a[:i]] = a[i+1:]
		} else {
			pos = append(pos, a)
		}
	}
	return
}

func contains(list []string, v string) bool {
	for _, x := range list {
		if x == v {
			return true
		}
	}
	return false
}

func stamp() string { return now().Format("2006-01-02T15:04:05Z07:00") }

func loadAll(root string) ([]task, error) {
	var tasks []task
	projects, err := os.ReadDir(root)
	if err != nil {
		return nil, err
	}
	for _, p := range projects {
		if !p.IsDir() || strings.HasPrefix(p.Name(), "_") || strings.HasPrefix(p.Name(), ".") {
			continue
		}
		entries, _ := os.ReadDir(filepath.Join(root, p.Name()))
		for _, e := range entries {
			if !e.IsDir() {
				continue
			}
			dir := filepath.Join(root, p.Name(), e.Name())
			data, err := os.ReadFile(filepath.Join(dir, "task.json"))
			if err != nil {
				continue
			}
			m := map[string]any{}
			if err := json.Unmarshal(data, &m); err != nil {
				return nil, fmt.Errorf("%s: %w", filepath.Join(dir, "task.json"), err)
			}
			tasks = append(tasks, task{dir: dir, m: m})
		}
	}
	sort.SliceStable(tasks, func(i, j int) bool {
		ri, rj := rank(tasks[i].s("status")), rank(tasks[j].s("status"))
		if ri != rj {
			return ri < rj
		}
		return tasks[i].s("updated") > tasks[j].s("updated")
	})
	return tasks, nil
}

func rank(status string) int {
	for i, s := range statuses {
		if s == status {
			return i
		}
	}
	return len(statuses)
}

func find(root, key string) (task, error) {
	tasks, err := loadAll(root)
	if err != nil {
		return task{}, err
	}
	var hits []task
	for _, t := range tasks {
		full := t.s("project") + "/" + t.s("id")
		if strings.EqualFold(t.s("id"), key) || strings.EqualFold(full, strings.ReplaceAll(key, `\`, "/")) {
			hits = append(hits, t)
		}
	}
	switch len(hits) {
	case 0:
		return task{}, fmt.Errorf("no task %q", key)
	case 1:
		return hits[0], nil
	}
	return task{}, fmt.Errorf("%q matches %d tasks; use <project>/<key>", key, len(hits))
}

// save writes through a temp file so a killed process never leaves half a task.json.
func save(t task) error {
	t.m["updated"] = stamp()
	data, err := json.MarshalIndent(t.m, "", "  ")
	if err != nil {
		return err
	}
	path := filepath.Join(t.dir, "task.json")
	tmp := path + ".tmp"
	if err := os.WriteFile(tmp, append(data, '\n'), 0o644); err != nil {
		return err
	}
	return os.Rename(tmp, path)
}

func apply(t task, kv map[string]string) error {
	for k, v := range kv {
		switch {
		case k == "status" && !contains(statuses, v):
			return fmt.Errorf("status %q; use one of %s", v, strings.Join(statuses, ", "))
		case k == "type" && !contains(types, v):
			return fmt.Errorf("type %q; use one of %s", v, strings.Join(types, ", "))
		case k == "id" || k == "project" || k == "created" || k == "updated" || k == "events":
			return fmt.Errorf("field %q is not settable", k)
		case v == "":
			delete(t.m, k)
		case k == "tokens":
			n, err := strconv.ParseInt(v, 10, 64)
			if err != nil {
				return fmt.Errorf("tokens %q is not a number", v)
			}
			t.m[k] = n
		default:
			t.m[k] = v
		}
	}
	return nil
}

func cmdNew(root string, pos []string, kv map[string]string, out io.Writer) error {
	if len(pos) != 2 {
		return errors.New("usage: jplannew <project> <key-or-slug> [title=...] [type=...]")
	}
	project, id := pos[0], pos[1]
	if strings.ContainsAny(project+id, `/\:*?"<>| `) || strings.HasPrefix(project, "_") {
		return errors.New("project and key must be plain folder names without spaces")
	}
	dir := filepath.Join(root, project, id)
	if _, err := os.Stat(filepath.Join(dir, "task.json")); err == nil {
		return fmt.Errorf("task %s/%s already exists", project, id)
	}
	if err := os.MkdirAll(dir, 0o755); err != nil {
		return err
	}
	t := task{dir: dir, m: map[string]any{
		"id": id, "project": project, "title": id, "type": "implement", "status": "todo", "created": stamp(),
	}}
	if err := apply(t, kv); err != nil {
		return err
	}
	if err := save(t); err != nil {
		return err
	}
	seed := map[string]string{
		"task.md": fmt.Sprintf("# %s\n\n## What\n\n## Why\n\n## Source\n\n## Done when\n", t.s("title")),
		"plan.md": "# Plan\n\n## Progress\n\n## Decisions\n\n## Surprises\n\n## Outcome\n",
	}
	for name, body := range seed {
		path := filepath.Join(dir, name)
		if _, err := os.Stat(path); errors.Is(err, fs.ErrNotExist) {
			if err := os.WriteFile(path, []byte(body), 0o644); err != nil {
				return err
			}
		}
	}
	fmt.Fprintln(out, "created", dir)
	return writeIndex(root, io.Discard)
}

func cmdLs(root string, pos []string, kv map[string]string, out io.Writer) error {
	tasks, err := loadAll(root)
	if err != nil {
		return err
	}
	all := contains(pos, "all")
	w := tabwriter.NewWriter(out, 0, 4, 2, ' ', 0)
	fmt.Fprintln(w, "PROJECT\tKEY\tTYPE\tSTATUS\tUPDATED\tNEXT")
	n := 0
	for _, t := range tasks {
		if (!all && !t.open()) || (kv["project"] != "" && !strings.EqualFold(kv["project"], t.s("project"))) {
			continue
		}
		next := t.s("next")
		if next == "" {
			next = t.s("title")
		}
		fmt.Fprintf(w, "%s\t%s\t%s\t%s\t%s\t%s\n", t.s("project"), t.s("id"), t.s("type"), t.s("status"), day(t.s("updated")), clip(next, 70))
		n++
	}
	w.Flush()
	fmt.Fprintf(out, "%d shown, %d total\n", n, len(tasks))
	return nil
}

func day(ts string) string {
	if len(ts) >= 10 {
		return ts[:10]
	}
	return ts
}

func clip(s string, n int) string {
	r := []rune(s)
	if len(r) <= n {
		return s
	}
	return string(r[:n-1]) + "…"
}

func cmdShow(root string, pos []string, out io.Writer) error {
	if len(pos) != 1 {
		return errors.New("usage: jplanshow <key>")
	}
	t, err := find(root, pos[0])
	if err != nil {
		return err
	}
	data, _ := json.MarshalIndent(t.m, "", "  ")
	fmt.Fprintf(out, "%s\n%s\n", t.dir, data)
	entries, _ := os.ReadDir(t.dir)
	var names []string
	for _, e := range entries {
		if e.Name() != "task.json" {
			names = append(names, e.Name())
		}
	}
	fmt.Fprintln(out, "files:", strings.Join(names, ", "))
	return nil
}

func cmdSet(root string, pos []string, kv map[string]string, out io.Writer) error {
	if len(pos) != 1 || len(kv) == 0 {
		return errors.New("usage: jplanset <key> field=value [field=value ...]")
	}
	t, err := find(root, pos[0])
	if err != nil {
		return err
	}
	if err := apply(t, kv); err != nil {
		return err
	}
	if err := save(t); err != nil {
		return err
	}
	fmt.Fprintf(out, "updated %s/%s\n", t.s("project"), t.s("id"))
	return writeIndex(root, io.Discard)
}

func cmdEvent(root string, pos []string, out io.Writer) error {
	if len(pos) < 2 {
		return errors.New("usage: jplanevent <key> <class> [note]")
	}
	t, err := find(root, pos[0])
	if err != nil {
		return err
	}
	events, _ := t.m["events"].([]any)
	t.m["events"] = append(events, map[string]any{"class": pos[1], "note": strings.Join(pos[2:], " "), "at": stamp()})
	if err := save(t); err != nil {
		return err
	}
	fmt.Fprintf(out, "event %s recorded on %s\n", pos[1], t.s("id"))
	return nil
}

// cmdStats counts in how many of the most recent tasks each event class occurs.
// A class seen in several different tasks is a pattern; many events in one task are not.
func cmdStats(root string, kv map[string]string, out io.Writer) error {
	last := 20
	if v := kv["last"]; v != "" {
		n, err := strconv.Atoi(v)
		if err != nil || n < 1 {
			return fmt.Errorf("last=%q is not a positive number", v)
		}
		last = n
	}
	tasks, err := loadAll(root)
	if err != nil {
		return err
	}
	sort.SliceStable(tasks, func(i, j int) bool { return tasks[i].s("updated") > tasks[j].s("updated") })
	if len(tasks) > last {
		tasks = tasks[:last]
	}
	inTasks, total := map[string]int{}, map[string]int{}
	for _, t := range tasks {
		seen := map[string]bool{}
		events, _ := t.m["events"].([]any)
		for _, e := range events {
			em, _ := e.(map[string]any)
			class, _ := em["class"].(string)
			total[class]++
			if !seen[class] {
				seen[class] = true
				inTasks[class]++
			}
		}
	}
	classes := make([]string, 0, len(inTasks))
	for c := range inTasks {
		classes = append(classes, c)
	}
	sort.Slice(classes, func(i, j int) bool { return inTasks[classes[i]] > inTasks[classes[j]] })
	w := tabwriter.NewWriter(out, 0, 4, 2, ' ', 0)
	fmt.Fprintln(w, "CLASS\tTASKS\tEVENTS\tPATTERN")
	for _, c := range classes {
		pattern := ""
		if inTasks[c] >= 3 {
			pattern = "yes"
		}
		fmt.Fprintf(w, "%s\t%d\t%d\t%s\n", c, inTasks[c], total[c], pattern)
	}
	w.Flush()
	fmt.Fprintf(out, "over the %d most recent tasks; pattern = seen in 3 or more tasks\n", len(tasks))
	return nil
}

func cmdIdea(root string, pos []string, out io.Writer) error {
	if len(pos) == 0 {
		return errors.New("usage: jplanidea <text>")
	}
	path := filepath.Join(root, "IDEAS.md")
	if _, err := os.Stat(path); errors.Is(err, fs.ErrNotExist) {
		if err := os.WriteFile(path, []byte("# Ideas\n\nParked ideas. Promote one with `jplannew`.\n\n"), 0o644); err != nil {
			return err
		}
	}
	f, err := os.OpenFile(path, os.O_APPEND|os.O_WRONLY, 0o644)
	if err != nil {
		return err
	}
	defer f.Close()
	if _, err := fmt.Fprintf(f, "- %s: %s\n", now().Format("2006-01-02"), strings.Join(pos, " ")); err != nil {
		return err
	}
	fmt.Fprintln(out, "parked in", path)
	return nil
}

func writeIndex(root string, out io.Writer) error {
	tasks, err := loadAll(root)
	if err != nil {
		return err
	}
	var b strings.Builder
	fmt.Fprintf(&b, "# Task index\n\nGenerated by `jplanindex` on %s. Do not edit; edit `task.json` or use `jplanset`.\n\n", now().Format("2006-01-02 15:04"))
	b.WriteString("## Open\n\n| Project | Key | Type | Status | Updated | Next |\n|---|---|---|---|---|---|\n")
	open := 0
	var closed []task
	for _, t := range tasks {
		if !t.open() {
			closed = append(closed, t)
			continue
		}
		open++
		next := t.s("next")
		if next == "" {
			next = t.s("title")
		}
		fmt.Fprintf(&b, "| %s | [%s](%s/%s/task.md) | %s | %s | %s | %s |\n", t.s("project"), t.s("id"), t.s("project"), t.s("id"), t.s("type"), t.s("status"), day(t.s("updated")), strings.ReplaceAll(next, "|", "/"))
	}
	sort.SliceStable(closed, func(i, j int) bool { return closed[i].s("updated") > closed[j].s("updated") })
	fmt.Fprintf(&b, "\n%d open, %d closed.\n\n## Recently closed\n\n", open, len(closed))
	for i, t := range closed {
		if i == 10 {
			break
		}
		fmt.Fprintf(&b, "- %s %s/%s (%s): %s\n", day(t.s("updated")), t.s("project"), t.s("id"), t.s("status"), t.s("title"))
	}
	path := filepath.Join(root, "INDEX.md")
	if err := os.WriteFile(path, []byte(b.String()), 0o644); err != nil {
		return err
	}
	fmt.Fprintln(out, "wrote", path)
	return nil
}

func dirSize(dir string) int64 {
	var n int64
	filepath.WalkDir(dir, func(_ string, d fs.DirEntry, err error) error {
		if err == nil && !d.IsDir() {
			if info, err := d.Info(); err == nil {
				n += info.Size()
			}
		}
		return nil
	})
	return n
}

func mb(n int64) string { return fmt.Sprintf("%.1f", float64(n)/1048576) }

func cmdClean(root string, pos []string, kv map[string]string, out io.Writer) error {
	days := 14
	if v := kv["days"]; v != "" {
		n, err := strconv.Atoi(v)
		if err != nil || n < 0 {
			return fmt.Errorf("days=%q is not a number", v)
		}
		days = n
	}
	doIt := contains(pos, "apply")
	tasks, err := loadAll(root)
	if err != nil {
		return err
	}
	cutoff := now().AddDate(0, 0, -days).Format("2006-01-02T15:04:05Z07:00")
	w := tabwriter.NewWriter(out, 0, 4, 2, ' ', 0)
	fmt.Fprintln(w, "PROJECT\tKEY\tSTATUS\tTOTAL MB\tSCRATCH MB\tACTION")
	var total, freed int64
	for _, t := range tasks {
		scratch := filepath.Join(t.dir, "scratch")
		size, ssize := dirSize(t.dir), dirSize(scratch)
		total += size
		action := ""
		if ssize > 0 && !t.open() && t.s("updated") < cutoff {
			action = "would remove scratch"
			if doIt {
				if err := os.RemoveAll(scratch); err != nil {
					return err
				}
				action = "removed scratch"
			}
			freed += ssize
		}
		fmt.Fprintf(w, "%s\t%s\t%s\t%s\t%s\t%s\n", t.s("project"), t.s("id"), t.s("status"), mb(size), mb(ssize), action)
	}
	w.Flush()
	verb := "would free"
	if doIt {
		verb = "freed"
	}
	fmt.Fprintf(out, "total %s MB; %s %s MB (scratch of tasks closed more than %d days ago)\n", mb(total), verb, mb(freed), days)
	return nil
}
