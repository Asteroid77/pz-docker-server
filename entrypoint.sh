#!/bin/bash
set -e

PZ_INSTALL_DIR="/opt/pzserver"
STEAMCMD_DIR="/home/steam/steamcmd"

echo "--- 容器启动初始化 ---"
echo "模式: SSL_MODE=$SSL_MODE"
echo "域名: DOMAIN_NAME=$DOMAIN_NAME"

smart_chown() {
    local target="$1"
    local user="steam"
    
    if [ ! -d "$target" ]; then
        return
    fi

    # 获取目标目录当前的所有者
    current_owner=$(stat -c '%U' "$target")

    # 只有当所有者不是 steam 时，才执行耗时的递归修改
    if [ "$current_owner" != "$user" ]; then
        echo "修复权限: $target (正在执行 chown -R，请耐心等待...)"
        chown -R "$user:$user" "$target"
    else
        echo "权限正确: $target (跳过检查)"
    fi
}

# steam目录权限处理
echo "正在给予文件权限..."
# 对关键目录进行智能检查
smart_chown "/home/steam"
smart_chown "/opt/pzserver"
smart_chown "/opt/filebrowser"


# --- 初始化 Web 配置面板 ---
WEB_DIR="/opt/pz-web-backend"
WEB_BIN="$WEB_DIR/pz-web-backend"
WEB_DEFAULT="/usr/local/share/pz-web-backend-default"

echo "--- 初始化 Web 配置面板 ---"
# 确保目录存在
if [ ! -d "$WEB_DIR" ]; then
    mkdir -p "$WEB_DIR"
fi

# 如果挂载目录里没有二进制文件（第一次运行），则从镜像备份里复制一个
if [ ! -f "$WEB_BIN" ]; then
    echo "检测到面板程序缺失，复制初始版本..."
    cp "$WEB_DEFAULT" "$WEB_BIN"
else
    echo "检测到现有面板程序，跳过复制 (保留持久化版本)。"
fi

# 确保 steam 用户有权限执行和写入 (为了在线更新能覆盖)
chown -R steam:steam "$WEB_DIR"
chmod +x "$WEB_BIN"


# 证书目录权限处理
if [ -d "/certs" ]; then
    # 尝试修改权限，但如果失败（例如只读挂载），不要退出脚本
    chmod -R 755 /certs 2>/dev/null || echo "提示: /certs 目录是只读的，跳过权限修改。"
fi

# --- 初始化 FileBroswer ---
echo "--- 初始化 文件浏览器(FileBrowser)变量 ---"
FB_DIR="/opt/filebrowser"
FB_DB="/opt/filebrowser/database.db"
# 用户在网页上看到的“根目录”实际上是这里
FB_ROOT="/home/steam/Zomboid"
# 确保目标目录存在，否则 FileBrowser 会报错
mkdir -p "$FB_ROOT" "$FB_DIR"
chown steam:steam "$FB_ROOT" "$FB_DIR"

# 如果数据库不存在，或者大小为0 (上次初始化失败)，则重新初始化
if [ ! -s "$FB_DB" ]; then
    echo "--- 初始化 FileBrowser 数据库 ---"
    
    # 安全起见，先删掉旧的
    rm -f "$FB_DB"

    # 初始化空库
    filebrowser config init -d "$FB_DB"
    
    # 设置全局配置
    # 注意：root 路径必须存在且有权限
    filebrowser config set -d "$FB_DB" --address 0.0.0.0 --port 35088 --root "$FB_ROOT" --baseurl "/filebrowser/"
    
    # 创建管理员 (密码长度必须 > 12)
    # 默认账号: admin
    # 默认密码: admin12345678
    echo "设置管理员密码为: $FILEBROSWER_ADMIN_PASSWORD"
    filebrowser users add "$FILEBROSWER_ADMIN_USERNAME" "$FILEBROSWER_ADMIN_PASSWORD" --perm.admin -d "$FB_DB"
    echo "--- 给予 FileBrowser 数据库权限 ---"
    chown -R steam:steam "$FB_DIR"
    chmod 644 "$FB_DB" 2>/dev/null || true
else
    echo "--- FileBrowser 数据库已存在，跳过初始化 ---"
