#!/usr/bin/env bash
set -euo pipefail

source "Config.env"

sudo pacman -S --noconfirm --needed snapper grub-btrfs inotify-tools snap-pac sbsigntools mokutil openssl linux-headers

sudo btrfs quota enable /
sudo btrfs quota enable /home

sudo umount /.snapshots 2>/dev/null || true
sudo rm -rf /.snapshots
sudo snapper -c root create-config /
sudo btrfs subvolume delete /.snapshots
sudo mkdir -p /.snapshots
if grep -q "[[:space:]]/\.snapshots[[:space:]]" /etc/fstab; then
    sudo mount /.snapshots
else
    sudo btrfs subvolume create /.snapshots
fi
sudo chmod 750 /.snapshots

sudo umount /home/.snapshots 2>/dev/null || true
sudo rm -rf /home/.snapshots
sudo snapper -c home create-config /home
sudo btrfs subvolume delete /home/.snapshots
sudo mkdir -p /home/.snapshots
if grep -q "[[:space:]]/home/\.snapshots[[:space:]]" /etc/fstab; then
    sudo mount /home/.snapshots
else
    sudo btrfs subvolume create /home/.snapshots
fi
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

sudo tee /usr/local/bin/flatpak >/dev/null << 'EOF'
#!/usr/bin/env bash
set -eo pipefail

REAL_FLATPAK="/usr/bin/flatpak"
CMD="${1:-}"

case "$CMD" in
    install|update|uninstall|remove)
        SNAP_NUM=$(sudo snapper -c root create -t pre -p -c number -d "flatpak $CMD")
        trap 'sudo snapper -c root create -t post --pre-number "$SNAP_NUM" -c number -d "flatpak $CMD"' EXIT
        ;;
esac

"$REAL_FLATPAK" "$@"
EOF
sudo chmod 755 /usr/local/bin/flatpak

MOK_DIR="/home/${USERNAME}/Security/MOK"
sudo mkdir -p "$MOK_DIR"

if [[ ! -f "${MOK_DIR}/MOK.priv" ]]; then
    sudo openssl req -new -x509 -newkey rsa:4096 \
        -keyout "${MOK_DIR}/MOK.priv" \
        -outform DER -out "${MOK_DIR}/MOK.der" \
        -nodes -days 36500 \
        -subj "/CN=${USERNAME} Arch Kernel Signing Key/"
    sudo openssl x509 -inform DER -in "${MOK_DIR}/MOK.der" -out "${MOK_DIR}/MOK.pem"
fi

sudo chown -R "${USERNAME}:${USERNAME}" "/home/${USERNAME}/Security"
sudo chmod 700 "$MOK_DIR"
sudo chmod 600 "${MOK_DIR}/MOK.priv"
sudo chmod 644 "${MOK_DIR}/MOK.der" "${MOK_DIR}/MOK.pem"

# BIOS / FIRMWARE ACTION REQUIRED:
# 1. Run `sudo mokutil --import /home/$USERNAME/Security/MOK/MOK.der` and set a one-time password.
# 2. Reboot into UEFI/BIOS settings: disable CSM/Legacy Boot and enable Secure Boot (Standard Mode).
# 3. If not using `shim-signed` with GRUB, enroll `/home/$USERNAME/Security/MOK/MOK.der` into the UEFI DB (Signature Database) directly inside your BIOS Key Management menu, or ensure your bootloader delegates to MOKManager on reboot to select "Enroll MOK" -> "Continue" -> enter your one-time password.

sudo mkdir -p /etc/dkms/framework.conf.d
sudo tee /etc/dkms/framework.conf.d/signing.conf >/dev/null << EOF
mok_signing_key="${MOK_DIR}/MOK.priv"
mok_certificate="${MOK_DIR}/MOK.der"
sign_file="/usr/lib/modules/\$kernelver/build/scripts/sign-file"
EOF

sudo tee /usr/local/sbin/sign-kernel-and-modules >/dev/null << EOF
#!/usr/bin/env bash
set -euo pipefail

