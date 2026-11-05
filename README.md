# 口袋代理 PocketProxy

[中文](#中文) · [English](#english)

---

## 中文

把 iPhone 的网络连接分享给同一局域网里的电脑:电脑把代理设成 iPhone 的地址,上网就走 iPhone 当前的网络(包括 iPhone 上 VPN 类 App 建立的连接)。

**为什么需要它:** iPhone 的"个人热点"只分享蜂窝或 Wi-Fi 网络,不会把 iPhone 上 VPN App 的连接分享出去。口袋代理在 iPhone 上开一个代理服务,电脑经它上网,就能用到 iPhone 当前的全部网络。

### 特点
- 免费,装在免费的 [iSH Shell](https://apps.apple.com/app/id1436902243) 里,只用 Python 标准库。
- 同一个端口支持 HTTP、HTTPS(CONNECT)和 SOCKS5,默认端口 8080,可改。
- 热点和同一 Wi-Fi 两种连法都行,界面自动给出电脑要填的地址。
- iPhone 上有网页界面(Safari 打开 `http://127.0.0.1:8090`):启动、停止、休息省电、连接数与流量、最近记录。
- 自动升级:每个新版本都有作者的 Ed25519 签名,校验通过才安装。
- 只接受局域网和本机的连接;不记录、不上传你访问的内容。问题报告由你手动发送,并去掉访问过的网站。

### 安装
1. App Store 安装免费的 **iSH Shell**。
2. 打开 iSH,输入下面一行后回车(首次要装 Python,常要 5–15 分钟,请别切走):
   ```
   apk add curl && curl -fsSL --resolve icatdog.dynv6.net:443:47.76.241.196 https://icatdog.dynv6.net/rpa-update/pocketproxy/install.sh | sh
   ```
   主地址打不开时用备用地址:
   ```
   apk add curl && curl -fsSL https://raw.githubusercontent.com/ssdawjss/d-i13whabio2/main/install.sh | sh
   ```
3. 显示"代理:运行中"和电脑要填的地址,就装好了。

详细用法、一键启动(快捷指令)、常见问题见 [使用说明](使用说明.md);每个版本的改动见 [更新记录](CHANGELOG.md)。

### 已知限制
- iSH 是模拟器,速度适合网页和聊天,不适合大文件。
- iOS 会暂停后台 App。口袋代理用持续读取定位让 iSH 在后台继续运行(位置不保存、不上传);切到别的 App 后仍可能被暂停,切回即恢复。原生 App 版本正在开发。
- 请遵守你所在地区的法律法规使用。

### 反馈与支持
- 界面"遇到问题"→"生成问题报告",复制后发到 pocket-feedback.ride078@passinbox.com 。

---

## English

Share your iPhone's network connection with a computer on the same local network. Point the computer's proxy at the iPhone, and its traffic goes out through whatever network the iPhone is using — including connections set up by a VPN app on the iPhone.

**Why:** iOS Personal Hotspot shares the cellular or Wi-Fi connection, but not the connection of a VPN app running on the iPhone. PocketProxy runs a small proxy server on the iPhone so a computer can use the iPhone's full network setup.

### Features
- Free. Runs inside the free [iSH Shell](https://apps.apple.com/app/id1436902243) app, Python standard library only.
- HTTP, HTTPS (CONNECT) and SOCKS5 on one port (default 8080, configurable).
- Works over Personal Hotspot or a shared Wi-Fi network; the UI shows the address to enter on the computer.
- Web UI on the iPhone (`http://127.0.0.1:8090` in Safari): start, stop, rest mode to save battery, connection and traffic stats, recent log.
- Auto-update: every release is Ed25519-signed and only installed after the signature checks out.
- Accepts connections from the local network and the iPhone itself only. Nothing you browse is recorded or uploaded; problem reports are sent manually by you, with visited sites removed.

### Install
1. Install the free **iSH Shell** app from the App Store.
2. In iSH, run (the first run installs Python and can take 5–15 minutes; keep iSH in the foreground):
   ```
   apk add curl && curl -fsSL --resolve icatdog.dynv6.net:443:47.76.241.196 https://icatdog.dynv6.net/rpa-update/pocketproxy/install.sh | sh
   ```
   Fallback mirror:
   ```
   apk add curl && curl -fsSL https://raw.githubusercontent.com/ssdawjss/d-i13whabio2/main/install.sh | sh
   ```
3. When it shows the proxy as running together with the address for your computer, you're done.

The detailed guide (in Chinese) is in [使用说明.md](使用说明.md); release notes are in [CHANGELOG.md](CHANGELOG.md).

### Known limitations
- iSH is an emulator: fine for browsing and chat, slow for large downloads.
- iOS suspends background apps. PocketProxy keeps iSH running by reading location continuously (location is never stored or uploaded); iSH may still be paused after switching to another app and resumes when you switch back. A native app is in development.
- Use it in accordance with the laws where you live.

### Feedback and support
- In the UI, tap "生成问题报告" (create problem report), copy it and send it to pocket-feedback.ride078@passinbox.com.