fi
# --- 结束 初始化 FileBroswer ---



# 打印HTTPS预备信息
if [ "$SSL_MODE" = "cloudflare" ]; then
    if [ -z "$CF_Token" ]; then
        echo "警告: SSL模式为 Cloudflare 但未检测到 CF_Token"
    else
        echo "Cloudflare Token 已加载 (掩码处理: ${CF_Token:0:5}******)"
    fi
fi

setup_ssl() {
    echo "--- [HTTPS] 初始化 SSL 配置 (当前模式: $SSL_MODE) ---"
    
    # 约定好最终使用的证书文件名
    FINAL_CERT="$SSL_PATH/$SSL_CERT"
    FINAL_KEY="$SSL_PATH/$SSL_KEY"

    # 是否准备好 HTTPS
    SSL_READY="false"

    # ============================================
    # 检查是否已有证书
    # ============================================
    if [ -s "$FINAL_CERT" ] && [ -s "$FINAL_KEY" ]; then
        echo "✅ 检测到 /certs 目录下已存在证书文件，跳过申请步骤。"
        echo "   -> 直接使用现有证书。"
        SSL_READY="true"
    else
        echo "ℹ️  /certs 目录下未找到完整证书，进入申请/生成流程..."
        
        # ============================================
        # 根据模式处理
        # ============================================
        
        # --- 模式 A: Cloudflare 自动申请 ---
        if [ "$SSL_MODE" = "cloudflare" ]; then
            echo "--- 正在使用 Cloudflare API 申请证书 ---"
            
            # 校验参数
            if [ -z "$CF_Token" ] || [ -z "$DOMAIN_NAME" ] || [ -z "$CF_Account_ID" ]; then
                echo "❌ 错误: 缺少 CF_Token/DOMAIN_NAME/CF_Account_ID，无法申请。回退到 HTTP 模式。"
            else
                # 导入环境变量
                export CF_Token="$CF_Token"
                export CF_Account_ID="$CF_Account_ID"
                # 申请证书 (如果失败不要退出脚本，而是回退 HTTP)
                if /root/.acme.sh/acme.sh --issue --server letsencrypt --dns dns_cf -d "$DOMAIN_NAME"; then
                    # 安装证书到 /certs
                    echo "--- 申请成功，正在安装证书到 /certs ---"
                    /root/.acme.sh/acme.sh --install-cert -d "$DOMAIN_NAME" \
                        --key-file       "$FINAL_KEY"  \
                        --fullchain-file "$FINAL_CERT" \
                        --reloadcmd     "nginx -s reload"
                    
                    if [ -s "$FINAL_CERT" ]; then
                        echo "✅ 证书已保存到挂载目录。"
                        SSL_READY="true"
                    fi
                else
                    echo "❌ 证书申请失败，请检查 Cloudflare Token 或网络。"
                fi
            fi
        
        # --- 模式 B: Custom 自定义 ---
        elif [ "$SSL_MODE" = "custom" ]; then
             # 用户选择了 custom 但没把文件放对位置
             echo "❌ 模式为 custom 但 $SSL_PATH 下没找到 $SSL_CERT 以及 $SSL_KEY。"
             echo "   请将证书文件重命名并放入当前挂载Docker-Compose下的 ./certs 目录。"
        fi
    fi

    # ============================================
    #  生成 Nginx 配置
    # ============================================
    if [ "$SSL_READY" = "true" ]; then
        echo "🚀 启用 HTTPS (443) + HTTP 跳转"
        generate_nginx_config "on" "$FINAL_CERT" "$FINAL_KEY"
    else
        echo "⚠️  未满足 HTTPS 条件，仅启用 HTTP (80)"
        generate_nginx_config "off" "" ""
    fi
}
setup_nginx_auth() {
    # 环境变量中定义的用户名和密码
    local user="$PZ_WEB_ACCOUNT"
    local pass="$PZ_WEB_PASSWORD"
    local auth_file="/etc/nginx/.htpasswd"

    if [ -n "$pass" ]; then
        echo "--- [Security] 正在为 Web 面板配置 Basic Auth ---"
        echo "    User: $user"
        echo "    Pass: (已隐藏)"
        
        # 使用 htpasswd 生成密码文件 (-b 表示命令行输入密码, -c 表示创建新文件)
        htpasswd -bc "$auth_file" "$user" "$pass"
        return 0
    else
        echo "⚠️  警告: 未设置 ADMIN_PASSWORD，Web 面板将没有任何密码保护！"
        # 如果存在旧文件，删掉，防止意外锁定
        rm -f "$auth_file"
        return 1
    fi
}
# Nginx 配置生成函数 (优化版：增加 HTTP->HTTPS 跳转)
generate_nginx_config() {
    local ssl_on=$1
    local cert=$2
    local key=$3
    NGINX_CONF="/etc/nginx/conf.d/default.conf"

    echo "# 自动生成 Nginx 配置" > "$NGINX_CONF"
    
    if [ "$ssl_on" = "on" ]; then
        # --- HTTPS Server ---
        echo "server {" >> "$NGINX_CONF"
        echo "    listen 443 ssl;" >> "$NGINX_CONF"
        echo "    server_name $DOMAIN_NAME;" >> "$NGINX_CONF"
        echo "    ssl_certificate $cert;" >> "$NGINX_CONF"
        echo "    ssl_certificate_key $key;" >> "$NGINX_CONF"
        echo "    ssl_protocols TLSv1.2 TLSv1.3;" >> "$NGINX_CONF"
        
        # 插入反向代理逻辑
        append_proxy_locations "$NGINX_CONF"
        
        echo "}" >> "$NGINX_CONF"

        # --- HTTP 跳转 HTTPS ---
        echo "server {" >> "$NGINX_CONF"
        echo "    listen 80;" >> "$NGINX_CONF"
        echo "    server_name $DOMAIN_NAME;" >> "$NGINX_CONF"
        echo "    return 301 https://\$host\$request_uri;" >> "$NGINX_CONF"
        echo "}" >> "$NGINX_CONF"
    else
        # --- 纯 HTTP 模式 ---
        echo "server {" >> "$NGINX_CONF"
        echo "    listen 80;" >> "$NGINX_CONF"
        append_proxy_locations "$NGINX_CONF"
        echo "}" >> "$NGINX_CONF"
    fi
}

