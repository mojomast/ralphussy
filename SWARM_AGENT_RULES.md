# Swarm Agent Rules - Source File Cleanliness

## Purpose
This document defines critical rules for swarm workers to ensure source code files remain clean and valid.

## CRITICAL: Source File Cleanliness Rules

### NEVER Insert These Into Source Files

1. **HTML/Markdown Comments**
   - `<!-- any content -->` 
   - `{# Jinja comments #}`
   - These are ONLY valid in `.html`, `.md`, `.xml` files

2. **Progress/Checkpoint Markers**
   - `// PROGRESS: ...`
   - `// SWARM: ...`
   - `// Worker N: ...`
   - `// Task completed: ...`
   - `// CHECKPOINT: ...`
   - `# PROGRESS: ...` (in Python/Shell)

3. **Merge Conflict Markers**
   - `<<<<<<< ...`
   - `=======`
   - `>>>>>>> ...`

4. **Coordination Comments**
   - `// TODO (Worker 3): ...`
   - `// HANDOFF: ...`
   - `// SYNC: ...`

### Correct Comment Syntax by Language

If you MUST add a comment in source code, use the correct syntax:

| Language | Comment Syntax |
|----------|---------------|
| Go | `// comment` or `/* comment */` |
| Python | `# comment` or `""" docstring """` |
| JavaScript/TypeScript | `// comment` or `/* comment */` |
| Rust | `// comment` or `/* comment */` |
| C/C++ | `// comment` or `/* comment */` |
| Ruby | `# comment` |
| Shell/Bash | `# comment` |
| HTML/XML | `<!-- comment -->` |
| Markdown | `<!-- comment -->` |

### Progress Tracking

Progress is tracked by the swarm system, NOT in source files:
- Use `<promise>COMPLETE</promise>` at the END of your response
- The swarm database tracks task status
- Worker logs capture detailed progress
- NEVER embed progress tracking in code

### Development Notes

If you need to leave notes about code:
1. Create a separate `NOTES.md` or `TODO.md` file
2. Use proper language-specific `TODO:` or `FIXME:` comments
3. Example: `// TODO: Optimize this algorithm for large inputs`

### Validation

Before completing a task, mentally verify:
- [ ] No HTML comments in `.go`, `.py`, `.rs`, `.js`, `.ts` files
- [ ] No progress markers embedded in source code
- [ ] No merge conflict markers present
- [ ] All comments use proper language syntax

## Usage

Include this in your devplan or prompt:

```markdown
IMPORTANT: Follow the rules in SWARM_AGENT_RULES.md for source file cleanliness.
Never insert progress markers, HTML comments, or coordination annotations into source code files.
```

Or add to your ralph.config:
```bash
# Add to worker prompt
SWARM_EXTRA_INSTRUCTIONS="Follow source file cleanliness rules: no progress markers, no HTML comments in code files."
```
