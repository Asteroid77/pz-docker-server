#!/bin/bash
# 位于 /home/steam/start-pz.sh

PZ_INSTALL_DIR="/opt/pzserver"
STEAMCMD_DIR="/home/steam/steamcmd"

echo "--- Supervisor 正在启动僵毁服务端 ---"
# 确认分支
# 如果 PZ_BRANCH 为空，默认为 public
BRANCH=${PZ_BRANCH:-public}
BETA_ARGS=""

if [ "$BRANCH" = "public" ] || [ "$BRANCH" = "latest" ]; then
    echo "--- [Game] 目标分支: 稳定版 (public) ---"
else
    echo "--- [Game] 目标分支: 测试版 ($BRANCH) ---"
    BETA_ARGS="-beta $BRANCH"
fi
echo "--- [Game] 开始检查更新... ---"
# timeout 600s: 给 SteamCMD 10分钟时间。如果超时或失败，尝试继续启动旧版本。
timeout 600s $STEAMCMD_DIR/steamcmd.sh -tcp \
    +force_install_dir $PZ_INSTALL_DIR \
    +login anonymous \
    +app_update 380870 $BETA_ARGS \
    +quit || echo "--- [Game] 更新过程遇到错误或超时，尝试直接启动服务器... ---"

# --- 启动服务器 ---
cd $PZ_INSTALL_DIR
if [ ! -f "./start-server.sh" ]; then
    echo "错误: 找不到 start-server.sh，可能是游戏下载完全失败。"
    exit 1
fi

# 使用 exec 替换当前 shell 进程
# 这样 supervisord 的停止信号 (SIGTERM) 能直接传给 java 进程
# 保证游戏能有机会执行“保存并退出”逻辑
exec ./start-server.sh -adminpassword admin -cachedir=/home/steam/Zomboid