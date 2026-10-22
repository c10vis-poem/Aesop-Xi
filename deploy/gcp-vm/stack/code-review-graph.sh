#!/bin/bash
# Install code-review-graph from the c10vis-poem fork (via uv) as an HTTP MCP service on 127.0.0.1:5555.
set -euo pipefail
command -v uv >/dev/null || { sudo apt-get install -y -qq pipx >/dev/null && pipx install -q uv && export PATH="$HOME/.local/bin:$PATH"; }
export PATH="$HOME/.local/bin:$PATH"
uv tool install --force --python 3.12 "git+https://github.com/c10vis-poem/NvAEx-code-review-graph.git@main" >/dev/null
echo "code-review-graph $(code-review-graph --version 2>/dev/null || echo installed)"

sudo tee /etc/systemd/system/code-review-graph.service >/dev/null <<EOF
[Unit]
Description=code-review-graph MCP (HTTP)
After=network-online.target
Wants=network-online.target

[Service]
User=$USER
WorkingDirectory=$HOME/repos
ExecStart=$HOME/.local/bin/code-review-graph serve --http --host 127.0.0.1 --port 5555
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
sudo systemctl daemon-reload
sudo systemctl enable --now code-review-graph
