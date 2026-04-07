#!/usr/bin/env bash
# Check if agent-browser is installed and install if needed
# Usage: check_agent_browser.sh

if command -v agent-browser &> /dev/null; then
    echo "✓ agent-browser is installed"
    exit 0
fi

echo "agent-browser not found. Install it? (y/n)"
read -r REPLY

if [[ $REPLY =~ ^[Yy]$ ]]; then
    echo "Installing agent-browser..."
    npm install -g agent-browser
    agent-browser install
    echo "✓ agent-browser installed"
else
    echo "Skipping agent-browser installation"
    exit 0
fi
