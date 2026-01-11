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

# 更换国内源(USE_CN_MIRROR=true 时启用)
RUN if [ "$USE_CN_MIRROR" = "true" ] ; then \
      sed -i 's/archive.ubuntu.com/mirrors.aliyun.com/g' /etc/apt/sources.list && \
      sed -i 's/security.ubuntu.com/mirrors.aliyun.com/g' /etc/apt/sources.list ; \
    fi

# 启用 32 位架构（SteamCMD 必须）并安装依赖
RUN  --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt,sharing=locked \
    dpkg --add-architecture i386 && \
    apt-get update && \
    apt-get install -y \
    software-properties-common \
    lib32gcc-s1 \
    apache2-utils \
    ca-certificates \
    curl \
    wget \
    cron \
    locales \
    git \
    gosu \
    supervisor \
    nginx \
    socat \
    && rm -rf /var/lib/apt/lists/*

# 配置语言环境（防止僵毁控制台乱码）
RUN locale-gen en_US.UTF-8
ENV LANG=en_US.UTF-8
ENV LANGUAGE=en_US:en
ENV LC_ALL=en_US.UTF-8

# 获取FileBrowser
RUN ARCH=$(dpkg --print-architecture) && \
    echo "Detected architecture: $ARCH" && \
    if [ "$ARCH" = "amd64" ]; then FB_ARCH="linux-amd64"; \
    elif [ "$ARCH" = "arm64" ]; then FB_ARCH="linux-arm64"; \
    else echo "Unsupported architecture" && exit 1; fi && \
    curl -fsSL "https://github.com/filebrowser/filebrowser/releases/latest/download/$FB_ARCH-filebrowser.tar.gz" | tar -xz -C /usr/local/bin filebrowser && \
    chmod +x /usr/local/bin/filebrowser

# 用户与目录
RUN useradd -m -d /home/steam -s /bin/bash steam && \
    mkdir -p /home/steam/steamcmd && \
    mkdir -p ${PZ_INSTALL_DIR} && \
    mkdir -p /var/log/supervisor && \
    mkdir -p /certs && \
    # 创建 FileBrowser 数据库专用目录
    mkdir -p /opt/filebrowser && \
    # 创建游戏配置Web服务目录
    mkdir -p /opt/pz-web-backend && \
    # 创建 Nginx 配置目录
    mkdir -p /etc/nginx/conf.d && \
    # 给予这些目录权限给默认的steam用户
    chown -R steam:steam /home/steam ${PZ_INSTALL_DIR} /certs /opt/filebrowser /opt/pz-web-backend

# 手动安装 SteamCMD
# 直接从官网下载解压，没有代理的话可能会很慢。
WORKDIR /home/steam/steamcmd
USER steam
RUN curl -sqL "https://steamcdn-a.akamaihd.net/client/installer/steamcmd_linux.tar.gz" | tar zxvf -
RUN ./steamcmd.sh +quit

# 下载僵毁
RUN --mount=type=cache,target=/home/steam/Steam,uid=1000,gid=1000 \
    ./steamcmd.sh +login anonymous +quit && \
    ./steamcmd.sh \
    +force_install_dir ${PZ_INSTALL_DIR} \
    +login anonymous \
    +app_update 380870 validate \
    +quit
# 清理下载缓存
RUN rm -rf /home/steam/Steam/appcache/*

# 配置文件注入
# 切换用户
USER root
# 复制 Supervisor 配置
COPY supervisord.conf /etc/supervisor/conf.d/supervisord.conf
# 复制游戏启动脚本
COPY start-pz.sh /home/steam/start-pz.sh
RUN chmod +x /home/steam/start-pz.sh && chown steam:steam /home/steam/start-pz.sh
# 复制入口脚本
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

# 设置僵毁默认分支为 public
ENV PZ_BRANCH="public"
# 设置游戏设置Web服务相关内容
ENV PZ_SETTING_WEB_REPO="Asteroid77/pz-web-backend"
# 下载游戏配置页面后台二进制文件
RUN apt-get update && apt-get install -y curl jq && \
    LATEST_URL=$(curl -s "https://api.github.com/repos/${PZ_SETTING_WEB_REPO}/releases/latest" | jq -r '.assets[] | select(.name | contains("linux-amd64")) | .browser_download_url') && \
    echo "Downloading from: $LATEST_URL" && \
    curl -L "$LATEST_URL" -o /usr/local/share/pz-web-backend-default && \
    chmod +x /usr/local/share/pz-web-backend-default

# 暴露端口：游戏UDP + FileBrowser Web + 游戏配置页面
EXPOSE ${PORT_GAME_UDP}/udp ${PORT_GAME_UDP_HANDSHAKE}/udp ${PORT_FILEBROWSER} ${PORT_GAME_SETTING_WEB}

ENTRYPOINT ["/entrypoint.sh"]