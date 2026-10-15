# tmux-agents

Run several [Kiro CLI](https://kiro.dev) agents side by side in tmux and let them talk to each other.
Each agent lives in its own pane. Agents hand each other tasks with `tmux-agent send` / `spawn`, and
pass results back with `notify` / `wait`.

```
┌──────────────────────┬──────────────────────┐
│ %0 [coder]           │ %1 [jira]            │
│ > tmux-agent spawn   │ [from: coder]        │
│   jira "[WAIT:coder] │ [WAIT:coder] Get     │
│   details of COM-128"│ details of COM-128   │
│ > tmux-agent wait    │ ...                  │
└──────────────────────┴──────────────────────┘
```

## What's in the repo

| Path | What it is | Installed to |
|---|---|---|
| `bin/tmux-agent` | The CLI | `~/.local/bin/tmux-agent` |
| `hooks/detect-env.sh` | Kiro `agentSpawn` hook. Tells an agent which pane it's in, its own agent name, and its peers | `~/.kiro/hooks/tmux-agent-env.sh` |
| `skills/tmux-agent/SKILL.md` | Kiro skill. Teaches an agent the commands and the `[WAIT:...]` / `notify` protocol | `~/.kiro/skills/tmux-agent/SKILL.md` |
| `install.sh` | Symlinks the three files above into place | — |

## Requirements

- macOS or Linux, bash 3.2+
- tmux: `brew install tmux`
- kiro-cli on your `PATH`

## Install

```bash
git clone https://github.com/sukanthanv3/tmux-agents.git ~/tmux-agents
cd ~/tmux-agents
./install.sh
```

`install.sh` **symlinks** the files instead of copying them, so to update you only need:

```bash
cd ~/tmux-agents && git pull
```

What the installer does:

- If a file already exists at a target path, it backs it up to `<file>.bak-<timestamp>` first.
- If `~/.local/bin` isn't on your `PATH`, it adds an `export PATH=...` line to `~/.zshrc`
  (`~/.bash_profile` on macOS bash, `~/.bashrc` on Linux bash). Open a new terminal afterwards.
- You can change the locations: `BIN_DIR=/usr/local/bin ./install.sh`, or set `KIRO_HOME` if your
  Kiro config isn't in `~/.kiro`.
- `./install.sh --uninstall` removes the symlinks.

To skip the installer and just put the command on your `PATH`:

```bash
echo 'export PATH="$HOME/tmux-agents/bin:$PATH"' >> ~/.zshrc && source ~/.zshrc
```

Check it worked:

```bash
tmux-agent help
```

## Kiro integration

The CLI works without this step. Your agents only learn how to use it when each agent's config loads
the skill and runs the hook. Add both to every agent in `~/.kiro/agents/<name>.json` that you plan to
run under tmux-agent:

```json
{
  "resources": [
    "skill://~/.kiro/skills/tmux-agent/SKILL.md"
  ],
  "hooks": {
    "agentSpawn": [
      { "command": "bash ~/.kiro/hooks/tmux-agent-env.sh" }
    ]
  }
}
```

If the agent already has `resources` or `hooks`, add these entries to them instead of replacing them.
Then start the agent and run `/context` to confirm the skill loaded.

The hook prints something like this into the agent's context:

```
Shell Type: tmux pane
tmux-agent Session: ta-x7k2p9
My Agent Name: coder
Peer Agents: jira:%1
Messaging: tmux-agent send <agent> "<msg>" | tmux-agent notify <agent> "<result>"
```

Outside tmux it only reports the shell type, so the hook is safe to leave on all the time.

## Usage

### Start a session

```bash
id=$(tmux-agent start)      # prints the session id, e.g. ta-x7k2p9
tmux attach -t "$id"
```

In the first pane, make it an agent:

```bash
tmux-agent new coder        # registers this pane as "coder" and starts: kiro-cli chat -a --agent coder
```

The agent name has to match a Kiro agent config, unless you pass `--agent <kiro-agent>`.
Use `--dir <path>` to start the agent in another directory.

### Add more agents

From your shell, or from inside an agent:

```bash
tmux-agent spawn jira "Get the details of COM-128"
tmux-agent spawn --agent coder --dir ~/repo/api coder-2 "Fix the lint errors"
```

`spawn` opens a new pane and starts the agent with the task as its first prompt. If the agent is
already running, `spawn` just sends it the task. A window holds up to 4 panes; after that, new
windows are opened (change the limit with `TMUX_AGENT_MAX_PANES`).

### Talk between agents

```bash
# Ask for something back: tag it, then block until the receiver notifies you
tmux-agent send jira "[WAIT:coder] Summarise COM-128"
tmux-agent wait                       # prints jira's result

# The receiver answers with
tmux-agent notify coder "DONE: COM-128 — ..."

# Just pass information along (no tag, nobody waits)
tmux-agent send coder "FYI: COM-128 is blocked on design review"
```

The skill teaches agents these rules. You don't have to type them yourself.

### Inspect and clean up

```bash
tmux-agent list-sessions    # every tmux-agent session, newest first, with its agents
tmux-agent agents           # agents in the current session
tmux-agent capture jira     # dump a pane's recent output
tmux-agent stop jira        # cancel jira's current response (Ctrl-C); jira keeps running
tmux-agent quit jira        # exit jira; a spawned pane closes
tmux-agent kill [ID]        # kill a session (default: the current one)
```

Run `tmux-agent help` for the full command list.

### Outside the session

All commands work from any terminal once you point them at a session:

```bash
export TMUX_AGENT_SESSION=ta-x7k2p9
tmux-agent spawn jira "..."
```

## Configuration

| Variable | Default | Purpose |
|---|---|---|
| `TMUX_AGENT_SESSION` | session of the current pane | Which session commands act on |
| `TMUX_AGENT_MAX_PANES` | `4` | Panes per window before `spawn` opens a new window |
| `TMUX_AGENT_CMD` | `kiro-cli chat -a --agent` | Command used to launch an agent (agent name is appended) |

`kiro-cli chat -a` trusts every tool. Agents run unattended, so with anything less they would get
stuck on approval prompts. If you don't want that, override `TMUX_AGENT_CMD`.

## How it works

- A session is an ordinary tmux session tagged with the `@tmux_agent` option.
- The registry is the panes themselves: each agent pane carries an `@agent` user option. Apps can't
  overwrite it, pane ids never shift, and tmux drops it when the pane dies.
- `send` pastes into the target pane through bracketed paste and then presses Enter.
- `notify` / `wait` use `tmux wait-for` channels. Results are stored under
  `$TMPDIR/tmux-agent-<session>/`.
