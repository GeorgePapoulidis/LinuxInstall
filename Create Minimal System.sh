#!/usr/bin/env bash
set -euo pipefail

source "Config.env"

# ==============================================================================
# 2. Formatting encrypted disk
# ==============================================================================

wipefs -af "${DISK}"p* 2>/dev/null || true
wipefs -af "$DISK"
sgdisk --zap-all "$DISK"

sgdisk -n 1:0:+"$EFI_SIZE" -t 1:ef00 -c 1:"$PARTNAME_EFI" "$DISK"
sgdisk -n 2:0:+"$BOOT_SIZE" -t 2:ea00 -c 2:"$PARTNAME_BOOT" "$DISK"
sgdisk -n 3:0:0 -t 3:8309 -c 3:"$PARTNAME_LUKS" "$DISK"

partprobe "$DISK"
udevadm settle

mkfs.fat -F 32 -n "$LABEL_EFI" "${DISK}p1"
mkfs.ext4 -F -L "$LABEL_BOOT" "${DISK}p2"

cryptsetup luksFormat --type luks2 "${DISK}p3"
cryptsetup open "${DISK}p3" "$MAPPER_NAME"
mkfs.btrfs -f -L "$LABEL_BTRFS_FS" "/dev/mapper/${MAPPER_NAME}"

mount -t btrfs -o rw,noatime,ssd,discard=async,space_cache=v2 "/dev/mapper/${MAPPER_NAME}" /mnt
btrfs subvolume create "/mnt/${SUBVOL_ROOT}"
btrfs subvolume create "/mnt/${SUBVOL_ROOT_SNAPS}"
btrfs subvolume create "/mnt/${SUBVOL_HOME}"
btrfs subvolume create "/mnt/${SUBVOL_HOME_SNAPS}"
btrfs subvolume create "/mnt/${SUBVOL_SWAP}"
btrfs subvolume create "/mnt/${SUBVOL_VAR_LOG}"
btrfs subvolume create "/mnt/${SUBVOL_VAR_CACHE}"
umount /mnt

mount -t btrfs -o rw,noatime,ssd,discard=async,space_cache=v2,compress=zstd:1,subvol="${SUBVOL_ROOT}" "/dev/mapper/${MAPPER_NAME}" /mnt

mkdir -p /mnt/.snapshots
mkdir -p /mnt/home
mkdir -p /mnt/swap
mkdir -p /mnt/boot
mkdir -p /mnt/var/log
mkdir -p /mnt/var/cache

mount -t ext4 -o rw,noatime,discard "/dev/${DISK##*/}p2" /mnt/boot

mount -t btrfs -o rw,noatime,ssd,discard=async,space_cache=v2,compress=zstd:1,subvol="${SUBVOL_HOME}" "/dev/mapper/${MAPPER_NAME}" /mnt/home
mount -t btrfs -o rw,noatime,ssd,discard=async,space_cache=v2,compress=zstd:1,subvol="${SUBVOL_ROOT_SNAPS}" "/dev/mapper/${MAPPER_NAME}" /mnt/.snapshots
mount -t btrfs -o rw,noatime,ssd,discard=async,space_cache=v2,compress=zstd:1,subvol="${SUBVOL_VAR_LOG}" "/dev/mapper/${MAPPER_NAME}" /mnt/var/log
mount -t btrfs -o rw,noatime,ssd,discard=async,space_cache=v2,compress=zstd:1,subvol="${SUBVOL_VAR_CACHE}" "/dev/mapper/${MAPPER_NAME}" /mnt/var/cache
mount -t btrfs -o rw,noatime,ssd,discard=async,space_cache=v2,compress=none,subvol="${SUBVOL_SWAP}" "/dev/mapper/${MAPPER_NAME}" /mnt/swap

mkdir -p /mnt/home/.snapshots
mount -t btrfs -o rw,noatime,ssd,discard=async,space_cache=v2,compress=zstd:1,subvol="${SUBVOL_HOME_SNAPS}" "/dev/mapper/${MAPPER_NAME}" /mnt/home/.snapshots

mkdir -p /mnt/boot/efi
mount -t vfat -o rw,noatime,fmask=0077,dmask=0077,discard "/dev/${DISK##*/}p1" /mnt/boot/efi

