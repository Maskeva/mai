#!/bin/bash

# Arch Linux 自定义安装脚本 - 完整安装
set -e

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # 无颜色

# 输出颜色信息函数
info() {
    echo -e "${GREEN}[信息]${NC} $1"
}

warn() {
    echo -e "${YELLOW}[警告]${NC} $1"
}

error() {
    echo -e "${RED}[错误]${NC} $1"
    exit 1
}

question() {
    echo -e "${BLUE}[问题]${NC} $1"
}

# 检查是否以 root 权限运行
if [[ $EUID -ne 0 ]]; then
    error "此脚本必须以 root 权限运行。请使用 'sudo' 或以 root 用户身份运行。"
fi

info "开始 Arch Linux 自定义安装脚本"

# 显示所有可用硬盘
info "检测到的存储设备:"
lsblk -o NAME,SIZE,TYPE,MODEL -d | grep -v "loop"

# 获取所有硬盘列表
disks=($(lsblk -d -n -o NAME | grep -E "^(sd|nvme|vd)"))
if [ ${#disks[@]} -eq 0 ]; then
    error "未找到可用硬盘"
fi

# 让用户选择要操作的硬盘
question "请选择要安装 Arch Linux 的硬盘:"
for i in "${!disks[@]}"; do
    size=$(lsblk -d -n -o SIZE /dev/${disks[$i]})
    model=$(lsblk -d -n -o MODEL /dev/${disks[$i]} | tr -d ' ')
    echo "$((i+1)). /dev/${disks[$i]} ($size) $model"
done

read -p "请输入数字选择 (1-${#disks[@]}): " choice
if ! [[ "$choice" =~ ^[0-9]+$ ]] || [ "$choice" -lt 1 ] || [ "$choice" -gt "${#disks[@]}" ]; then
    error "无效的选择"
fi

selected_disk="/dev/${disks[$((choice-1))]}"

# 显示严重警告
warn "警告: 此操作将永久擦除磁盘 $selected_disk 上的所有数据!"
warn "这将不可恢复地删除磁盘上的所有分区和数据!"
read -p "请输入 'YES' 确认您要继续: " confirmation
if [ "$confirmation" != "YES" ]; then
    info "操作已取消"
    exit 0
fi

# 确定分区命名约定（处理NVMe磁盘）
if [[ $selected_disk == *"nvme"* ]]; then
    part1="${selected_disk}p1"
    part2="${selected_disk}p2"
else
    part1="${selected_disk}1"
    part2="${selected_disk}2"
fi

# 擦除磁盘分区表
info "正在擦除磁盘分区表..."
sgdisk --zap-all $selected_disk

# 创建新分区表 (GPT)
info "创建新的 GPT 分区表..."
parted -s $selected_disk mklabel gpt

# 创建 EFI 系统分区 (1GB)
info "创建 1GB 的 EFI 系统分区..."
parted -s $selected_disk mkpart primary fat32 1MiB 1025MiB
parted -s $selected_disk set 1 esp on

# 创建根分区 (剩余所有空间)
info "创建根分区 (使用剩余所有空间)..."
parted -s $selected_disk mkpart primary btrfs 1025MiB 100%

# 格式化分区
info "格式化 EFI 系统分区为 FAT32..."
mkfs.fat -F32 $part1

info "格式化根分区为 Btrfs..."
mkfs.btrfs -f $part2

# 挂载根分区并创建子卷（启用透明压缩）
info "挂载根分区并创建子卷（启用透明压缩）..."
mount -o compress=zstd $part2 /mnt

info "创建 Btrfs 子卷..."
btrfs subvolume create /mnt/@
btrfs subvolume create /mnt/@home
btrfs subvolume create /mnt/@swap

# 卸载分区以便重新挂载子卷
umount /mnt

# 使用子卷挂载分区并启用透明压缩
info "使用子卷挂载分区并启用透明压缩 (zstd)..."
mount -o subvol=@,compress=zstd $part2 /mnt
mkdir -p /mnt/home
mount -o subvol=@home,compress=zstd $part2 /mnt/home

# 创建并挂载交换子卷（不启用压缩）
info "创建并挂载交换子卷..."
mkdir -p /mnt/swap
mount -o subvol=@swap,noatime,nodiratime $part2 /mnt/swap

# 创建并挂载 EFI 分区
info "挂载 EFI 系统分区..."
mkdir -p /mnt/boot
mount $part1 /mnt/boot

# 显示分区结果
info "分区完成! 当前挂载情况:"
lsblk -f $selected_disk
df -h | grep -E "(Filesystem|/mnt)"

# 显示 Btrfs 文件系统信息
info "Btrfs 文件系统信息:"
btrfs filesystem show $part2
btrfs subvolume list /mnt

# ========== 系统安装部分 ==========
info "开始安装系统到硬盘..."

# 第一步：更新密钥
info "更新密钥环..."
pacman -Sy --noconfirm archlinux-keyring

# 第二步：安装基础包、编译工具、内核和固件
info "安装基础系统包、编译工具、内核和固件..."
pacstrap /mnt base base-devel linux linux-firmware \
          btrfs-progs nano sudo networkmanager

# 使用 Btrfs 方式创建交换文件
info "使用 Btrfs 方式创建 4GB 交换文件..."
btrfs filesystem mkswapfile --size 4g --uuid clear /mnt/swap/swapfile

# 启用交换文件
info "启用交换文件..."
swapon /mnt/swap/swapfile

# 生成 fstab 文件
info "生成 fstab 文件..."
genfstab -U /mnt > /mnt/etc/fstab

# 检查 fstab 文件
info "检查生成的 fstab 文件:"
cat /mnt/etc/fstab

# 设置主机名
read -p "请输入主机名: " hostname
echo "$hostname" > /mnt/etc/hostname

# 设置时区为Asia/Shanghai (UTC+8)
info "设置时区为Asia/Shanghai (UTC+8)..."
ln -sf /usr/share/zoneinfo/Asia/Shanghai /mnt/etc/localtime

# 同步硬件时钟
info "同步硬件时钟..."
arch-chroot /mnt hwclock --systohc

# 设置本地化为en_US.UTF-8
info "设置本地化为en_US.UTF-8..."
echo "en_US.UTF-8 UTF-8" >> /mnt/etc/locale.gen
echo "LANG=en_US.UTF-8" > /mnt/etc/locale.conf
arch-chroot /mnt locale-gen

# 启用时间同步服务
info "启用时间同步服务..."
arch-chroot /mnt systemctl enable systemd-timesyncd.service

# 安装 AMD 微码
info "安装 AMD 微码..."
arch-chroot /mnt pacman -S --noconfirm amd-ucode

# 设置 root 密码
info "设置 root 密码..."
arch-chroot /mnt passwd

# 创建普通用户
read -p "请输入要创建的普通用户名: " username
arch-chroot /mnt useradd -m -G wheel -s /bin/zsh "$username"
info "设置用户 $username 的密码..."
arch-chroot /mnt passwd "$username"

# 配置 sudo 权限
info "配置 sudo 权限..."
echo "%wheel ALL=(ALL) ALL" >> /mnt/etc/sudoers

# 安装 GRUB 引导程序
info "安装 GRUB 引导程序..."
pacstrap /mnt grub efibootmgr

# 配置 GRUB - 使用 Cutedog 作为启动器 ID
info "配置 GRUB 引导程序..."
arch-chroot /mnt grub-install --target=x86_64-efi --efi-directory=/boot --bootloader-id=Cutedog

# 完全禁用 watchdog - 添加 nowatchdog 参数到 GRUB 配置
info "完全禁用 watchdog..."
sed -i 's/GRUB_CMDLINE_LINUX_DEFAULT="\(.*\)"/GRUB_CMDLINE_LINUX_DEFAULT="\1 nowatchdog"/' /mnt/etc/default/grub

# 禁用 watchdog 系统服务
info "禁用 watchdog 系统服务..."
arch-chroot /mnt bash -c 'systemctl mask watchdog.service 2>/dev/null || true'

# 生成 GRUB 配置文件
arch-chroot /mnt grub-mkconfig -o /boot/grub/grub.cfg

# 显示 GRUB 安装结果
info "GRUB 引导程序安装完成!"
info "EFI 启动项已创建，启动器 ID 为 Cutedog"
info "已完全禁用 watchdog (内核参数和系统服务)"
info "GRUB 配置文件已生成: /boot/grub/grub.cfg"

# 切换到新安装的系统
info "正在切换到新安装的系统环境..."
arch-chroot /mnt /bin/bash <<EOF
echo "已成功切换到新系统环境!"
echo "主机名已设置为: $hostname"
echo "时区已设置为: Asia/Shanghai (UTC+8)"
echo "本地化已设置为: en_US.UTF-8"
echo "时间同步服务已启用"
echo "AMD 微码已安装"
echo "Root 密码已设置"
echo "用户 $username 已创建并添加到 wheel 组"
echo "sudo 权限已配置"
echo "GRUB 引导程序已安装并配置完成 (启动器 ID: Cutedog)"
echo "已完全禁用 watchdog"
echo "当前工作目录: \$(pwd)"
echo "您可以在此环境中继续执行系统配置命令"
EOF

# 最终提示
info "Arch Linux 安装脚本执行完成!"
info "请确认所有步骤已成功执行，然后使用以下命令重启系统:"
info "umount -R /mnt"
info "reboot"
info "重启后，您可以使用创建的用户 ($username) 登录系统"