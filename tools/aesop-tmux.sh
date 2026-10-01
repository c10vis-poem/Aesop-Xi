#!/data/data/com.termux/files/usr/bin/bash
# aesop-tmux.sh — Æsop-Xi orchestration tmux session layout
# Creates a session with windows for each pipeline component
set -euo pipefail

SESSION="aesop"
GCLOUD="$HOME/google-cloud-sdk/bin/gcloud"
VM="omniroute-brain"
ZONE="us-central1-a"
AGENT="${1:-claude}"  # pass engine name as arg: claude, deepseek, qwen, hermes

tmux kill-session -t "$SESSION" 2>/dev/null || true

# Window 0: Agent workspace (swappable engine)
tmux new-session -d -s "$SESSION" -n "$AGENT" -c "$HOME/storage/shared/Documents/NovAExorpus"

# Window 1: OmniRoute health monitor
tmux new-window -t "$SESSION" -n "omniroute"
tmux send-keys -t "$SESSION:omniroute" "watch -n 30 'curl -sf http://34.31.112.77:20128/api/monitoring/health 2>/dev/null || echo DOWN'" Enter

# Window 2: Terrestrial Brain monitor
tmux new-window -t "$SESSION" -n "tb"
tmux send-keys -t "$SESSION:tb" "watch -n 30 'curl -sf http://34.31.112.77:8000/ 2>/dev/null || echo DOWN'" Enter

# Window 3: mem0 (episodic memory)
tmux new-window -t "$SESSION" -n "mem0" -c "$HOME/storage/shared/Documents/NovAExorpus"

# Window 4: VM SSH (for managing OmniRoute + TB on the VM)
tmux new-window -t "$SESSION" -n "vm-ssh"
tmux send-keys -t "$SESSION:vm-ssh" "$GCLOUD compute ssh $VM --zone=$ZONE" Enter

# Window 5: Graphify
tmux new-window -t "$SESSION" -n "graphify" -c "$HOME/storage/shared/Documents/NovAExorpus"

# Window 6: Obsidian vault
tmux new-window -t "$SESSION" -n "obsidian" -c "$HOME/storage/shared/Documents/NovAExorpus"

# Window 7: code-review-graph
tmux new-window -t "$SESSION" -n "crg" -c "$HOME/repos/NovA-code-review-graph"

# Window 8: logs / scratch
tmux new-window -t "$SESSION" -n "logs"
tmux send-keys -t "$SESSION:logs" "echo 'Æsop pipeline logs window ready'" Enter

# Select agent window
tmux select-window -t "$SESSION:$AGENT"

echo "tmux session '$SESSION' created with 9 windows (agent: $AGENT):"
echo "  0:$AGENT     — Agent workspace (NovAExorpus)"
echo "  1:omniroute  — OmniRoute health monitor"
echo "  2:tb         — Terrestrial Brain health monitor"
echo "  3:mem0       — mem0 episodic memory"
echo "  4:vm-ssh     — SSH to GCP VM"
echo "  5:graphify   — Graphify workspace"
echo "  6:obsidian   — Obsidian vault directory"
echo "  7:crg        — code-review-graph workspace"
echo "  8:logs       — Logs / scratch"
echo ""
echo "Attach with: tmux attach -t aesop"
echo "Switch agent: bash $0 deepseek|qwen|hermes|claude"
