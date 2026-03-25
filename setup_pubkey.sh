#!/bin/bash
# One-liner public key setup script
# Usage: bash setup_pubkey.sh

set -e

PUBKEY="ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIHCsMYsSUKyK4F4C63Yf8EUGu3zjNykGB1DAd+pQjQ9h LOVEAertih+LacusClyne"

mkdir -p ~/.ssh
chmod 700 ~/.ssh

if grep -qF "$PUBKEY" ~/.ssh/authorized_keys 2>/dev/null; then
    echo "Public key already exists in authorized_keys, skipping."
else
    echo "$PUBKEY" >> ~/.ssh/authorized_keys
    echo "Public key added to ~/.ssh/authorized_keys"
fi

chmod 600 ~/.ssh/authorized_keys
echo "Done. You can now login with your private key."
