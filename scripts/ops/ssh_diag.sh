#!/usr/bin/env bash
# Why can an outside client reach port 22 but never see an SSH banner?
# Run as root on the SSH host:   bash scripts/ops/ssh_diag.sh
set -uo pipefail
section() { echo; echo "== $* =="; }

section "sshd effective config"
if command -v sshd >/dev/null 2>&1; then
  sshd -T 2>/dev/null | grep -Ei "^(port|listenaddress|allowusers|allowgroups|denyusers|denygroups|permitrootlogin|passwordauthentication|pubkeyauthentication|kbdinteractiveauthentication|maxstartups|maxsessions|logingracetime|banner|usepam|permitemptypasswords)" || echo "sshd -T failed"
else
  echo "sshd binary not on PATH"
fi

section "listening sockets"
ss -ltnp 2>/dev/null | grep -E ':(22|2222)\b' || echo "nothing on 22"

section "local firewall"
if command -v ufw >/dev/null 2>&1; then ufw status verbose 2>/dev/null | head -20; else echo "no ufw"; fi
if command -v firewall-cmd >/dev/null 2>&1; then firewall-cmd --list-all 2>/dev/null | head -20; fi
echo "-- iptables filter input"
iptables -S INPUT 2>/dev/null | head -20 || echo "iptables not readable"
echo "-- nft"
nft list ruleset 2>/dev/null | head -40 || echo "no nft rules"

section "tcp wrappers"
for file in /etc/hosts.allow /etc/hosts.deny; do [ -f "$file" ] && { echo "-- $file"; grep -v '^#' "$file" | grep -v '^$' | head -10; }; done

section "fail2ban"
if command -v fail2ban-client >/dev/null 2>&1; then
  fail2ban-client status 2>/dev/null
  fail2ban-client status sshd 2>/dev/null || true
else
  echo "no fail2ban"
fi

section "cloud edge (what the kernel sees)"
echo "-- conntrack cap / sysctl"
sysctl net.ipv4.tcp_syncookies net.core.somaxconn net.ipv4.tcp_max_syn_backlog 2>/dev/null
echo "-- sshd journal, last 60 lines"
journalctl -u ssh -u sshd -n 60 --no-pager 2>/dev/null | tail -60 || tail -n 60 /var/log/auth.log 2>/dev/null

section "auth log, connection noise"
grep -Ei "closed|banner|refused|disconnect|invalid|preauth" /var/log/auth.log 2>/dev/null | tail -25 || echo "no /var/log/auth.log"

section "public interfaces"
ip -4 addr show 2>/dev/null | grep -E "inet |^[0-9]" | head -10

section "how the site is fronted"
ss -ltnp 2>/dev/null | grep -E ':(80|443)\b' || echo "nothing on 80/443 locally (edge proxy runs elsewhere)"
