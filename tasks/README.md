# tasks/

Drop one task per file here (`.md` or `.txt`). Paste a whole issue if you like —
the entire file content is handed to Claude.

- Each file becomes one plan in `../plans/<name>.plan-<timestamp>.md`.
- After a successful run the source file is moved to `tasks/done/`.
- Failed tasks stay here and are retried on the next run.
- Optional first line to run in a specific repo: `<!-- cwd: /path/to/repo -->`

This README and the `done/` folder are ignored by the runner.
