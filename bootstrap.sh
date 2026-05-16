#!/bin/bash
# bootstrap.sh — prep a fresh Ubuntu 22.04 VPS to run this playbook locally.
# Run as the target user on the VPS itself if you don't have a separate
# Ansible controller. Idempotent: re-running on a host that's already
# bootstrapped is a no-op aside from `apt-get update`.
#
# Why this exists: Ubuntu 22.04's apt ships ansible-core 2.12, which is
# too old for current Galaxy collection metadata and errors out with
# `CollectionDependencyProvider.find_matches() got an unexpected keyword
# argument 'identifier'` on `ansible-galaxy collection install`. We
# replace it with a pinned 2.16.x via pip --user.
set -euo pipefail

sudo apt-get update
sudo apt-get remove -y ansible-core || true
sudo apt-get install -y python3-pip python3-venv
pip install --user 'ansible-core==2.16.*'

# Ensure ~/.local/bin is on PATH for future shells.
if ! grep -qF 'HOME/.local/bin' "$HOME/.bashrc" 2>/dev/null; then
    echo 'export PATH="$HOME/.local/bin:$PATH"' >> "$HOME/.bashrc"
fi
export PATH="$HOME/.local/bin:$PATH"

# Install required collections.
ansible-galaxy collection install -r requirements.yml

echo
echo "Bootstrap complete."
echo "Re-source bashrc ('source ~/.bashrc') or restart shell, then:"
echo "  ansible-playbook -i inventory.ini.local playbook.yml --check --diff"
