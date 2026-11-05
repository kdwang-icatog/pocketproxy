#!/bin/sh
# 发布口袋代理:签名 → 传到香港服务器(主下载地址)→ 推到 GitHub 发布仓库(备用地址)→ 核对线上文件
#              → 把源码同步到 GitHub 公开代码仓库。
# 用法: sh docs/pocketproxy/publish.sh
# 需要:香港服务器 SSH 密钥;签名私钥(keygen.sh 生成);本机 SSH 密钥能推送 GitHub。
set -e
cd "$(dirname "$0")"
KEY=${POCKETPROXY_KEY:-$HOME/.pocketproxy-sign/ed25519.pem}
HK=${HK_SSH:-root@47.76.241.196}
DIST_REPO=${DIST_REPO:-ssdawjss/d-i13whabio2}   # 只放发布文件,名字故意不带 pocketproxy
SRC_REPO=${SRC_REPO:-kdwang-icatog/pocketproxy}       # 公开源码
WORK=${POCKETPROXY_WORK:-$HOME/.pocketproxy-repos}     # 两个仓库的本地副本放这里(不在本仓库里)
# GitHub 的 22 端口常被重置,默认走 ssh.github.com:443
export GIT_SSH_COMMAND=${GIT_SSH_COMMAND:-"ssh -o ConnectTimeout=20 -o Hostname=ssh.github.com -p 443"}
FILES="pocketproxy.py pocketproxy.py.sig install.sh version.txt README.txt CHANGELOG.txt"
SRC_FILES="pocketproxy.py install.sh keygen.sh publish.sh CHANGELOG.md RELEASE.md"
VER=$(sed -n "s/^VERSION = '\([0-9.]*\)'.*/\1/p" pocketproxy.py)
[ -n "$VER" ] || { echo "pocketproxy.py 里找不到 VERSION"; exit 1; }
grep -q "^$VER " CHANGELOG.md || { echo "CHANGELOG.md 里还没写 $VER 的更新记录"; exit 1; }
[ -f "$KEY" ] || { echo "找不到签名私钥 $KEY(第一次先运行 keygen.sh)"; exit 1; }
PUB=$(openssl pkey -in "$KEY" -pubout | sed -n 2p)
grep -q "^SIGN_PUBKEY = '$PUB'" pocketproxy.py || { echo "pocketproxy.py 里的公钥和私钥不配对(运行 keygen.sh)"; exit 1; }
grep -q "^PUBKEY='$PUB'" install.sh || { echo "install.sh 里的公钥和私钥不配对(运行 keygen.sh)"; exit 1; }
T=$(mktemp -d)
printf '%s\n' "$VER" > "$T/version.txt"
# 服务器发 .txt 不带编码,开头加 UTF-8 标记(BOM),Safari 直接打开才不乱码
printf '\357\273\277' > "$T/README.txt"; cat README.md >> "$T/README.txt"
printf '\357\273\277' > "$T/CHANGELOG.txt"; cat CHANGELOG.md >> "$T/CHANGELOG.txt"
cp pocketproxy.py install.sh "$T/"
# 签名,并马上用公钥验一遍(和手机上的校验方式一样)
openssl pkeyutl -sign -inkey "$KEY" -rawin -in "$T/pocketproxy.py" -out "$T/pocketproxy.py.sig"
{ echo '-----BEGIN PUBLIC KEY-----'; echo "$PUB"; echo '-----END PUBLIC KEY-----'; } > "$T/pub.pem"
openssl pkeyutl -verify -pubin -inkey "$T/pub.pem" -rawin -in "$T/pocketproxy.py" -sigfile "$T/pocketproxy.py.sig" >/dev/null \
  || { echo "签名自检失败,没有发布"; exit 1; }
rm -f "$T/pub.pem"
echo "已签名 $VER"

# 1) 香港服务器(主下载地址)
ssh -o ConnectTimeout=20 "$HK" 'mkdir -p /var/www/rpa-update/pocketproxy'
(cd "$T" && scp -q -o ConnectTimeout=20 $FILES "$HK":/var/www/rpa-update/pocketproxy/)
for f in $FILES; do
  a=$(sha256sum "$T/$f" | cut -c1-16)
  b=$(curl -fsSL -m 30 --resolve icatdog.dynv6.net:443:47.76.241.196 "https://icatdog.dynv6.net/rpa-update/pocketproxy/$f" | sha256sum | cut -c1-16)
  [ "$a" = "$b" ] && echo "OK   香港 $f" || { echo "不一致 香港 $f(本地 $a 线上 $b)"; exit 1; }
