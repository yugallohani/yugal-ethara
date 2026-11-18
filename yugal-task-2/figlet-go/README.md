# practice/figlet-go

Harbor task: port pyfiglet 1.0.4 (commit `255827efbc09d662875dad50fa0edc1e1263bf45`)
to Go, byte for byte, in a room with no Python.

| Path | What |
|---|---|
| `NOTES.md` | pyfiglet facts: SHA, date, MIT, font setup step, smushing rules, options, rare cases |
| `environment/Dockerfile` | two stages: `source` (alpine/git, pinned) clones and sets up fonts; final room is `golang:1.23-alpine` (pinned by digest) + bash, user `player` |
| `task.toml` | agent user `player`, 3600 s; public network; build 900 s; verifier 900 s, shared |
| `instruction.md` | what the agent must build |
| `tests/gen.py` | author-side generator (seed 7) of `tests/data/{visible,hidden}.jsonl` from the original pyfiglet |
| `tests/grade.go`, `tests/test.sh` | Go-only grader: build (1), no_python (1), behaviour on hidden cases (4) |
| `tests/secret.b64` | the secret, drawn only when behaviour is 1.0 |
| `solution/solve.sh` | oracle: writes the Go port, moves fonts to `fonts/` (go:embed), deletes `.py` |
| `cheat/solve.sh` | lookup table over the visible cases, used to prove the grader catches it |
| `RESULTS.md`, `results/`, `screenshots/` | rewards, verifier logs and terminal screenshots for oracle, nop and cheat |

## Commands

Run the `harbor` commands from the folder that contains `figlet-go/` (`yugal-task-2/`),
and the other two from inside `figlet-go/`.

```
harbor run -p ./figlet-go -a oracle     # 1.0
harbor run -p ./figlet-go -a nop        # 0.0
docker build -t figlet-room environment/
python3 tests/gen.py                    # needs a pyfiglet/ checkout with pyfiglet/fonts/ set up,
                                        # beside or above the task folder (or PYFIGLET_DIR=...)
```
