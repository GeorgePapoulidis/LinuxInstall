#!/usr/bin/env bash
set -euo pipefail

source "Config.env"

mkdir -p "$KEY_DIR"
chmod 700 "$KEY_DIR"

echo "Key directory ready at: $KEY_DIR (Owned by $USERNAME)"
echo "Scanning all unmounted partitions..."

mapfile -t PARTITIONS < <(lsblk -rno NAME,FSTYPE,UUID,SIZE,MOUNTPOINT,LABEL | awk -F'[ ]' '$2!="" && $2!="swap" && $2!="squashfs" && $5=="" {print $1 "|" $2 "|" $3 "|" $4 "|" $6}')

if [ ${#PARTITIONS[@]} -eq 0 ]; then
    echo "No unmounted partitions found."
else
    for entry in "${PARTITIONS[@]}"; do
        IFS="|" read -r part_name fs_type part_uuid part_size part_label <<< "$entry"
        part_label="${part_label//\\x20/ }"
        dev_path="/dev/$part_name"

        if [[ "$fs_type" == "crypto_LUKS" ]]; then
            if lsblk -rno NAME "$dev_path" | tail -n +2 | grep -q . || grep -q "$part_uuid" /etc/crypttab 2>/dev/null; then
                continue
            fi
            is_encrypted=true
        else
            if grep -q "$part_uuid" /etc/fstab 2>/dev/null; then
                continue
            fi
            is_encrypted=false
        fi

        echo "================================================"
        echo "Found Partition : $dev_path"
        echo "Type            : $fs_type $( [ "$is_encrypted" = true ] && echo "(Encrypted)" || echo "(Unencrypted)" )"
        echo "Size            : $part_size"
        echo "Current Label   : ${part_label:-<none>}"
        echo "UUID            : $part_uuid"
        echo "================================================"

        read -rp "Do you want to configure and auto-mount this drive? (y/n): " confirm </dev/tty
        if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
            continue
        fi

        default_name="${part_label// /_}"
        read -rp "Enter a name for this drive (no spaces) ${default_name:+[default: $default_name]}: " drive_name </dev/tty
        drive_name="${drive_name:-$default_name}"
        drive_name="${drive_name// /_}"

        while [[ -z "$drive_name" ]]; do
            read -rp "Drive name cannot be empty. Enter a short name: " drive_name </dev/tty
            drive_name="${drive_name// /_}"
        done

        read -rp "Enter mount point [default: /mnt/$drive_name]: " mount_point </dev/tty
        mount_point="${mount_point:-/mnt/$drive_name}"

        if [ "$is_encrypted" = true ]; then
            key_file="$KEY_DIR/${drive_name}.key"

            if [ ! -f "$key_file" ]; then
                echo "Generating user-owned keyfile at $key_file..."
                dd if=/dev/urandom of="$key_file" bs=1024 count=4 status=none
                chmod 600 "$key_file"
                chown "$USERNAME:$USERNAME" "$key_file"
            else
                echo "Keyfile $key_file already exists. Using existing keyfile."
            fi

            echo "Enter existing LUKS password for $dev_path to enroll the keyfile:"
            sudo cryptsetup luksAddKey "$dev_path" "$key_file" </dev/tty

            echo "Unlocking $dev_path -> /dev/mapper/$drive_name..."
            sudo cryptsetup open "$dev_path" "$drive_name" --key-file "$key_file"

            echo "$drive_name UUID=$part_uuid $key_file luks,nofail" | sudo tee -a /etc/crypttab >/dev/null

            target_dev="/dev/mapper/$drive_name"
            inner_fs=$(lsblk -no FSTYPE "$target_dev" | head -n 1)
            fstab_source="$target_dev"
        else
            target_dev="$dev_path"
            inner_fs="$fs_type"
            fstab_source="UUID=$part_uuid"
        fi

        echo "Detected filesystem: $inner_fs"

        read -rp "Update filesystem label to '$drive_name'? (y/n): " set_label </dev/tty
        if [[ "$set_label" == "y" || "$set_label" == "Y" ]]; then
            case "$inner_fs" in
                ext4|ext3|ext2) sudo e2label "$target_dev" "$drive_name" ;;
                btrfs)          sudo btrfs filesystem label "$target_dev" "$drive_name" ;;
                ntfs)           sudo ntfslabel "$target_dev" "$drive_name" 2>/dev/null || true ;;
                exfat)          sudo exfatlabel "$target_dev" "$drive_name" 2>/dev/null || true ;;
                vfat|fat32)     sudo fatlabel "$target_dev" "$drive_name" 2>/dev/null || true ;;
            esac
        fi

        case "$inner_fs" in
            ntfs)
                mount_fs="ntfs3"
                mount_opts="defaults,nofail,uid=$USER_UID,gid=$USER_GID,umask=022"
                fs_pass=0
                ;;
            exfat|vfat|fat32)
                mount_fs="$inner_fs"
                mount_opts="defaults,nofail,uid=$USER_UID,gid=$USER_GID,umask=022"
                fs_pass=2
                ;;
            btrfs)
                mount_fs="btrfs"
                mount_opts="defaults,nofail"
                fs_pass=0
                ;;
            *)
                mount_fs="$inner_fs"
                mount_opts="defaults,nofail"
                fs_pass=2
                ;;
        esac

        sudo mkdir -p "$mount_point"
        echo "$fstab_source $mount_point $mount_fs $mount_opts 0 $fs_pass" | sudo tee -a /etc/fstab >/dev/null

        echo "Mounting $mount_point..."
        sudo mount "$mount_point"

        if [[ "$inner_fs" == "ext4" || "$inner_fs" == "btrfs" || "$inner_fs" == "xfs" ]]; then
            sudo chown "$USERNAME:$USERNAME" "$mount_point"
        fi

        echo "Success! $dev_path ($inner_fs) is mounted at $mount_point."
    done
fi

sudo systemctl daemon-reload
echo "================================================"
echo "All chosen drives are unlocked, mounted, and configured!"

chmod +x "Snapper Setup.sh"
sudo reboot
