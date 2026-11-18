// grade.go: verifier for the figlet-go Harbor task. Go standard library only.
//
//	build      (weight 1): `go build -o /tmp/figlet .` in /workspace/repo succeeds.
//	no_python  (weight 1): build passed AND no .py file under /workspace/repo
//	                       AND at least one hidden case matches.
//	behaviour  (weight 4): share of hidden cases whose stdout equals "out" exactly.
//
// Writes /logs/verifier/reward.json. If behaviour is exactly 1.0, draws the
// secret from /tests/secret.b64 with the twin itself.
package main

import (
	"bufio"
	"bytes"
	"context"
	"encoding/base64"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"io/fs"
	"os"
	"os/exec"
	"path/filepath"
	"runtime"
	"strings"
	"sync"
	"time"
)

const (
	repoDir      = "/workspace/repo"
	binPath      = "/tmp/figlet"
	hiddenPath   = "/tests/data/hidden.jsonl"
	secretPath   = "/tests/secret.b64"
	rewardDir    = "/logs/verifier"
	rewardPath   = "/logs/verifier/reward.json"
	caseTimeout  = 5 * time.Second
	buildTimeout = 10 * time.Minute
	totalBudget  = 10 * time.Minute // all cases together; the rest count as wrong
	maxOutput    = 8 << 20          // bytes of stdout kept per case

	wBuild     = 1.0
	wNoPython  = 1.0
	wBehaviour = 4.0
)

type testCase struct {
	Args []string `json:"args"`
	Out  string   `json:"out"`
}

type result struct {
	Reward    float64 `json:"reward"`
	Build     float64 `json:"build"`
	NoPython  float64 `json:"no_python"`
	Behaviour float64 `json:"behaviour"`
}

// limitedBuffer keeps at most max bytes and silently drops the rest.
type limitedBuffer struct {
	buf       bytes.Buffer
	max       int
	truncated bool
}

func (l *limitedBuffer) Write(p []byte) (int, error) {
	room := l.max - l.buf.Len()
	if room <= 0 {
		l.truncated = true
		return len(p), nil
	}
	if len(p) > room {
		l.buf.Write(p[:room])
		l.truncated = true
		return len(p), nil
	}
	return l.buf.Write(p)
}

func main() {
	res := result{}
	defer func() { writeReward(res) }()

	// 1. build
	buildOK := build()
	if buildOK {
		res.Build = 1
	}
	fmt.Printf("[build] %v\n", buildOK)

	// 3. behaviour (computed before no_python, which depends on it)
	matched, total := 0, 0
	if buildOK {
		cases, err := loadCases(hiddenPath)
		if err != nil {
			fmt.Printf("[behaviour] cannot read hidden cases: %v\n", err)
		} else {
			total = len(cases)
			matched = runCases(cases)
		}
	}
	if total > 0 {
		res.Behaviour = float64(matched) / float64(total)
	}
	fmt.Printf("[behaviour] %d/%d hidden cases match (%.4f)\n", matched, total, res.Behaviour)

	// 2. no_python
	pyFiles := findPyFiles(repoDir)
	fmt.Printf("[no_python] .py files left: %d\n", len(pyFiles))
	for i, p := range pyFiles {
		if i == 5 {
			fmt.Printf("  ... and %d more\n", len(pyFiles)-5)
			break
		}
		fmt.Printf("  %s\n", p)
	}
	if buildOK && len(pyFiles) == 0 && matched > 0 {
		res.NoPython = 1
	}

	res.Reward = (wBuild*res.Build + wNoPython*res.NoPython + wBehaviour*res.Behaviour) /
		(wBuild + wNoPython + wBehaviour)
	fmt.Printf("[score] build=%.0f no_python=%.0f behaviour=%.4f reward=%.4f\n",
		res.Build, res.NoPython, res.Behaviour, res.Reward)

	// 5. secret
	fmt.Println()
	if total > 0 && matched == total {
		showSecret()
	} else {
		fmt.Println("No secret for you. Yet.")
	}
}

func build() bool {
	_ = os.Remove(binPath) // never grade a binary the agent left behind
	ctx, cancel := context.WithTimeout(context.Background(), buildTimeout)
	defer cancel()
	cmd := exec.CommandContext(ctx, "go", "build", "-o", binPath, ".")
	cmd.Dir = repoDir
	out, err := cmd.CombinedOutput()
	if err != nil {
		fmt.Printf("[build] go build failed: %v\n%s\n", err, truncate(string(out), 4000))
		return false
	}
	if st, err := os.Stat(binPath); err != nil || st.IsDir() {
		fmt.Printf("[build] %s was not produced\n", binPath)
		return false
	}
	return true
}

