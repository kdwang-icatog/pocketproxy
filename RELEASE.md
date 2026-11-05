口袋代理发布步骤(给维护者)
==========================
一次性准备(1.0.9 起)
A. 签名密钥:在自己的电脑上(Windows 用 Git Bash)运行 sh docs/pocketproxy/keygen.sh。
   - 私钥在 ~/.pocketproxy-sign/ed25519.pem。马上离线备份(U 盘或密码管理器)。
     绝不能放进 git、香港服务器、网盘;丢了就发不了新版(已装的手机只能重新运行安装命令)。
   - 公钥会写进 pocketproxy.py 的 SIGN_PUBKEY 和 install.sh 的 PUBKEY,这两个文件要 git 提交(公钥可以公开)。
B. GitHub 两个公开仓库(都在网页上新建,勾选"Add a README file",默认分支 main):
   - 发布仓库 kdwang-icatog/d-i13whabio2:只放发布文件(程序、签名、安装脚本、版本号、说明),当备用下载地址,
     手机从 https://raw.githubusercontent.com/kdwang-icatog/d-i13whabio2/main/ 下载。名字故意不带 pocketproxy。
   - 源码仓库 kdwang-icatog/pocketproxy:公开源码(本目录除"上架评估.md"外的文件)。
   publish.sh 用本机 SSH 密钥推送这两个仓库(本地副本在 ~/.pocketproxy-repos/,只由脚本写),不需要 gh 命令行。
   换仓库名的话,改 pocketproxy.py 的 GITHUB_BASE、install.sh 的 GH、README.md 的备用安装命令,
   发布时用 DIST_REPO=用户名/仓库名 SRC_REPO=用户名/仓库名 sh publish.sh。
C. 反馈邮箱 pocket-feedback.ride078@passinbox.com:在 Proton 里建一条规则——收件人是这个地址的邮件放进"口袋代理反馈"文件夹。
   这是 Proton Pass 的匿名别名,转发到主邮箱,主邮箱地址不会暴露。
   报告只在正文里,带附件的一律不要打开。这个地址被垃圾邮件盯上时,在 Proton Pass 里停用它、新建一个别名,
   改 pocketproxy.py 的 FEEDBACK_EMAIL 和 README.md 后发新版。

每次发布
1. 改 pocketproxy.py,把 VERSION 加一(小修改末位加一,如 1.0.9 → 1.0.10)。只会自动升级到更高的版本号。
2. 在 CHANGELOG.md 最上面加一条:版本号、日期、改了什么。用户能看懂的话,不写代码细节。
3. 本机测试:python -I -B pocketproxy.py,用 curl 测 http://本机地址:8080/ 、HTTP、HTTPS、SOCKS5 代理,
   以及界面 http://127.0.0.1:8090 的 /api/status、/api/report。
4. 运行 sh docs/pocketproxy/publish.sh:签名 → 上传香港 /var/www/rpa-update/pocketproxy/ 并核对哈希 →
   推送 GitHub 发布仓库并核对(GitHub 失败只提醒,不影响香港那份)→ 同步源码到公开代码仓库。
5. git 提交(先 git pull --rebase)。
   远程让 iPhone 立即升级(不用等 1 小时,在同一局域网的电脑上;--noproxy '' 防止本机 NO_PROXY 把 127.0.0.1 直连):
   curl --noproxy '' -x http://iPhone地址:8080 -X POST -d '{}' http://127.0.0.1:8090/api/update
   远程看日志:浏览器打开 http://iPhone地址:8080/log 。
6. 已装的 iPhone(1.0.3 起):1 小时内在没有连接时自动升级;新版 90 秒内起不来会自动换回旧版,并且不再自动升级到这个版本
   (修好后发一个更高的版本号即可)。1.0.9 起签名不对的新版一律不装。急用就在界面点升级,或在 iSH 里重跑安装命令。
