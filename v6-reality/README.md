# IPv6-only VLESS Reality 安装器

适用于使用 systemd 的 Debian/Ubuntu VPS，安装 sing-box、VLESS Reality 和 XTLS Vision。入站只绑定检测到的公网 IPv6 地址。

## 使用

以 root 登录 VPS 后执行：

```bash
bash <(curl -fsSL https://xuedaibaw21.github.io/v6-reality/install.sh)
```

自定义端口：

```bash
PORT=8443 bash <(curl -fsSL https://xuedaibaw21.github.io/v6-reality/install.sh)
```

安装成功后，节点分享链接会显示在终端，并保存到：

```text
/root/vless-reality-info.txt
```

云服务器安全组需要另外允许对应的 IPv6 TCP 端口。