func loadCases(path string) ([]testCase, error) {
	f, err := os.Open(path)
	if err != nil {
		return nil, err
	}
	defer f.Close()
	var cases []testCase
	r := bufio.NewReader(f)
	for lineNo := 1; ; lineNo++ {
		line, err := r.ReadBytes('\n')
		if len(bytes.TrimSpace(line)) > 0 {
			var c testCase
			if jerr := json.Unmarshal(line, &c); jerr != nil {
				return nil, fmt.Errorf("line %d: %w", lineNo, jerr)
			}
			cases = append(cases, c)
		}
		if errors.Is(err, io.EOF) {
			break
		}
		if err != nil {
			return nil, err
		}
	}
	return cases, nil
}

// runOne runs the twin once from a neutral working directory.
func runOne(ctx context.Context, workDir string, args []string) ([]byte, bool) {
	ctx, cancel := context.WithTimeout(ctx, caseTimeout)
	defer cancel()
	cmd := exec.CommandContext(ctx, binPath, args...)
	cmd.Dir = workDir
	cmd.Stdin = nil
	cmd.Stderr = io.Discard
	out := &limitedBuffer{max: maxOutput}
	cmd.Stdout = out
	cmd.WaitDelay = time.Second
	_ = cmd.Run() // exit code is not graded
	if ctx.Err() != nil || out.truncated {
		return out.buf.Bytes(), false
	}
	return out.buf.Bytes(), true
}

func runCases(cases []testCase) int {
	workDir, err := os.MkdirTemp("", "figlet-grade-")
	if err != nil {
		workDir = "/"
	}
	defer os.RemoveAll(workDir)

	ctx, cancel := context.WithTimeout(context.Background(), totalBudget)
	defer cancel()

	ok := make([]bool, len(cases))
	jobs := make(chan int)
	var wg sync.WaitGroup
	workers := runtime.NumCPU()
	if workers > 8 {
		workers = 8
	}
	for w := 0; w < workers; w++ {
		wg.Add(1)
		go func() {
			defer wg.Done()
			for i := range jobs {
				if ctx.Err() != nil {
					continue
				}
				got, finished := runOne(ctx, workDir, cases[i].Args)
				ok[i] = finished && string(got) == cases[i].Out
			}
		}()
	}
	for i := range cases {
		jobs <- i
	}
	close(jobs)
	wg.Wait()
	if ctx.Err() != nil {
		fmt.Println("[behaviour] total time budget used up; remaining cases count as wrong")
	}

	matched, shown := 0, 0
	for i, good := range ok {
		if good {
			matched++
			continue
		}
		if shown < 5 {
			fmt.Printf("[behaviour] mismatch #%d args=%q\n", i, cases[i].Args)
			shown++
		}
	}
	return matched
}

func findPyFiles(root string) []string {
	var found []string
	_ = filepath.WalkDir(root, func(path string, d fs.DirEntry, err error) error {
		if err != nil {
			return nil
		}
		if !d.IsDir() && strings.HasSuffix(strings.ToLower(d.Name()), ".py") {
			found = append(found, path)
		}
		return nil
	})
	return found
}

func showSecret() {
	raw, err := os.ReadFile(secretPath)
	if err != nil {
		fmt.Printf("secret file missing: %v\n", err)
		return
	}
	text, err := base64.StdEncoding.DecodeString(strings.TrimSpace(string(raw)))
	if err != nil {
		fmt.Printf("secret file is not base64: %v\n", err)
		return
	}
	out, _ := runOne(context.Background(), "/", []string{"-f", "slant", string(text)})
	fmt.Println("*** SECRET UNLOCKED ***")
	fmt.Print(string(out))
}

func writeReward(res result) {
	_ = os.MkdirAll(rewardDir, 0o755)
	data, _ := json.Marshal(res)
	if err := os.WriteFile(rewardPath, append(data, '\n'), 0o644); err != nil {
		fmt.Printf("cannot write %s: %v\n", rewardPath, err)
		return
	}
	fmt.Printf("wrote %s: %s\n", rewardPath, data)
}

func truncate(s string, n int) string {
	if len(s) <= n {
		return s
	}
	return s[:n] + "\n... (truncated)"
}