# 抽取公共的 location 配置
append_proxy_locations() {
    local conf_file=$1
    local auth_file="/etc/nginx/.htpasswd"
    
    # 检查密码文件是否存在
    local auth_config=""
    if [ -f "$auth_file" ]; then
        auth_config="auth_basic \"Restricted Area\"; auth_basic_user_file $auth_file;"
    fi

    # --- Go Web Backend (需要密码保护) ---
    echo "    location / {" >> "$conf_file"
    
    # 注入认证配置
    if [ -n "$auth_config" ]; then
        echo "        $auth_config" >> "$conf_file"
    fi
    
    echo "        proxy_pass http://127.0.0.1:10888;" >> "$conf_file"
    echo "        proxy_set_header Host \$host;" >> "$conf_file"
    echo "        proxy_set_header X-Real-IP \$remote_addr;" >> "$conf_file"
    echo "        proxy_http_version 1.1;" >> "$conf_file"
    echo "        proxy_set_header Upgrade \$http_upgrade;" >> "$conf_file"
    echo "        proxy_set_header Connection \"upgrade\";" >> "$conf_file"
    echo "    }" >> "$conf_file"

    # --- FileBrowser (自带登录，不需要 Nginx 再拦截一次) ---
    echo "    location /filebrowser/ {" >> "$conf_file"
    echo "        proxy_pass http://127.0.0.1:35088/filebrowser/;" >> "$conf_file"
    echo "        proxy_set_header Host \$host;" >> "$conf_file"
    echo "        proxy_set_header X-Real-IP \$remote_addr;" >> "$conf_file"
    echo "    }" >> "$conf_file"
}

# 生成密码文件
setup_nginx_auth

# 执行逻辑
setup_ssl

# 创建日志文件，防止启动时报错
touch /home/steam/pz-stdout.log
chown steam:steam /home/steam/pz-stdout.log

# 启动 Supervisor
echo "--- 启动进程管理器 ---"
exec supervisord -c /etc/supervisor/conf.d/supervisord.conf