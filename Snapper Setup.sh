#!/usr/bin/env bash
set -euo pipefail

source "Config.env"

sudo pacman -S --noconfirm --needed snapper grub-btrfs inotify-tools

sudo btrfs quota enable /
sudo btrfs quota enable /home

sudo umount /.snapshots
sudo rm -rf /.snapshots
sudo snapper -c root create-config /
sudo btrfs subvolume delete /.snapshots
sudo mkdir -p /.snapshots
sudo mount /.snapshots
sudo chmod 750 /.snapshots

sudo umount /home/.snapshots
sudo rm -rf /home/.snapshots
sudo snapper -c home create-config /home
sudo btrfs subvolume delete /home/.snapshots
sudo mkdir -p /home/.snapshots
sudo mount /home/.snapshots
sudo chmod 750 /home/.snapshots

sudo sed -i \
    -e "s|^ALLOW_USERS=.*|ALLOW_USERS=\"${USERNAME}\"|" \
    -e 's|^SPACE_LIMIT=.*|SPACE_LIMIT="0.2"|' \
    -e 's|^NUMBER_CLEANUP=.*|NUMBER_CLEANUP="yes"|' \
    -e 's|^NUMBER_LIMIT=.*|NUMBER_LIMIT="5"|' \
    -e 's|^NUMBER_LIMIT_IMPORTANT=.*|NUMBER_LIMIT_IMPORTANT="10"|' \
    -e 's|^TIMELINE_CREATE=.*|TIMELINE_CREATE="yes"|' \
    -e 's|^TIMELINE_CLEANUP=.*|TIMELINE_CLEANUP="yes"|' \
    -e 's|^TIMELINE_LIMIT_HOURLY=.*|TIMELINE_LIMIT_HOURLY="0"|' \
    -e 's|^TIMELINE_LIMIT_DAILY=.*|TIMELINE_LIMIT_DAILY="5"|' \
    -e 's|^TIMELINE_LIMIT_WEEKLY=.*|TIMELINE_LIMIT_WEEKLY="10"|' \
    -e 's|^TIMELINE_LIMIT_MONTHLY=.*|TIMELINE_LIMIT_MONTHLY="2"|' \
    -e 's|^TIMELINE_LIMIT_YEARLY=.*|TIMELINE_LIMIT_YEARLY="0"|' \
    /etc/snapper/configs/root

sudo sed -i \
    -e "s|^ALLOW_USERS=.*|ALLOW_USERS=\"${USERNAME}\"|" \
    -e 's|^SPACE_LIMIT=.*|SPACE_LIMIT="0.2"|' \
    -e 's|^NUMBER_CLEANUP=.*|NUMBER_CLEANUP="no"|' \
    -e 's|^TIMELINE_CREATE=.*|TIMELINE_CREATE="yes"|' \
    -e 's|^TIMELINE_CLEANUP=.*|TIMELINE_CLEANUP="yes"|' \
    -e 's|^TIMELINE_LIMIT_HOURLY=.*|TIMELINE_LIMIT_HOURLY="0"|' \
    -e 's|^TIMELINE_LIMIT_DAILY=.*|TIMELINE_LIMIT_DAILY="0"|' \
    -e 's|^TIMELINE_LIMIT_WEEKLY=.*|TIMELINE_LIMIT_WEEKLY="4"|' \
    -e 's|^TIMELINE_LIMIT_MONTHLY=.*|TIMELINE_LIMIT_MONTHLY="0"|' \
    -e 's|^TIMELINE_LIMIT_YEARLY=.*|TIMELINE_LIMIT_YEARLY="0"|' \
    /etc/snapper/configs/home

sudo systemctl enable --now snapper-timeline.timer
sudo systemctl enable --now snapper-cleanup.timer
sudo systemctl enable --now grub-btrfsd.service

sudo pacman -S --noconfirm --needed snap-pac

sudo touch /etc/kernel-pinned.conf

sudo tee /usr/local/sbin/kernel-archive-pre >/dev/null << 'EOF'
#!/usr/bin/env bash
set -euo pipefail

for vmlinuz in /boot/vmlinuz-*; do
    [[ -e "$vmlinuz" ]] || continue
    name="${vmlinuz#/boot/vmlinuz-}"

    if [[ "$name" =~ ^[0-9]+\.[0-9]+\.[0-9]+ ]]; then
        continue
    fi

    kver=$(file -bL "$vmlinuz" | grep -oP 'version \K[^ ]+' || true)
    [[ -n "$kver" ]] || continue

    if [[ -d "/usr/lib/modules/${kver}" ]]; then
        cp -p "$vmlinuz" "/boot/vmlinuz-${kver}"

        if [[ -f "/boot/initramfs-${name}.img" ]]; then
            cp -p "/boot/initramfs-${name}.img" "/boot/initramfs-${kver}.img"
        fi

        if [[ -f "/boot/initramfs-${name}-fallback.img" ]]; then
            cp -p "/boot/initramfs-${name}-fallback.img" "/boot/initramfs-${kver}-fallback.img"
        fi

        mkdir -p /usr/lib/modules/.archived
        rm -rf "/usr/lib/modules/.archived/${kver}"
        cp -a --reflink=always "/usr/lib/modules/${kver}" "/usr/lib/modules/.archived/${kver}"
    fi
