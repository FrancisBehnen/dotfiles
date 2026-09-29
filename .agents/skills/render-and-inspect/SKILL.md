---
name: render-and-inspect
description: >-
  Render something and LOOK at it: a generated HTML page, a Mermaid/Graphviz/D2 diagram, a chart or dashboard, an SVG, a PDF, a local file or localhost URL, or a before/after visual comparison. Renders it in a real browser via `playwright-cli` and screenshots it to a PNG that can be read back. Use whenever "I need to see how this renders" is the goal, not only for testing. For general browser automation and Playwright tests, use the upstream `playwright-cli` skill instead.
allowed-tools: Bash(playwright-cli:*) Bash(python3 -m http.server*)
---

# Render and inspect

The binary is **`playwright-cli`**, not `playwright`, so a negative `which playwright`
tells you nothing. Check `which playwright-cli` (usually `~/.bun/bin`) or use
`npx playwright-cli`. For every command beyond this recipe, see the upstream
`playwright-cli` skill.

## Recipe

```bash
# file:// is BLOCKED outright: always serve the folder, never open the file directly
python3 -m http.server 8977 --bind 127.0.0.1   # run in the background
playwright-cli -s=render open --browser=chrome http://127.0.0.1:8977/page.html
playwright-cli -s=render --raw console error    # catch render failures before trusting the output
playwright-cli -s=render screenshot --filename=out.png   # then Read out.png to see it
playwright-cli -s=render close                  # always tear down, and kill the server too
```

Use a named session (`-s=`) so the browser can be addressed across calls and
closed at the end.

## `file://` never works

Serve over HTTP, even for a one-line static page. The failure is
`Error: Access to "file:" protocol is blocked. Attempted URL: "file:///…"`, and the
CLI raises it *after* reporting that the browser opened, so it is easy to miss and
leaves the session on `about:blank`. This is a **protocol block, not a CORS nuance**.
Measured 2026-09-02: `<!doctype html><title>x</title><h1>hello</h1>` with no
imports at all failed exactly like a page importing ES modules from a CDN.

## Invocation shapes that don't exist

Each of these cost a failed call (re-checked against playwright-cli 0.1.15 on
2026-09-29):

- **There is no `navigate` subcommand.** Use `open <url>` for the first load and
  `goto <url>` afterwards. `navigate` prints the whole help text, which reads like
  a quoting mistake of yours rather than a wrong command name.
- **There is no `--headless` flag.** Headless is the default; the only mode flag is
  `--headed`. `open --headless <url>` fails on the flag and dumps help again.
- **`screenshot`'s positional argument is an element target, not a filename.**
  `screenshot out.png` tries to resolve `out.png` as a page element. The filename
  goes in `--filename=out.png`; `--full-page` and `--hires` are separate flags.
- **A screenshot needs a browser that is already open.** A cold `screenshot` gives
  `The browser 'default' is not open, please run open first`. Worse, if an earlier
  session left a browser open on another page, you silently capture *that* page,
  so run `close-all` before a fresh render.

## One browser, one owner

`playwright-cli` drives one persistent browser per session name, so treat it as an
exclusive resource. Two agents on the same session silently override each other's
`open`/`goto`, and the loser screenshots a page it never opened with no error. Give
each agent its own `-s=` name, or serialise them. Verify identity in the result
rather than trusting the call: set a `document.title` or a marker only you know,
and assert it comes back. See "contended singleton tools" in `~/.claude/CLAUDE.md`.

Prefer an offline check where one exists. A Mermaid diagram, for example, can be
validated with its parser (bun + jsdom) with no browser at all.