done

# 仓库本地副本:没有就 clone;有就对齐远程(这两个副本只由本脚本写,不在里面手改)
sync_repo() {  # $1=owner/name  $2=本地目录
  if [ -d "$2/.git" ]; then
    git -C "$2" fetch -q origin && git -C "$2" reset -q --hard origin/main
  else
    mkdir -p "$(dirname "$2")" && git clone -q -c core.autocrlf=false "git@github.com:$1.git" "$2" || return 1
  fi
  # 公开仓库用 GitHub 隐私邮箱提交,不暴露真实邮箱;不做换行转换(手机上的脚本必须是 LF)
  git -C "$2" config core.autocrlf false
  git -C "$2" config user.name "${GIT_PUB_NAME:-kdwang-icatog}"
  git -C "$2" config user.email "${GIT_PUB_EMAIL:-279066644+kdwang-icatog@users.noreply.github.com}"
  # 发布仓库在组织 ssdawjss 下,提交用中性署名,不关联个人账号
  if [ "$1" = "$DIST_REPO" ]; then
    git -C "$2" config user.name "release"
    git -C "$2" config user.email "release@localhost.invalid"
  fi
  # 仓库转移后旧地址会跳转,远程地址跟着改成新的
  git -C "$2" remote set-url origin "git@github.com:$1.git"
}
# 只有内容变了才提交并推送
commit_push() {  # $1=本地目录 $2=提交说明
  git -C "$1" add -A
  if git -C "$1" diff --cached --quiet; then echo "     (没有变化)"; return 0; fi
  git -C "$1" -c core.autocrlf=false commit -q -m "$2" && git -C "$1" push -q origin HEAD:main
}

# 2) GitHub 发布仓库(备用地址)。失败只提醒,香港那份已经能用
D="$WORK/dist"
if sync_repo "$DIST_REPO" "$D" && (cd "$T" && cp $FILES "$D/") && commit_push "$D" "口袋代理 $VER"; then
  echo "已推送发布文件到 $DIST_REPO,核对线上文件(raw 有几分钟缓存)"
  i=0
  while :; do
    bad=
    for f in $FILES; do
      a=$(sha256sum "$T/$f" | cut -c1-16)
      b=$(curl -fsSL -m 60 -H 'Cache-Control: no-cache' "https://raw.githubusercontent.com/$DIST_REPO/main/$f" | sha256sum | cut -c1-16)
      [ "$a" = "$b" ] || bad="$bad $f"
    done
    [ -z "$bad" ] && { echo "OK   GitHub 发布仓库 $FILES"; break; }
    i=$((i + 1)); [ $i -ge 12 ] && { echo "提醒 GitHub 发布仓库还不一致:$bad(多半是缓存,过几分钟再看)"; break; }
    sleep 30
  done
else
  echo "提醒:GitHub 发布仓库推送失败,备用地址还是旧版(香港已发布,不影响使用)"
fi

# 3) GitHub 公开代码仓库
S="$WORK/src"
# 仓库首页用中英文说明 README.github.md;给手机看的使用说明 README.md 在仓库里叫"使用说明.md";
# 有 FUNDING.yml 就放到 .github/(仓库页的 Sponsor 按钮);ios/ 是原生 App 源码(带 GitHub Actions 编译)
copy_src() {
  cp $SRC_FILES "$S/" && cp README.github.md "$S/README.md" && cp README.md "$S/使用说明.md" || return 1
  if [ -f FUNDING.yml ]; then mkdir -p "$S/.github" && cp FUNDING.yml "$S/.github/FUNDING.yml"; fi
  if [ -d ios ]; then rm -rf "$S/ios" && cp -r ios "$S/ios"; fi
  if [ -d ios/.github ]; then mkdir -p "$S/.github" && cp -r ios/.github/. "$S/.github/" && rm -rf "$S/ios/.github"; fi
}
if sync_repo "$SRC_REPO" "$S" && copy_src && commit_push "$S" "口袋代理 $VER"; then
  echo "OK   源码已同步到 $SRC_REPO"
else
  echo "提醒:源码同步到 $SRC_REPO 失败(发布不受影响)"
fi
rm -rf "$T"
echo "已发布 $VER"
