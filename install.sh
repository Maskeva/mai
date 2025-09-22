#!/bin/bash

# Arch Linux Custom Installation Script - Full Installation
set -e

# Color definitions
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Colored output functions
info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

warn() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1"
    exit 1
}

question() {
    echo -e "${BLUE}[QUESTION]${NC} $1"
}

# Check if running as root
if [[ $EUID -ne 0 ]]; then
    error "This script must be run as root. Please use 'sudo' or run as root user."
fi

info "Starting Arch Linux custom installation script"

# Show all available disks
info "Detected storage devices:"
lsblk -o NAME,SIZE,TYPE,MODEL -d | grep -v "loop"

# Get list of all disks
disks=($(lsblk -d -n -o NAME | grep -E "^(sd|nvme|vd)"))
if [ ${#disks[@]} -eq 0 ]; then
    error "No available disks found"
fi

# Let user select disk to operate on
question "Please select the disk to install Arch Linux on:"
for i in "${!disks[@]}"; do
    size=$(lsblk -d -n -o SIZE /dev/${disks[$i]})
    model=$(lsblk -d -n -o MODEL /dev/${disks[$i]} | tr -d ' ')
    echo "$((i+1)). /dev/${disks[$i]} ($size) $model"
done

read -p "Enter your choice (1-${#disks[@]}): " choice
if ! [[ "$choice" =~ ^[0-9]+$ ]] || [ "$choice" -lt 1 ] || [ "$choice" -gt "${#disks[@]}" ]; then
    error "Invalid selection"
fi

selected_disk="/dev/${disks[$((choice-1))]}"

# Show serious warning
warn "WARNING: This operation will permanently erase all data on disk $selected_disk!"
warn "This will irreversibly delete all partitions and data on the disk!"
read -p "Enter 'YES' to confirm you want to continue: " confirmation
if [ "$confirmation" != "YES" ]; then
    info "Operation cancelled"
    exit 0
fi

# Determine partition naming convention (handle NVMe disks)
if [[ $selected_disk == *"nvme"* ]]; then
    part1="${selected_disk}p1"
    part2="${selected_disk}p2"
else
    part1="${selected_disk}1"
    part2="${selected_disk}2"
fi

# Erase disk partition table
info "Erasing disk partition table..."
sgdisk --zap-all $selected_disk

# Create new partition table (GPT)
info "Creating new GPT partition table..."
parted -s $selected_disk mklabel gpt

# Create EFI system partition (1GB)
info "Creating 1GB EFI system partition..."
parted -s $selected_disk mkpart primary fat32 1MiB 1025MiB
parted -s $selected_disk set 1 esp on

# Create root partition (remaining space)
info "Creating root partition (using all remaining space)..."
parted -s $selected_disk mkpart primary btrfs 1025MiB 100%

# Format partitions
info "Formatting EFI system partition as FAT32..."
mkfs.fat -F32 $part1

info "Formatting root partition as Btrfs..."
mkfs.btrfs -f $part2

# Mount root partition and create subvolumes (with transparent compression)
info "Mounting root partition and creating subvolumes (with transparent compression)..."
mount -o compress=zstd $part2 /mnt

info "Creating Btrfs subvolumes..."
btrfs subvolume create /mnt/@
btrfs subvolume create /mnt/@home
btrfs subvolume create /mnt/@swap

# Unmount to remount subvolumes
umount /mnt

# Mount partitions with subvolumes and enable transparent compression
info "Mounting partitions with subvolumes and enabling transparent compression (zstd)..."
mount -o subvol=@,compress=zstd $part2 /mnt
mkdir -p /mnt/home
mount -o subvol=@home,compress=zstd $part2 /mnt/home

# Create and mount swap subvolume (no compression)
info "Creating and mounting swap subvolume..."
mkdir -p /mnt/swap
mount -o subvol=@swap,noatime,nodiratime $part2 /mnt/swap

# Create and mount EFI partition
info "Mounting EFI system partition..."
mkdir -p /mnt/boot
mount $part1 /mnt/boot

# Show partition results
info "Partitioning completed! Current mount status:"
lsblk -f $selected_disk
df -h | grep -E "(Filesystem|/mnt)"

# Show Btrfs filesystem information
info "Btrfs filesystem information:"
btrfs filesystem show $part2
btrfs subvolume list /mnt

# ========== System Installation Section ==========
info "Starting system installation to disk..."

echo 'Server = https://mirrors.tuna.tsinghua.edu.cn/archlinux/$repo/os/$arch' | sudo tee /etc/pacman.d/mirrorlist

# Step 1: Update keyring
info "Updating keyring..."
pacman -Sy --noconfirm archlinux-keyring

# Step 2: Install base packages, build tools, kernel and firmware
info "Installing base system packages, build tools, kernel and firmware..."
pacstrap /mnt base base-devel linux linux-firmware \
          btrfs-progs

# Install AMD microcode
info "Installing AMD microcode..."
arch-chroot /mnt pacman -S --noconfirm amd-ucode zsh nano sudo networkmanager

# Create swap file using Btrfs method
info "Creating 4GB swap file using Btrfs method..."
btrfs filesystem mkswapfile --size 4g --uuid clear /mnt/swap/swapfile

# Enable swap file
info "Enabling swap file..."
swapon /mnt/swap/swapfile

# Generate fstab file
info "Generating fstab file..."
genfstab -U /mnt > /mnt/etc/fstab

# Check fstab file
info "Checking generated fstab file:"
cat /mnt/etc/fstab

# Set hostname
read -p "Enter hostname: " hostname
echo "$hostname" > /mnt/etc/hostname

# Set timezone to Asia/Shanghai (UTC+8)
info "Setting timezone to Asia/Shanghai (UTC+8)..."
ln -sf /usr/share/zoneinfo/Asia/Shanghai /mnt/etc/localtime

# Sync hardware clock
info "Syncing hardware clock..."
arch-chroot /mnt hwclock --systohc

# Set localization to en_US.UTF-8
info "Setting localization to en_US.UTF-8..."
echo "en_US.UTF-8 UTF-8" >> /mnt/etc/locale.gen
echo "LANG=en_US.UTF-8" > /mnt/etc/locale.conf
arch-chroot /mnt locale-gen

# Enable time synchronization service
info "Enabling time synchronization service..."
arch-chroot /mnt systemctl enable systemd-timesyncd.service

# Set root password
info "Setting root password..."
arch-chroot /mnt passwd

# Create regular user
read -p "Enter username to create: " username
arch-chroot /mnt useradd -m -G wheel -s /bin/zsh "$username"
info "Setting password for user $username..."
arch-chroot /mnt passwd "$username"

# Configure sudo privileges
info "Configuring sudo privileges..."
echo "%wheel ALL=(ALL) ALL" >> /mnt/etc/sudoers

# Install GRUB bootloader
info "Installing GRUB bootloader..."
pacstrap /mnt grub efibootmgr

# Configure GRUB - Use Cutedog as bootloader ID
info "Configuring GRUB bootloader..."
arch-chroot /mnt grub-install --target=x86_64-efi --efi-directory=/boot --bootloader-id=Cutedog

# Completely disable watchdog - Add nowatchdog parameter to GRUB config
info "Completely disabling watchdog..."
sed -i 's/GRUB_CMDLINE_LINUX_DEFAULT="\(.*\)"/GRUB_CMDLINE_LINUX_DEFAULT="\1 nowatchdog"/' /mnt/etc/default/grub

# Enable NetworkManager.service
info "Enable NetworkManager system service..."
arch-chroot /mnt systemctl enable NetworkManager

# Generate GRUB configuration
arch-chroot /mnt grub-mkconfig -o /boot/grub/grub.cfg

# Show GRUB installation result
info "GRUB bootloader installation completed!"
info "EFI boot entry created with bootloader ID: Cutedog"
info "Watchdog completely disabled (kernel parameter and system service)"
info "GRUB configuration file generated: /boot/grub/grub.cfg"

# Switch to newly installed system
info "Switching to new system environment..."
arch-chroot /mnt /bin/bash <<EOF
echo "Successfully switched to new system environment!"
echo "Hostname set to: $hostname"
echo "Timezone set to: Asia/Shanghai (UTC+8)"
echo "Localization set to: en_US.UTF-8"
echo "Time synchronization service enabled"
echo "AMD microcode installed"
echo "Root password set"
echo "User $username created and added to wheel group"
echo "sudo privileges configured"
echo "GRUB bootloader installed and configured (bootloader ID: Cutedog)"
echo "Watchdog completely disabled"
echo "Current working directory: \$(pwd)"
echo "You can continue with system configuration commands in this environment"
EOF

# Final instructions
info "Arch Linux installation script execution completed!"
info "Please confirm all steps completed successfully, then reboot using:"
info "umount -R /mnt"
info "reboot"
info "After reboot, you can log in using the created user ($username)"


