# syntax=docker/dockerfile:1
# 启用高级构建特性

# 指定基础镜像
FROM ubuntu:jammy

# --- 构建参数 ---
# 是否使用功能国内源（默认为 true）
ARG USE_CN_MIRROR=true
# 代理，构建时通过 --build-arg 传入
ARG http_proxy
ARG https_proxy

#  设置环境变量，防止 apt 安装时弹出交互界面
ENV DEBIAN_FRONTEND=noninteractive
ENV http_proxy=$http_proxy
ENV https_proxy=$https_proxy

# --- 僵毁相关环境变量 ---
# 存档目录
ENV PZ_DATA_DIR="/home/steam/Zomboid"
# 安装目录
ENV PZ_INSTALL_DIR="/opt/pzserver"
# 端口定义
ENV PORT_GAME_UDP=16261
ENV PORT_GAME_UDP_HANDSHAKE=16262

# --- FileBrowser 相关环境变量 ---
# Web 端口
ENV PORT_FILEBROWSER=35088

# --- 游戏配置页面相关环境变量 ---
ENV PORT_GAME_SETTING_WEB=10888

# --- HTTPS 预留配置 ---
# 模式: off (默认), custom (自带文件), cloudflare (自动申请)
ENV SSL_MODE="off" 
# 你的域名
ENV DOMAIN_NAME="localhost"
# 你的邮箱 (SSL_MODE=cloudflare 时启用)
ENV EMAIL=""
# Cloudflare API信息(SSL_MODE=cloudflare 时启用)
ENV CF_Token=""
ENV CF_Account_ID=""
# 自定义证书路径 (SSL_MODE=custom 时启用)
ENV SSL_PATH="/certs"
ENV SSL_KEY="key.pem"
ENV SSL_CERT="cert.pem"

# 设置僵毁默认分支为 public
ENV PZ_BRANCH="public"
# 设置游戏设置Web服务相关内容
ENV PZ_SETTING_WEB_REPO="Asteroid77/pz-web-backend"
# 下载游戏配置页面后台二进制文件
ENV PZ_WEB_BACKEND_FILENAME="pz-web-backend-linux-amd64"

# 更换国内源(USE_CN_MIRROR=true 时启用)
RUN <<EOF
if [ "$USE_CN_MIRROR" = "true" ]; then
    echo "Switching to CN mirror..."
    # 使用 ; 作为分隔符，或者直接换行，两种 sed 命令可以合成一个
    # sed 是 "Stream Editor"（流编辑器）的缩写，主要用于文本处理。
	# sed 's/要查找的内容/要替换成的内容/g' 文件名
	# -i 不输出结果打印到屏幕上，且直接应用
	# -e 表达式/脚本，在一个sed命令中执行多次编辑规则，无需重复调用sed
	# 下面表达式的主要功能，指的是将文件内的archive.ubuntu.com或者security.ubuntu.com改为mirrors.aliyun.com
    sed -i \
        -e 's/archive.ubuntu.com/mirrors.aliyun.com/g' \
        -e 's/security.ubuntu.com/mirrors.aliyun.com/g' \
        /etc/apt/sources.list
fi
EOF

# 启用 32 位架构（SteamCMD 必须）并安装依赖
# dpkg --add-architecture i386 启用 32 位架构（SteamCMD 必须)
# --mount 这是BuildKit高级功能，持久化缓存下面这些依赖，免得你DockerFile后又要跑去下一遍。
# target 就是缓存的目录，这里分两个，一个是apt用来下载.deb安装包的地方，另一个是apt-get update下载的软件包list信息。
# sharing缓存锁，多个构建任务同时运行时，缓存不会出错。
# apt-get就不用介绍了吧？安装依赖用的。
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt,sharing=locked \
    <<EOF
# 脚本出错时立即退出
set -e
# --- 准备基础环境 ---
echo "Adding 32-bit architecture for SteamCMD..."
dpkg --add-architecture i386
# --- 更新软件包列表 (会使用高速缓存) ---
echo "Updating package lists..."
apt-get update

