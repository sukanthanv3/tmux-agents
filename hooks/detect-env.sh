#!/usr/bin/env bash
# Detect the shell environment the agent is running in
# Output is injected into agent context via agentSpawn hook
# chmod +x ~/.kiro/scripts/detect-env.sh

echo "=== Environment Context ==="

# Detect tmux
if [ -n "$TMUX" ] && [ -n "$TMUX_PANE" ]; then
  # Always target OUR pane ($TMUX_PANE); without -t tmux reports the active pane.
  T="$TMUX_PANE"
  TMUX_SESSION=$(tmux display-message -p -t "$T" '#S' 2>/dev/null)
  TMUX_WINDOW=$(tmux display-message -p -t "$T" '#W' 2>/dev/null)
  TMUX_PANE_INDEX=$(tmux display-message -p -t "$T" '#P' 2>/dev/null)
  PANE_COUNT=$(tmux list-panes -t "$T" 2>/dev/null | wc -l | tr -d ' ')
  echo "Shell Type: tmux pane"
  echo "Tmux Session: $TMUX_SESSION"
  echo "Tmux Window: $TMUX_WINDOW"
  echo "Tmux Pane Index: $TMUX_PANE_INDEX"
  echo "Tmux Pane ID: $T"
  echo "Panes in Window: $PANE_COUNT"

  # tmux-agent runtime info (agent-to-agent messaging)
  if [ "$(tmux show-options -t "$TMUX_SESSION" -qv @tmux_agent 2>/dev/null)" = "1" ]; then
    MY_AGENT=$(tmux show-options -p -t "$T" -qv @agent 2>/dev/null)
    PEERS=$(tmux list-panes -s -t "$TMUX_SESSION" -F '#{@agent}:#{pane_id}' 2>/dev/null |
      grep -v '^:' | grep -v "^${MY_AGENT:-<none>}:" | tr '\n' ' ')
    echo "tmux-agent Session: $TMUX_SESSION"
    echo "My Agent Name: ${MY_AGENT:-(not registered)}"
    echo "Peer Agents: ${PEERS:-(none)}"
    echo "Messaging: tmux-agent send <agent> \"<msg>\" | tmux-agent notify <agent> \"<result>\""
  fi
elif [ -n "$STY" ]; then
  echo "Shell Type: GNU screen session ($STY)"
else
  # Detect interactive vs non-interactive
  if [ -t 0 ] && [ -t 1 ]; then
    echo "Shell Type: interactive terminal"
  else
    echo "Shell Type: non-interactive (piped/scripted)"
  fi
fi

# TTY info
if TTY_NAME=$(tty 2>/dev/null); then
  echo "TTY: $TTY_NAME"
else
  echo "TTY: none (no controlling terminal)"
fi

# Parent process (useful for detecting how the agent was launched)
PARENT_PID=$PPID
PARENT_CMD=$(ps -o comm= -p "$PARENT_PID" 2>/dev/null || echo "unknown")
echo "Parent Process: $PARENT_CMD (PID: $PARENT_PID)"

# SSH detection
if [ -n "$SSH_CLIENT" ] || [ -n "$SSH_TTY" ]; then
  echo "Remote: yes (SSH session)"
else
  echo "Remote: no (local)"
fi

# Basic system info
echo "Host: $(hostname -s 2>/dev/null)"
echo "User: $(whoami)"
echo "CWD: $(pwd)"
echo "==========================="

exit 0
