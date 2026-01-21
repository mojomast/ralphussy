# Agent Notes

## Ralph Canonical Entrypoint

When you run `ralph` from any folder, the command resolves like this:

- `/usr/local/bin/ralph` (what your shell finds on PATH)
- This is a symlink to `/home/mojo/.local/bin/ralph`

To avoid editing one script and accidentally running another:

- Treat `/home/mojo/projects/opencode2/ralph` as the *only* implementation to modify.
- `/home/mojo/.local/bin/ralph` is a tiny wrapper that `exec`s `/home/mojo/projects/opencode2/ralph`.

Quick checks:

```bash
command -v ralph
readlink -f "$(command -v ralph)"
```

Expected output:

- `command -v ralph` -> `/usr/local/bin/ralph`
- `readlink -f ...` -> `/home/mojo/.local/bin/ralph`

If `ralph` is not using the repo-local implementation, fix the wrapper at:

- `/home/mojo/.local/bin/ralph`

Notes:

- `/home/mojo/bin/ralph` also exists, but it is not used unless `/home/mojo/bin` is earlier in `PATH`.
