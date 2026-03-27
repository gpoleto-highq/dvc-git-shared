# Auto-start SSH agent
if ! pgrep -u "$USER" ssh-agent > /dev/null; then
    ssh-agent > ~/.ssh/agent.env
fi
if [[ ! "$SSH_AUTH_SOCK" ]]; then
    source ~/.ssh/agent.env > /dev/null
fi
ssh-add -l &>/dev/null || ssh-add ~/.ssh/id_ed25519
