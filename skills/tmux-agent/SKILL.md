---
name: tmux-agent
description: Multi-agent tmux runtime — managing agents, sending tasks, and inter-agent communication
---

## Command Reference

| Command | Usage | Description |
| :--- | :--- | :--- |
| `tmux-agent start [--name ID]` | Start runtime | Create a session with one pane (agents get panes on demand) |
| `tmux-agent new [--dir <path>] [--agent <kiro-agent>] <agent>` | Run here | Register the CURRENT pane as <agent> and start kiro in it |
| `tmux-agent spawn [--dir <path>] [--agent <kiro-agent>] <agent> "<task>"` | Create agent | Open a NEW pane, start <agent> with <task> as its first prompt. If <agent> already runs, just sends it <task> |
| `tmux-agent stop <agent>` | Cancel | Cancel the agent's current response (Ctrl-C). It keeps running and can take a new task |
| `tmux-agent quit <agent>` | Quit agent | Exit the agent; its spawned pane closes |
| `tmux-agent send <agent> "<message>"` | Send message | Send a follow-up message to a running agent |
| `tmux-agent wait` | Wait for result | Block until someone notifies YOU (defaults to your own name) |
| `tmux-agent notify <requester> "<message>"` | Notify | Send result to the requester: wakes its `wait`, or pastes into its pane if it isn't waiting |
| `tmux-agent result <agent>` | Last result | Re-read the last notify message sent to <agent> |
| `tmux-agent agents` | List agents | Show registered agents and their state |
| `tmux-agent status` | Full status | All panes, agents, free slots |
| `tmux-agent capture <agent>` | Debug | Read raw pane output |
| `tmux-agent list-sessions` | List sessions | All tmux-agent sessions with id, created time, agents — newest first |
| `tmux-agent kill` | Kill | Kill session and clean up |

---

## Creating Agents

There is no fixed set of panes. When you need another agent, spawn it — a new pane is created, registered as that agent (`TMUX_AGENT_NAME`), and kiro starts with your task:

```bash
tmux-agent spawn jira "[WAIT:coder] Get details of COM-128"     # kiro agent "jira"
tmux-agent spawn --agent coder --dir ~/repo coder-2 "Fix the lint errors"  # second coder
```

- Agent name = kiro agent config unless `--agent` is given (use it to run several of the same kind).
- Check `tmux-agent agents` first; spawning a running agent just sends it the task.
- `stop` cancels what an agent is doing (e.g. it went down the wrong path); follow up with `send` to redirect it.
- `quit` agents you spawned when their work is done.

## Inter-Agent Communication

Any agent can send messages to any other agent using `tmux-agent send`. There are two modes:

### Request-Response (need a reply)

When you need a result back, add a `[WAIT:<your-name>]` tag. This tells the receiver they MUST `notify` when done because you're blocking on `wait`.

```bash
# Sender: tag the message and block
tmux-agent send jira "[WAIT:coder] I need the full details of COM-128"
result=$(tmux-agent wait)          # waits on coder's own inbox

# Receiver (jira): sees [WAIT:coder], does the work, then notifies
tmux-agent notify coder "DONE: COM-128 — Summary: Fix validation. Status: Open. ..."
```

**The sender is blocking on `tmux-agent wait`. If you receive a `[WAIT:...]` message and don't notify, the sender hangs forever.**

### Fire-and-Forget (no reply needed)

When you're just passing information and don't need a response, send without a tag. The receiver processes it but does NOT notify.

```bash
# Jira passes ticket details to coder — no tag, no wait
tmux-agent send coder "Here are the details for COM-128: Summary: Fix validation. Description: ..."

# Coder receives and uses the info, no notify needed
```

### Decision Rule

| Situation | Tag? | Sender waits? | Receiver notifies? |
|-----------|------|---------------|-------------------|
| You need a result back | `[WAIT:<your-name>]` | Yes (`tmux-agent wait`) | Yes (`tmux-agent notify`) |
| Just passing info, your job is done | No tag | No | No |
| User ran you directly (no tag in prompt) | No tag | N/A | No |

---

## Notify Protocol

### When to Notify

Notify ONLY when you received a `[WAIT:<name>]` tag AND you are in a tmux environment (environment context shows `Shell Type: tmux pane`).

If either condition is missing — no notify. Just do your work and stop.

### How to Notify

```bash
tmux-agent notify <name-from-WAIT-tag> "DONE: <full summary>"
```

### What to Include

Your notify message is the ONLY way results reach the sender. Be complete:

- **Code changes**: files changed, branch, push status, MR URL, test results
- **Jira data**: ticket key, summary, status, assignee, description, acceptance criteria, comments
- **Build/test**: pass/fail, error details, command output

---

## Rules

1. **`[WAIT:...]` tag = must notify.** The sender is blocking. If you don't notify, they hang.
2. **No tag = no notify.** Just do the work.
3. **Notify LAST** — finish all work first, notify as your final action.
4. **Be complete** — include everything the sender needs in the notify message.
5. **Tag when you need a reply** — always use `[WAIT:<your-name>]` when you need results back.
6. **Don't tag fire-and-forget** — if you're just passing data and moving on, no tag.
7. **You are autonomous** — never wait for user input. Execute fully, then notify (if tagged).