done
EOF

sudo chmod 755 /usr/local/sbin/kernel-archive-pre

sudo tee /usr/local/sbin/kernel-archive-post >/dev/null << 'EOF'
#!/usr/bin/env bash
set -euo pipefail

if [[ -d /usr/lib/modules/.archived ]]; then
    for moddir in /usr/lib/modules/.archived/*; do
        [[ -d "$moddir" ]] || continue
        kver="${moddir##*/}"
        if [[ ! -d "/usr/lib/modules/${kver}" ]]; then
            mv "$moddir" "/usr/lib/modules/${kver}"
        else
            rm -rf "$moddir"
        fi
    done
fi

declare -A active_kvers=()
for vmlinuz in /boot/vmlinuz-*; do
    [[ -e "$vmlinuz" ]] || continue
    name="${vmlinuz#/boot/vmlinuz-}"
    if [[ ! "$name" =~ ^[0-9]+\.[0-9]+\.[0-9]+ ]]; then
        kver=$(file -bL "$vmlinuz" | grep -oP 'version \K[^ ]+' || true)
        [[ -n "$kver" ]] && active_kvers["$kver"]=1
    fi
done

declare -A pinned_kvers=()
if [[ -f /etc/kernel-pinned.conf ]]; then
    while IFS= read -r line; do
        line="${line%%#*}"
        line="${line#"${line%%[![:space:]]*}"}"
        line="${line%"${line##*[![:space:]]}"}"
        [[ -n "$line" ]] && pinned_kvers["$line"]=1
    done < /etc/kernel-pinned.conf
fi

now=$(date +%s)
declare -A archive_mtime=()

for vmlinuz in /boot/vmlinuz-*; do
    [[ -e "$vmlinuz" ]] || continue
    kver="${vmlinuz#/boot/vmlinuz-}"
    if [[ "$kver" =~ ^[0-9]+\.[0-9]+\.[0-9]+ ]]; then
        if [[ -n "${active_kvers[$kver]:-}" ]]; then
            rm -f "/boot/vmlinuz-${kver}" "/boot/initramfs-${kver}.img" "/boot/initramfs-${kver}-fallback.img"
            continue
        fi
        archive_mtime["$kver"]=$(stat -c %Y "$vmlinuz")
    fi
done

declare -A keep_kvers=()
for kver in "${!pinned_kvers[@]}"; do
    keep_kvers["$kver"]=1
done

newest_kver=""
newest_mtime=0
for kver in "${!archive_mtime[@]}"; do
    mtime="${archive_mtime[$kver]}"
    if (( mtime > newest_mtime )); then
        newest_mtime=$mtime
        newest_kver="$kver"
    fi
done
[[ -n "$newest_kver" ]] && keep_kvers["$newest_kver"]=1

targets=(604800 1209600 2592000)
for target in "${targets[@]}"; do
    best_kver=""
    best_diff=999999999
    for kver in "${!archive_mtime[@]}"; do
        age=$(( now - archive_mtime[$kver] ))
        diff=$(( age > target ? age - target : target - age ))
        if (( diff < best_diff )); then
            best_diff=$diff
            best_kver="$kver"
        fi
    done
    [[ -n "$best_kver" ]] && keep_kvers["$best_kver"]=1
done

for kver in "${!archive_mtime[@]}"; do
    if [[ -z "${keep_kvers[$kver]:-}" ]]; then
        rm -f "/boot/vmlinuz-${kver}" "/boot/initramfs-${kver}.img" "/boot/initramfs-${kver}-fallback.img"
        rm -rf "/usr/lib/modules/${kver}"
    fi
done

grub-mkconfig -o /boot/grub/grub.cfg
EOF

sudo chmod 755 /usr/local/sbin/kernel-archive-post

sudo mkdir -p /etc/pacman.d/hooks

sudo tee /etc/pacman.d/hooks/05-kernel-archive-pre.hook >/dev/null << 'EOF'
[Trigger]
Operation = Upgrade
Operation = Remove
Type = Path
Target = usr/lib/modules/*/vmlinuz

[Action]
Description = Archiving current kernel, uncompressed initramfs, and signed modules...
When = PreTransaction
Exec = /usr/local/sbin/kernel-archive-pre
EOF

sudo tee /etc/pacman.d/hooks/99-kernel-archive-post.hook >/dev/null << 'EOF'
[Trigger]
Operation = Install
Operation = Upgrade
Operation = Remove
Type = Path
Target = usr/lib/modules/*/vmlinuz
Target = usr/src/*/dkms.conf

[Action]
Description = Pruning archived kernels and updating GRUB menu...
When = PostTransaction
Exec = /usr/local/sbin/kernel-archive-post
EOF

chmod +x "Nvim Setup.sh"
echo "Executing Nvim Setup.sh"
"./Nvim Setup.sh"
