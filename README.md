# cron-claude

Overnight batch planner. While you're away, it runs Claude Code in **plan mode**
(read-only) over each task and writes a Markdown plan you can review in the morning.

## Layout
```
cron-claude/
├── .config        # model, effort, cwd, timeout, window
├── run.sh         # the runner (cron drives this)
├── tasks/         # drop one task/issue per file (.md or .txt)
│   └── done/      # processed tasks moved here
├── plans/         # generated plans land here
└── logs/          # one log per run
```

## Usage
1. Put task files in `tasks/` (see `tasks/README.md`).
2. Cron runs `run.sh` overnight. Or run it manually any time:
   ```
   ENFORCE_WINDOW=0 ~/cron-claude/run.sh   # ignore the time window
   ```
3. Read the results in `plans/`.

## Schedule
Runs every ~5h inside the 6 PM–3 AM window: at **18:00, 23:00, 03:00**.
The last run starts by 3 AM so its ~5h usage window resets around 8 AM (arrival),
leaving your morning session budget intact. crontab entry (via `install-cron.sh`):
```
0 18,23,3 * * * /home/nando/cron-claude/run.sh >> /home/nando/cron-claude/logs/cron.log 2>&1
```
The runner also self-checks the window, so a manual/misfired run outside
6 PM–3 AM exits quietly (unless `ENFORCE_WINDOW=0`).

## Config
Edit `.config`. Keys: `MODEL`, `EFFORT` (low|medium|high|xhigh|max),
`PROJECT_DIR`, `PLAN_TIMEOUT`, `ENFORCE_WINDOW`, `WINDOW_START`, `WINDOW_END`.
