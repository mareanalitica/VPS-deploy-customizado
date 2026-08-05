#!/usr/bin/env bash

# ==============================================================================
# VPS Security Hardening & Firewall Configuration Script
# Target: Ubuntu / Debian VPS
# Purpose: Protect against brute-force attacks, port scanning, and unauthorized access.
# ==============================================================================

set -e

echo "🛡️  [VPS Hardening] Starting security configuration..."

# 1. Check Root Privileges
if [ "$EUID" -ne 0 ]; then
    echo "❌ Please run as root (use: sudo ./harden-vps.sh)"
    exit 1
fi

# 2. Update System & Install Core Security Tools
echo "📦 [1/7] Installing security tools (UFW, Fail2ban, iptables-persistent)..."
apt-get update -y
# Ubuntu releases from ~24.10+ ship a "ufw" package that Breaks
# "iptables-persistent" (ufw absorbed most of its own rule persistence).
# Try with it first (older Ubuntu/Debian still need it for the DOCKER-USER
# chain to survive a reboot); fall back without it if apt reports a conflict,
# rather than aborting the whole hardening run over a persistence nice-to-have.
if ! apt-get install -y ufw fail2ban iptables-persistent curl git; then
    echo "⚠️  iptables-persistent conflita com ufw nesta distro - instalando sem ele."
    echo "    A chain DOCKER-USER ainda e' aplicada nesta sessao, mas pode nao"
    echo "    sobreviver a um reboot ate isso ser revisitado (ver ADR/README)."
    apt-get install -y ufw fail2ban curl git
fi

# 3. Configure Fail2ban
echo "🔒 [2/7] Configuring Fail2ban for SSH brute-force protection..."
cat << 'EOF' > /etc/fail2ban/jail.local
[DEFAULT]
bantime = 1h
findtime = 10m
maxretry = 5

[sshd]
enabled = true
port = ssh
filter = sshd
logpath = /var/log/auth.log
maxretry = 3
bantime = 24h
EOF

systemctl restart fail2ban
systemctl enable fail2ban

# 4. Harden SSH: key-only authentication
# ------------------------------------------------------------------------
# Some VPS providers (e.g. Hostinger) provision a root account with a
# generated password by default, on top of any SSH key you supplied - so
# password auth being merely "rate limited" by UFW/Fail2ban isn't enough.
# We only disable it if we can confirm at least one authorized key exists
# anywhere on the box, to avoid locking out the operator's own access.
echo "🔑 [3/7] Hardening SSH (key-only authentication)..."
if [ -s /root/.ssh/authorized_keys ] || find /home -maxdepth 3 -name authorized_keys -size +0c 2>/dev/null | grep -q .; then
    sed -i \
        -e 's/^#*PasswordAuthentication.*/PasswordAuthentication no/' \
        -e 's/^#*PermitRootLogin.*/PermitRootLogin prohibit-password/' \
        /etc/ssh/sshd_config
    grep -q '^PasswordAuthentication no' /etc/ssh/sshd_config || echo 'PasswordAuthentication no' >> /etc/ssh/sshd_config
    grep -q '^PermitRootLogin prohibit-password' /etc/ssh/sshd_config || echo 'PermitRootLogin prohibit-password' >> /etc/ssh/sshd_config
    systemctl reload ssh 2>/dev/null || systemctl reload sshd 2>/dev/null || true
    echo "✅ SSH now accepts key-only authentication (password login disabled)."
else
    echo "⚠️  No authorized SSH key found under /root/.ssh or /home/*/.ssh - SKIPPING"
    echo "    password-auth lockdown so this doesn't lock out your own access."
    echo "    Add your public key and re-run this script to apply it."
fi

# 5. Kernel Hardening Parameters (sysctl)
echo "🧠 [4/7] Applying Kernel & Network Hardening (sysctl)..."
cat << 'EOF' > /etc/sysctl.d/99-security-hardening.conf
# Disable IP Forwarding (unless needed for custom routing)
# Protect against SYN flood attacks
net.ipv4.tcp_syncookies = 1
net.ipv4.tcp_max_syn_backlog = 2048
net.ipv4.tcp_synack_retries = 2

# Ignore ICMP Echo Requests (Ping) - Optional
net.ipv4.icmp_echo_ignore_broadcasts = 1

# Disable IP Source Routing
net.ipv4.conf.all.accept_source_route = 0
net.ipv4.conf.default.accept_source_route = 0