MOK_PRIV="${MOK_DIR}/MOK.priv"
MOK_DER="${MOK_DIR}/MOK.der"
MOK_PEM="${MOK_DIR}/MOK.pem"

[[ -f "\$MOK_PRIV" && -f "\$MOK_DER" ]] || exit 0

for kdir in /usr/lib/modules/*; do
    [[ -d "\$kdir" ]] || continue
    kver="\${kdir##*/}"
    [[ "\$kver" == ".staging" || "\$kver" == ".archived" ]] && continue

    SIGN_FILE="\${kdir}/build/scripts/sign-file"
    if [[ -x "\$SIGN_FILE" ]]; then
        while IFS= read -r -d '' mod; do
            if [[ "\$mod" == *.ko ]]; then
                "\$SIGN_FILE" sha512 "\$MOK_PRIV" "\$MOK_DER" "\$mod"
            elif [[ "\$mod" == *.ko.zst ]]; then
                zstd -dfq "\$mod" -o "\${mod%.zst}"
                "\$SIGN_FILE" sha512 "\$MOK_PRIV" "\$MOK_DER" "\${mod%.zst}"
                zstd -fq --rm "\${mod%.zst}" -o "\$mod"
            elif [[ "\$mod" == *.ko.xz ]]; then
                xz -dfk "\$mod"
                "\$SIGN_FILE" sha512 "\$MOK_PRIV" "\$MOK_DER" "\${mod%.xz}"
                xz -fz "\${mod%.xz}"
            fi
        done < <(find "\$kdir/updates" "\$kdir/extramodules" "\$kdir/kernel/drivers/media" -type f \( -name "*.ko" -o -name "*.ko.zst" -o -name "*.ko.xz" \) -print0 2>/dev/null || true)
    fi
done

for vmlinuz in /boot/vmlinuz-*; do
    [[ -f "\$vmlinuz" ]] || continue
    if ! sbverify --cert "\$MOK_PEM" "\$vmlinuz" >/dev/null 2>&1; then
        sbsign --key "\$MOK_PRIV" --cert "\$MOK_PEM" --output "\${vmlinuz}.signed" "\$vmlinuz"
        mv "\${vmlinuz}.signed" "\$vmlinuz"
    fi
done
EOF
sudo chmod 755 /usr/local/sbin/sign-kernel-and-modules

sudo touch /etc/kernel-pinned.conf

sudo tee /usr/local/sbin/kernel-archive-pre >/dev/null << 'EOF'
#!/usr/bin/env bash
set -euo pipefail

rm -rf /boot/.staging /usr/lib/modules/.staging
mkdir -p /boot/.staging

for vmlinuz in /boot/vmlinuz-*; do
    [[ -e "$vmlinuz" ]] || continue
    name="${vmlinuz#/boot/vmlinuz-}"

    if [[ "$name" =~ ^[0-9]+\.[0-9]+\.[0-9]+ ]]; then
        continue
    fi

    kver=$(file -bL "$vmlinuz" | grep -oP 'version \K[^ ]+' || true)
    [[ -n "$kver" ]] || continue

    if [[ -d "/usr/lib/modules/${kver}" ]]; then
        cp -p "$vmlinuz" "/boot/.staging/vmlinuz.tmp"
        echo "$name" > "/boot/.staging/orig-name"
        echo "$kver" > "/boot/.staging/kver"

        if [[ -f "/boot/initramfs-${name}.img" ]]; then
            cp -p "/boot/initramfs-${name}.img" "/boot/.staging/initramfs.img.tmp"
        fi

        if [[ -f "/boot/initramfs-${name}-fallback.img" ]]; then
            cp -p "/boot/initramfs-${name}-fallback.img" "/boot/.staging/initramfs-fallback.img.tmp"
        fi

        cp -a --reflink=auto "/usr/lib/modules/${kver}" "/usr/lib/modules/.staging"
        break
    fi
done
EOF
sudo chmod 755 /usr/local/sbin/kernel-archive-pre

sudo tee /usr/local/sbin/kernel-archive-recover >/dev/null << 'EOF'
#!/usr/bin/env bash
set -euo pipefail

