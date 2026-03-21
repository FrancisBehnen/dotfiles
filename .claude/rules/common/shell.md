# Shell Commands

## Avoiding Harness Blocks

The harness requires manual approval for certain patterns. Avoid them:

- **`cd` + redirection**: Never combine `cd` with `>`, `>>`, or `|` in a compound
  command. Use absolute paths instead, or run `cd` as a separate command first.
- **`$()` command substitution**: Avoid `$()` in compound commands. Prefer pipes
  or split into separate sequential commands.

## Reducing Approval Prompts

Batch independent checks into a single Bash call using `&&`, `;`, or `echo "==="`
separators. Fewer calls = fewer prompts for the user to approve.