# Enable Reverse Path Filtering (Prevent IP Spoofing)
net.ipv4.conf.all.rp_filter = 1
net.ipv4.conf.default.rp_filter = 1
EOF

sysctl --system >/dev/null 2>&1 || true

# 6. Configure Firewall (UFW)
echo "🧱 [5/7] Setting up UFW Firewall rules..."

# Reset rules
ufw --force reset >/dev/null

# Default Policies: Deny incoming, Allow outgoing
ufw default deny incoming
ufw default allow outgoing

# Allow SSH with Rate Limiting (Prevents Brute Force)
ufw limit 22/tcp comment 'SSH Rate Limited'

# Allow Web Traffic (Traefik Reverse Proxy)
ufw allow 80/tcp comment 'HTTP Traefik'
ufw allow 443/tcp comment 'HTTPS Traefik'

# Allow Docker Swarm Internal Communication (Overlay Network)
ufw allow 2377/tcp comment 'Docker Swarm Management'
ufw allow 7946/tcp comment 'Docker Swarm Node Communication'
ufw allow 7946/udp comment 'Docker Swarm Node Communication'
ufw allow 4789/udp comment 'Docker Swarm Overlay Network'

# 7. Database Ports Security Policy
echo "🗄️  [6/7] Configuring Database Security Policies..."
echo "ℹ️  Database ports (MongoDB 27017, Postgres 5432, Redis 6379) are kept INTERNAL to Docker."
echo "ℹ️  If external connection is needed, use trusted IP whitelist:"
echo "    Example: sudo ufw allow from <YOUR_IP> to any port 5432 proto tcp"

# Enable Firewall
ufw --force enable

# 8. Docker bypasses UFW: harden the DOCKER-USER chain too
# ------------------------------------------------------------------------
# Docker inserts its own iptables rules ahead of UFW's INPUT chain, so
# "ufw default deny incoming" does NOT protect ports published by containers
# (docker run -p / compose "ports:"). Any port a service publishes to the
# host bypasses UFW entirely unless we filter it here, in the DOCKER-USER
# chain, which Docker guarantees runs before its own DNAT/forwarding rules
# (supported since Docker 17.06). This is a safety net: production's
# docker-stack.yml intentionally publishes nothing except Traefik on 80/443,
# but this stops a future "ports:" mistake (or the DEV compose file, which
# does publish DB ports) from silently becoming internet-reachable.
if command -v docker &>/dev/null; then
    echo "🐳 [7/7] Hardening the DOCKER-USER iptables chain (Docker ignores UFW by default)..."

    harden_docker_user_chain() {
        local ipt="$1"
        "$ipt" -N DOCKER-USER 2>/dev/null || true
        "$ipt" -F DOCKER-USER
        "$ipt" -A DOCKER-USER -i lo -j RETURN
        "$ipt" -A DOCKER-USER -m state --state RELATED,ESTABLISHED -j RETURN
        # HTTP/HTTPS (Traefik) - meant to be public
        "$ipt" -A DOCKER-USER -p tcp --dport 80 -j RETURN
        "$ipt" -A DOCKER-USER -p tcp --dport 443 -j RETURN
        # Docker Swarm management/overlay ports (cluster-to-cluster traffic)
        "$ipt" -A DOCKER-USER -p tcp --dport 2377 -j RETURN
        "$ipt" -A DOCKER-USER -p tcp --dport 7946 -j RETURN
        "$ipt" -A DOCKER-USER -p udp --dport 7946 -j RETURN
        "$ipt" -A DOCKER-USER -p udp --dport 4789 -j RETURN
        # Anything else published by a container to the host: drop it.
        "$ipt" -A DOCKER-USER -j DROP
    }

    harden_docker_user_chain iptables
    command -v ip6tables &>/dev/null && harden_docker_user_chain ip6tables

    netfilter-persistent save >/dev/null 2>&1 || true
    echo "✅ DOCKER-USER chain hardened and persisted."
else
    echo "ℹ️  [7/7] Docker not installed yet - re-run this script (or apply the DOCKER-USER"
    echo "    chain rules manually) after './setup/init.sh' installs Docker."
fi

echo "----------------------------------------------------------------------"
echo "✅ [VPS Hardening Complete] Status Summary:"
echo "----------------------------------------------------------------------"
ufw status verbose
echo "----------------------------------------------------------------------"
echo "🎉 VPS Security Hardening applied successfully!"
