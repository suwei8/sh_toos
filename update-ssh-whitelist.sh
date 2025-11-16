#!/usr/bin/env bash

# Stop on errors and undefined variables.
set -euo pipefail

echo "Clearing iptables rules..."
sudo iptables -F
sudo iptables -X
sudo iptables -t nat -F
sudo iptables -t nat -X
sudo iptables -t mangle -F
sudo iptables -t mangle -X

echo "Setting default policies to ACCEPT..."
sudo iptables -P INPUT ACCEPT
sudo iptables -P FORWARD ACCEPT
sudo iptables -P OUTPUT ACCEPT

echo "Installing iptables-persistent..."
sudo apt install -y iptables-persistent

echo "Saving current firewall rules..."
sudo netfilter-persistent save

echo "iptables reset completed."