btrfs filesystem mkswapfile --size ${SWAP_SIZE}g /mnt/swap/swapfile

# ==============================================================================
# 3. Setting up minimal system
# ==============================================================================

pacstrap -K /mnt \
base \
linux \
linux-firmware \
linux-headers \
amd-ucode \
btrfs-progs \
cryptsetup \
vim \
grub \
efibootmgr \
plymouth \
os-prober \
networkmanager \
sudo

swapon /mnt/swap/swapfile
genfstab -U /mnt >> /mnt/etc/fstab

read -rsp "Enter password for root: " ROOT_PASSWORD
echo
read -rsp "Enter password for $USERNAME: " USER_PASSWORD
echo

arch-chroot -S /mnt /bin/bash 3<&0 << CHROOT
sed -i '/^#en_GB.UTF-8 UTF-8/s/^#//' /etc/locale.gen
sed -i '/^#el_GR.UTF-8 UTF-8/s/^#//' /etc/locale.gen
locale-gen
echo "LANG=en_GB.UTF-8" > /etc/locale.conf
echo "$HOSTNAME" > /etc/hostname
echo "KEYMAP=us" > /etc/vconsole.conf

cat << HOSTSEOF > /etc/hosts
127.0.0.1 localhost
::1 localhost
127.0.1.1 $HOSTNAME.localdomain $HOSTNAME
HOSTSEOF

echo "EDITOR=vim" >> /etc/environment
echo "VISUAL=vim" >> /etc/environment

ln -sf /usr/share/zoneinfo/Europe/Athens /etc/localtime
hwclock --systohc

echo 'COMPRESSION="cat"' >> /etc/mkinitcpio.conf

sed -i 's/^MODULES=(.*/MODULES=(nvme)/' /etc/mkinitcpio.conf
sed -i 's/^HOOKS=.*/HOOKS=(base systemd plymouth autodetect microcode modconf kms keyboard sd-vconsole block sd-encrypt btrfs filesystems fsck)/' /etc/mkinitcpio.conf

plymouth-set-default-theme -R bgrt

echo "root:${ROOT_PASSWORD}" | chpasswd

useradd -m -s /bin/bash "$USERNAME"
usermod -aG wheel "$USERNAME"

echo "$USERNAME:${USER_PASSWORD}" | chpasswd

echo "%wheel ALL=(ALL:ALL) ALL" > /etc/sudoers.d/00-wheel
chmod 0440 /etc/sudoers.d/00-wheel
visudo -c

UUID=\$(blkid -s UUID -o value "${DISK}p3")

sed -i "s|^GRUB_DEFAULT=.*|GRUB_DEFAULT=saved|" /etc/default/grub
sed -i "s|^#GRUB_SAVEDEFAULT=.*|GRUB_SAVEDEFAULT=true|" /etc/default/grub
sed -i "s|^GRUB_TIMEOUT=.*|GRUB_TIMEOUT=3|" /etc/default/grub
sed -i "s|^#GRUB_DISABLE_OS_PROBER=.*|GRUB_DISABLE_OS_PROBER=false|" /etc/default/grub
sed -i "s|^GRUB_DISTRIBUTOR=.*|GRUB_DISTRIBUTOR=\"$BOOTLOADER_ID\"|" /etc/default/grub

sed -i "s|^GRUB_CMDLINE_LINUX_DEFAULT=.*|GRUB_CMDLINE_LINUX_DEFAULT=\"quiet splash loglevel=3 rd.udev.log_priority=3 rd.luks.name=\${UUID}=${MAPPER_NAME} root=/dev/mapper/${MAPPER_NAME} rootflags=subvol=${SUBVOL_ROOT} nvidia_drm.modeset=1 rd.luks.options=discard nvidia_drm.fbdev=1\"|" /etc/default/grub

grub-install --target=x86_64-efi --efi-directory=/boot/efi --bootloader-id="$BOOTLOADER_ID"
grub-mkconfig -o /boot/grub/grub.cfg

systemctl enable NetworkManager.service
systemctl enable fstrim.timer
systemctl enable systemd-timesyncd.service

CHROOT

unset ROOT_PASSWORD USER_PASSWORD

swapoff /mnt/swap/swapfile
umount -R /mnt
#reboot
#