# --- 安装所有依赖 ---
echo "Installing dependencies..."
RAW_DEPS_LIST="
    # software-properties-common: 提供 add-apt-repository 等管理软件源的工具。
    software-properties-common
    # lib32gcc-s1: SteamCMD 和游戏运行必需的 32 位基础库。
    lib32gcc-s1
    # apache2-utils: 提供 htpasswd 命令，用于 Nginx Basic Auth 认证。
    apache2-utils
    # ca-certificates: 保证 HTTPS 连接的安全性，是 curl, wget 等命令能正常工作的基础。
    ca-certificates
    # curl, wget, git: 下载和版本控制工具。
    curl
    wget
    git
    # cron: 任务计划程序，用于定期备份等。
    cron
    # locales: 本地化与字符集支持，防止控制台乱码。
    locales
    # gosu: 一个比 sudo 更安全、更适合在容器中切换用户的工具。
    gosu
    # supervisor: 进程管理器，我们用它来同时运行游戏、Nginx 等。
    supervisor
    # nginx: 高性能的反向代理服务器。
    nginx
    # socat: 强大的网络工具。
    socat 
"
CLEAN_DEPS=$(echo "$RAW_DEPS_LIST" | sed '/^\s*#/d;/^\s*$/d')
apt-get install -y $CLEAN_DEPS
    
