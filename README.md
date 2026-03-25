# VPS Setup Guide

This guide walks you through setting up a fresh VPS from scratch, in the recommended order.

---

## Step 1 — Reinstall the OS (DD)

**Why?** Most VPS providers ship outdated or bloated OS images. Reinstalling gives you a clean, minimal Debian 13.

> You will lose SSH access during reinstall. The VPS reboots automatically. Reconnect with the password you set below.

**Outside China:**

```bash
curl -O https://raw.githubusercontent.com/bin456789/reinstall/main/reinstall.sh || wget -O ${_##*/} $_
bash reinstall.sh debian 13 --ssh-port 22 --password 'YourPasswordHere'
```

**Mainland China (CN mirror):**

```bash
curl -O https://cnb.cool/bin456789/reinstall/-/git/raw/main/reinstall.sh || wget -O ${_##*/} $_
bash reinstall.sh debian 13 --ssh-port 22 --password 'YourPasswordHere'
```

> Replace `YourPasswordHere` with a strong password. You will use it to SSH in after reboot.

After reboot, reconnect:

```bash
ssh root@<your-vps-ip> -p 22
```

---

## Step 2 — SSH Public Key

**Why?** Key-based auth is more secure than passwords.

### 2a — Add public key

Run on the VPS:

```bash
curl -fsSL https://raw.githubusercontent.com/utada1stlove/vps_started/main/setup_pubkey.sh | bash
```

Or manually:

```bash
mkdir -p ~/.ssh && chmod 700 ~/.ssh
echo 'ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIHCsMYsSUKyK4F4C63Yf8EUGu3zjNykGB1DAd+pQjQ9h LOVEAertih+LacusClyne' >> ~/.ssh/authorized_keys
chmod 600 ~/.ssh/authorized_keys
```

### 2b — Enable key auth in sshd_config

Edit `/etc/ssh/sshd_config`:

```
PubkeyAuthentication yes
AuthorizedKeysFile .ssh/authorized_keys
```

Optionally disable password login after confirming key login works:

```
PasswordAuthentication no
```

Restart sshd:

```bash
systemctl restart sshd
```

> Test key login in a **new terminal** before closing your current session.

---

## Step 3 — Personal Setup Script

**Why?** Automates common post-install tasks.

Repo: https://github.com/utada1stlove/linux_sh

**Outside China:**

```bash
curl -fsSL https://raw.githubusercontent.com/utada1stlove/linux_sh/main/install.sh | sudo bash
```

**Mainland China (via mirror):**

```bash
curl -fsSL https://ghproxy.cfd/raw.githubusercontent.com/utada1stlove/linux_sh/main/install.sh | sudo bash
```

---

## Step 4 — TCP Tuning

**Why?** Tuning TCP (e.g. enabling BBR) significantly improves network throughput and latency.

Repo: https://github.com/ylx2016/Linux-NetSpeed

```bash
wget -N --no-check-certificate "https://raw.githubusercontent.com/ylx2016/Linux-NetSpeed/master/tcp.sh" \
  && chmod +x tcp.sh \
  && bash tcp.sh
```

Follow the interactive menu. BBR is recommended.

---

## Step 5 — Firewall with nftables

**Why?** nftables protects your server from unwanted traffic.

**Option A — Personal script:**

See: https://github.com/utada1stlove/richang/blob/main/linux/nftables/nftable%E9%A3%9F%E7%94%A8%E6%96%B9%E6%B3%95.md

**Option B — Nfter tool:**

Repo: https://github.com/utada1stlove/Nfter

**Outside China:**

```bash
curl -fsSL https://raw.githubusercontent.com/utada1stlove/Nfter/main/nfter.sh | sudo bash
```

**Mainland China (via mirror):**

```bash
curl -fsSL https://ghproxy.cfd/raw.githubusercontent.com/utada1stlove/Nfter/main/nftercn.sh | sudo bash
```

> Make sure to allow port 22 (SSH) in your rules before applying, or you will lock yourself out.

---

## Step 6 — Proxy Panel

**Why?** One-click deployment of [shoes](https://github.com/cfal/shoes), a multi-protocol proxy. Supports HTTP, SOCKS5, Shadowsocks, Trojan, VMess, VLESS, VLESS-Reality, Hysteria2, TUIC v5, and more.

Repo: https://github.com/utada1stlove/proxy_panel

> Must be run as root.

```bash
wget -c https://raw.githubusercontent.com/utada1stlove/proxy_panel/main/panel.sh && chmod +x panel.sh && ./panel.sh
```

The interactive menu lets you add/remove listeners and view share URLs for each proxy.
