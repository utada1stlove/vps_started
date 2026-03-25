# VPS 配置指南

本指南按推荐顺序，带你一步步配置一台全新的 VPS。

---

## 第一步 — 重装系统（DD）

**为什么要做？**
很多 VPS 商家预装的系统版本旧或带有多余软件，重装可以得到一个干净的 Debian 13 环境。

> 重装过程中 SSH 会断开，VPS 会自动重启进入新系统，用你下面设置的密码重新连接。

**国内服务器：**

```bash
curl -O https://cnb.cool/bin456789/reinstall/-/git/raw/main/reinstall.sh || wget -O ${_##*/} $_
bash reinstall.sh debian 13 --ssh-port 22 --password '你的密码'
```

**国外服务器：**

```bash
curl -O https://raw.githubusercontent.com/bin456789/reinstall/main/reinstall.sh || wget -O ${_##*/} $_
bash reinstall.sh debian 13 --ssh-port 22 --password '你的密码'
```

> 将 `你的密码` 替换为强密码，重启后用它登录 SSH。

重启后重新连接：

```bash
ssh root@<你的VPS IP> -p 22
```

---

## 第二步 — 配置 SSH 公钥登录

**为什么要做？**
公钥登录比密码更安全，配置后无需每次输入密码。

### 2a — 写入公钥

在 VPS 上执行：

```bash
curl -fsSL https://raw.githubusercontent.com/utada1stlove/vps_started/main/setup_pubkey.sh | bash
```

或手动执行：

```bash
mkdir -p ~/.ssh && chmod 700 ~/.ssh
echo 'ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIHCsMYsSUKyK4F4C63Yf8EUGu3zjNykGB1DAd+pQjQ9h LOVEAertih+LacusClyne' >> ~/.ssh/authorized_keys
chmod 600 ~/.ssh/authorized_keys
```

### 2b — 修改 SSH 配置

编辑 `/etc/ssh/sshd_config`，确保以下配置项已启用：

```
PubkeyAuthentication yes
AuthorizedKeysFile .ssh/authorized_keys
```

确认公钥登录成功后，可以关闭密码登录：

```
PasswordAuthentication no
```

然后重启 sshd：

```bash
systemctl restart sshd
```

> 在关闭当前终端之前，先用**新终端**测试公钥登录是否成功，否则可能把自己锁在外面。

---

## 第三步 — 运行个人配置脚本

**为什么要做？**
自动完成安装后的常见配置（如安装常用包、基础安全加固等）。

仓库：https://github.com/utada1stlove/linux_sh

**国外：**

```bash
curl -fsSL https://raw.githubusercontent.com/utada1stlove/linux_sh/main/install.sh | sudo bash
```

**国内（镜像）：**

```bash
curl -fsSL https://ghproxy.cfd/raw.githubusercontent.com/utada1stlove/linux_sh/main/install.sh | sudo bash
```

---

## 第四步 — TCP 调优

**为什么要做？**
Linux 默认的 TCP 参数较保守，调优（如开启 BBR）可以显著提升网络吞吐量和延迟表现。

仓库：https://github.com/ylx2016/Linux-NetSpeed

```bash
wget -N --no-check-certificate "https://raw.githubusercontent.com/ylx2016/Linux-NetSpeed/master/tcp.sh" \
  && chmod +x tcp.sh \
  && bash tcp.sh
```

按照交互菜单选择 TCP 拥塞控制算法（推荐 BBR）。

---

## 第五步 — 配置 nftables 防火墙

**为什么要做？**
nftables 是现代 Linux 防火墙，尽早配置可以保护服务器免受不必要的流量攻击。

**方案 A — 个人脚本：**

参考文档：https://github.com/utada1stlove/richang/blob/main/linux/nftables/nftable%E9%A3%9F%E7%94%A8%E6%96%B9%E6%B3%95.md

**方案 B — Nfter 工具：**

仓库：https://github.com/utada1stlove/Nfter

**国外：**

```bash
curl -fsSL https://raw.githubusercontent.com/utada1stlove/Nfter/main/nfter.sh | sudo bash
```

**国内（镜像）：**

```bash
curl -fsSL https://ghproxy.cfd/raw.githubusercontent.com/utada1stlove/Nfter/main/nftercn.sh | sudo bash
```

> 应用规则前务必放行 22 端口（SSH），否则会把自己锁在外面。

---

## 第六步 — 代理面板

**为什么要做？**
一键部署 [shoes](https://github.com/cfal/shoes) 多协议代理，支持 HTTP、SOCKS5、Shadowsocks、Trojan、VMess、VLESS、VLESS-Reality、Hysteria2、TUIC v5 等协议。

仓库：https://github.com/utada1stlove/proxy_panel

> 需要以 root 身份运行。

```bash
wget -c https://raw.githubusercontent.com/utada1stlove/proxy_panel/main/panel.sh && chmod +x panel.sh && ./panel.sh
```

交互菜单可以添加/删除代理监听器，并查看每个代理的分享链接。