# --- 清理 ---
echo "Cleaning up apt lists to reduce image size..."
rm -rf /var/lib/apt/lists/*
EOF

# 配置语言环境（防止僵毁控制台乱码）
# 需要在locales下载后才能使用。
RUN locale-gen en_US.UTF-8
ENV LANG=en_US.UTF-8
ENV LANGUAGE=en_US:en
ENV LC_ALL=en_US.UTF-8


# 获取FileBrowser
RUN <<EOF
# 脚本出错时立即退出
set -e

# --- 检测 CPU 架构 ---
# dpkg打印当前处理器架构，然后去判断是amd64(x86)还是arm64(arm)架构，因为Filebrowser不支持arm结构的处理器。
ARCH=$(dpkg --print-architecture)
echo "Detected architecture: $ARCH"

case "$ARCH" in
    "amd64")
        FB_ARCH="linux-amd64"
        ;;
    "arm64")
        FB_ARCH="linux-arm64"
        ;;
    *)
        echo "Unsupported architecture for FileBrowser: $ARCH"
        exit 1
        ;;
esac

# --- 构造下载 URL ---
# 定义基础 URL
FB_URL="https://github.com/filebrowser/filebrowser/releases/latest/download/${FB_ARCH}-filebrowser.tar.gz"

# 根据构建参数决定是否添加代理前缀
# -n的意思是"non-zero length" 或者 "not empty"，当然，你也可以写成"$GITHUB_PROXY_URL"!=""
# echo其实就是控制台输出这么一串字符，相当于打印log
if [ -n "$GITHUB_PROXY_URL" ]; then
    echo "Using GitHub proxy: $GITHUB_PROXY_URL"
    DOWNLOAD_URL="${GITHUB_PROXY_URL}/${FB_URL}"
else
    DOWNLOAD_URL="${FB_URL}"
fi
# --- 下载并安装 ---
echo "Downloading FileBrowser from: $DOWNLOAD_URL"
# curl
# -f -fail返回错误会直接失败退出
# -s -silent 静默工作
# -S -show-error安静，但出错了还是要输出log
# -L -location 跟着重定向走
# tar 用于处理.tar文件（解压缩之类的也有）
# -x --extract 提取文件
# -z --gzip 告诉tar这个数据是gzip算法压缩，需要用gunzip解压才能处理
# -C --directory /usr/local/bin 解压后放入/usr/local/bin
# filebrowser 指定只要这个文件
curl -fsSL "$DOWNLOAD_URL" | tar -xz -C /usr/local/bin filebrowser

# --- 赋予执行权限 ---
chmod +x /usr/local/bin/filebrowser
echo "FileBrowser installed successfully."
EOF

# --- 用户与目录 ---
RUN <<EOF
# 脚本出错时立即退出
set -e

# --- 创建 steam 用户 ---
echo "Creating user 'steam'..."
useradd -m -d /home/steam -s /bin/bash steam

# --- 创建所有必需的目录 ---
# 创建steamcmd目录
echo "Creating application directories..."
DIRECTORIES_TO_CREATE="
    # 创建SteamCMD目录
    /home/steam/steamcmd
    # 创建Steam目录
    /home/steam/Steam
    # 创建僵毁服务器目录
    ${PZ_INSTALL_DIR}
    # 创建 supervisor日志目录
    /var/log/supervisor
    # 创建证书存放目录
    /certs
    # 创建 FileBrowser 数据库专用目录
    /opt/filebrowser
    # 创建游戏配置Web服务目录
    /opt/pz-web-backend
    # 创建 Nginx 配置目录
    /etc/nginx/conf.d
"
CLEAN_DIRECTORIES_TO_CREATE=$(echo "$DIRECTORIES_TO_CREATE" | sed '/^\s*#/d;/^\s*$/d')
mkdir -p $CLEAN_DIRECTORIES_TO_CREATE

# --- 赋予 steam 用户对关键目录的所有权 ---
echo "Setting permissions for 'steam' user..."
CHOWN_LIST="
    /home/steam
    ${PZ_INSTALL_DIR}
    /certs
    /opt/filebrowser
    /opt/pz-web-backend
"
chown -R steam:steam $CHOWN_LIST
    
EOF

# 手动安装 SteamCMD
# 相当于cd /home...
WORKDIR /home/steam/steamcmd 
#切换用户为'steam'这个用户
USER steam 
RUN <<EOF
# 脚本出错时立即退出
set -e

# --- 定义下载地址 ---
OFFICIAL_URL="https://steamcdn-a.akamaihd.net/client/installer/steamcmd_linux.tar.gz"
CN_URL="https://media.st.dl.eccdnx.com/client/installer/steamcmd_linux.tar.gz" 
DOWNLOAD_URL=""

# --- 根据构建参数选择 URL ---
if [ "$USE_CN_MIRROR" = "true" ]; then
    echo "--> Using Steam China CDN..."
    DOWNLOAD_URL="$CN_URL"
else
    echo "--> Using International CDN..."
    DOWNLOAD_URL="$OFFICIAL_URL"
fi

# --- 下载并解压 ---
echo "--> Downloading SteamCMD from: $DOWNLOAD_URL"
curl -fsSL "$DOWNLOAD_URL" | tar -zxvf -

echo "--> SteamCMD installed successfully."
EOF



# 配置文件注入
# 切换用户
USER root
# 复制 Supervisord 配置
COPY supervisord.conf /etc/supervisor/conf.d/supervisord.conf
# 复制游戏启动脚本
COPY start-pz.sh /home/steam/start-pz.sh
RUN chmod +x /home/steam/start-pz.sh && chown steam:steam /home/steam/start-pz.sh
# 复制入口脚本
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh


RUN <<EOF
# 脚本出错时立即退出
set -e

# --- 构造指向最新版的链接 ---
echo "Constructing GitHub download URL..."
LATEST_URL="https://github.com/${PZ_SETTING_WEB_REPO}/releases/latest/download/${PZ_WEB_BACKEND_FILENAME}"

# --- 检查并应用代理 ---
if [ -n "$GITHUB_PROXY_URL" ]; then
    echo "--> Using GitHub proxy: $GITHUB_PROXY_URL"
    DOWNLOAD_URL="${GITHUB_PROXY_URL}${LATEST_URL}"
else
    DOWNLOAD_URL="${LATEST_URL}"
fi

# --- 下载并安装 ---
echo "--> Downloading latest version from: $DOWNLOAD_URL"
# -L 参数是必须的，用于跟随 GitHub 的 latest release 重定向
curl -fSL "$DOWNLOAD_URL" -o /usr/local/share/pz-web-backend-default

# --- 赋予执行权限 ---
chmod +x /usr/local/share/pz-web-backend-default
echo "--> pz-web-backend downloaded and installed successfully."
EOF

# 暴露端口：游戏UDP + FileBrowser Web + 游戏配置页面
EXPOSE ${PORT_GAME_UDP}/udp ${PORT_GAME_UDP_HANDSHAKE}/udp ${PORT_GAME_SETTING_WEB}

#设置一个入口文件，上面提到的入口脚本，游戏启动脚本，Supervisord配置文件都由这个入口激活。
ENTRYPOINT ["/entrypoint.sh"]