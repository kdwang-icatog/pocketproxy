#!/bin/sh
# 生成口袋代理的发布签名密钥(只做一次),并把公钥写进 pocketproxy.py 和 install.sh。
# 用法(在维护者自己的电脑上,Windows 用 Git Bash): sh docs/pocketproxy/keygen.sh
# 私钥默认放在 ~/.pocketproxy-sign/ed25519.pem(可用环境变量 POCKETPROXY_KEY 改),绝不能放进 git、服务器或网盘。
set -e
cd "$(dirname "$0")"
KEY=${POCKETPROXY_KEY:-$HOME/.pocketproxy-sign/ed25519.pem}
if [ -f "$KEY" ]; then
  echo "已有私钥 $KEY,直接用它(不会覆盖)"
else
  mkdir -p "$(dirname "$KEY")"
  openssl genpkey -algorithm ed25519 -out "$KEY"
  chmod 600 "$KEY" 2>/dev/null || true
  echo "已生成私钥 $KEY"
  echo "!! 请马上把它备份到离线的地方(U 盘或密码管理器)。丢了就发不了新版,已装的手机只能重新运行安装命令。"
fi
PUB=$(openssl pkey -in "$KEY" -pubout | sed -n 2p)
sed -i "s|^SIGN_PUBKEY = '.*'|SIGN_PUBKEY = '$PUB'|" pocketproxy.py
sed -i "s|^PUBKEY='.*'|PUBKEY='$PUB'|" install.sh
echo "公钥已写入 pocketproxy.py 和 install.sh:$PUB"
echo "公钥可以公开,记得 git 提交这两个文件。"