if [[ -f /boot/.staging/kver ]]; then
    kver=$(cat /boot/.staging/kver)
    orig_name="linux"
    [[ -f /boot/.staging/orig-name ]] && orig_name=$(cat /boot/.staging/orig-name)

    if [[ -d /usr/lib/modules/.staging && ! -d "/usr/lib/modules/${kver}" ]]; then
        cp -a --reflink=auto /usr/lib/modules/.staging "/usr/lib/modules/${kver}"
    fi

    if [[ -f /boot/.staging/vmlinuz.tmp && ! -f "/boot/vmlinuz-${orig_name}" ]]; then
        cp -p /boot/.staging/vmlinuz.tmp "/boot/vmlinuz-${orig_name}"
    fi
    if [[ -f /boot/.staging/initramfs.img.tmp && ! -f "/boot/initramfs-${orig_name}.img" ]]; then
        cp -p /boot/.staging/initramfs.img.tmp "/boot/initramfs-${orig_name}.img"
    fi
    if [[ -f /boot/.staging/initramfs-fallback.img.tmp && ! -f "/boot/initramfs-${orig_name}-fallback.img" ]]; then
        cp -p /boot/.staging/initramfs-fallback.img.tmp "/boot/initramfs-${orig_name}-fallback.img"
    fi
fi
EOF
sudo chmod 755 /usr/local/sbin/kernel-archive-recover

sudo tee /etc/systemd/system/kernel-archive-recover.service >/dev/null << 'EOF'
[Unit]
Description=Recover interrupted kernel upgrade from staging
DefaultDependencies=no
After=local-fs.target
Before=systemd-modules-load.service

[Service]
Type=oneshot
ExecStart=/usr/local/sbin/kernel-archive-recover

[Install]
WantedBy=sysinit.target
EOF
sudo systemctl enable kernel-archive-recover.service

sudo tee /usr/local/sbin/kernel-archive-post >/dev/null << 'EOF'
#!/usr/bin/env bash
set -euo pipefail

/usr/local/sbin/sign-kernel-and-modules

if [[ -f /boot/.staging/vmlinuz.tmp ]]; then
    kver=""
    [[ -f /boot/.staging/kver ]] && kver=$(cat /boot/.staging/kver)
    if [[ -z "$kver" ]]; then
        kver=$(file -bL /boot/.staging/vmlinuz.tmp | grep -oP 'version \K[^ ]+' || true)
    fi

    if [[ -n "$kver" ]]; then
        if [[ -d /usr/lib/modules/.staging ]]; then
            if [[ ! -d "/usr/lib/modules/${kver}" ]]; then
                mv /usr/lib/modules/.staging "/usr/lib/modules/${kver}"
            else
                rm -rf /usr/lib/modules/.staging
            fi
        fi

        mv /boot/.staging/vmlinuz.tmp "/boot/vmlinuz-${kver}"
        if [[ -f /boot/.staging/initramfs.img.tmp ]]; then
            mv /boot/.staging/initramfs.img.tmp "/boot/initramfs-${kver}.img"
        fi
        if [[ -f /boot/.staging/initramfs-fallback.img.tmp ]]; then
            mv /boot/.staging/initramfs-fallback.img.tmp "/boot/initramfs-${kver}-fallback.img"
        fi
    fi
    rm -rf /boot/.staging /usr/lib/modules/.staging
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
        line="${line\%"${line##*[![:space:]]}"}"
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
        archive_mtime["$kver"]=$(stat -c \%Y "$vmlinuz")
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
Description = Staging current kernel, initramfs, and modules to single temporary backup...
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
Target = usr/lib/modules/*/updates/*
Target = usr/lib/modules/*/extramodules/*

[Action]
Description = Signing kernels/modules, promoting staged backup, and updating GRUB...
When = PostTransaction
Exec = /usr/local/sbin/kernel-archive-post
EOF

sudo /usr/local/sbin/sign-kernel-and-modules
sudo mkinitcpio -P
sudo grub-mkconfig -o /boot/grub/grub.cfg

chmod +x "Nvim Setup.sh"
echo "Executing Nvim Setup.sh"
"./Nvim Setup.sh"
