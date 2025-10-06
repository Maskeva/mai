#!/bin/bash

# 启用错误检查，遇到任何错误即停止执行
set -e

# 定义错误处理函数
error_handler() {
    echo "脚本执行出错，退出状态码: $?"
    exit 1
}

# 设置错误捕获
trap error_handler ERR


# 添加archlinuxcn清华源
echo '[archlinuxcn]' | sudo tee -a /etc/pacman.conf
echo 'Server = https://mirrors.tuna.tsinghua.edu.cn/archlinuxcn/$arch' | sudo tee -a /etc/pacman.conf

# 先同步数据库并单独安装keyring
sudo pacman -Sy archlinuxcn-keyring

# 安装所有软件包（确保所有包在官方或archlinuxcn库中可用）
sudo pacman -S noto-fonts-cjk noto-fonts-emoji ark bluez bluez-utils \
fcitx5-im fcitx5-chinese-addons ghostty gwenview kate kcalc kfind kscreen \
nvidia-dkms plasma-desktop plasma-applets-weather-widget-3 elisa fastfetch \
plasma-firewall plasma-nm plasma-pa plasma-systemmonitor sddm sddm-kcm spectacle throne \
libva libva-utils libva-nvidia-driver ttf-jetbrains-mono-nerd starship dolphin dragon \
pipewire pipewire-pulse pipewire-alsa pipewire-jack wireplumber \
zsh-autosuggestions zsh-completions zsh-syntax-highlighting


# 在ZSH中启用Starship
echo 'eval "$(starship init zsh)"' >> ~/.zshrc

# 设置fcitx5环境变量（系统级）
echo 'GTK_IM_MODULE=fcitx' | sudo tee -a /etc/environment
echo 'QT_IM_MODULE=fcitx' | sudo tee -a /etc/environment
echo 'XMODIFIERS=@im=fcitx' | sudo tee -a /etc/environment

# # 配置Snapper（假设根目录已使用Btrfs文件系统）
# echo "> 配置Snapper..."
# # 创建snapper配置（如果尚未创建）
# if ! sudo snapper list-configs | grep -q "root"; then
#     sudo snapper -c root create-config /
# fi
#
# # 设置Snapper配置
# sudo snapper -c root set-config "ALLOW_GROUPS=wheel"
# sudo snapper -c root set-config "SYNC_ACL=yes"
# sudo snapper -c root set-config "NUMBER_CLEANUP=yes"
# sudo snapper -c root set-config "NUMBER_MIN_AGE=1800"
# sudo snapper -c root set-config "SPACE_LIMIT=10G"
# sudo snapper -c root set-config "NUMBER_LIMIT=20"
# sudo snapper -c root set-config "NUMBER_LIMIT_IMPORTANT=10"
#
# # 设置时间线快照保留策略
# sudo snapper -c root set-config "TIMELINE_LIMIT_HOURLY=0"      # 禁用每小时快照
# sudo snapper -c root set-config "TIMELINE_LIMIT_DAILY=7"       # 保留最近7天的每日快照
# sudo snapper -c root set-config "TIMELINE_LIMIT_WEEKLY=3"      # 禁用每周快照
# sudo snapper -c root set-config "TIMELINE_LIMIT_MONTHLY=0"    # 保留最近12个月的月度快照
# sudo snapper -c root set-config "TIMELINE_LIMIT_QUARTERLY=0"   # 禁用季度快照
# sudo snapper -c root set-config "TIMELINE_LIMIT_YEARLY=0"      # 禁用年度快照


echo "Done！"

