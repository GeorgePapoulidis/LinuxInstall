#!/usr/bin/env bash
set -euo pipefail

source "Config.env"

# Boot from the new system and continue with the rest of the commands
# ==============================================================================
# 4. Configuring package managers and downloading packages
# ==============================================================================

cat << UpdateConfigFile >> Config.env

export USER_UID=\$(id -u "$USERNAME")
export USER_GID=\$(id -g "$USERNAME")
export KEY_DIR="\$(getent passwd "$USERNAME" | cut -d: -f6)/Security"
UpdateConfigFile

source Config.env

sudo sed -i "/\[multilib\]/,/Include/"'s/^#//' /etc/pacman.conf
sudo sed -i \
  -e 's/^#Color/Color/' \
  -e 's/^#VerbosePkgLists/VerbosePkgLists/' \
  -e "s/^#\?ParallelDownloads.*/ParallelDownloads = ${PARALLEL_DOWNLOADS}\nILoveCandy/" \
  /etc/pacman.conf
sudo sed -i 's/^#MAKEFLAGS=.*/MAKEFLAGS="-j$(nproc)"/' /etc/makepkg.conf

sudo pacman -Syu --needed --noconfirm base-devel git
git clone https://aur.archlinux.org/paru-bin.git /tmp/paru-bin
(cd /tmp/paru-bin && makepkg -si --noconfirm)
sudo sed -i 's/^#SudoLoop/SudoLoop/' /etc/paru.conf
rm -rf /tmp/paru-bin

sudo pacman -S --needed --noconfirm flatpak
sudo flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo

paru -S --needed --noconfirm \
nvidia-580xx-dkms \
nvidia-580xx-utils \
lib32-nvidia-580xx-utils \
nvidia-580xx-settings \
libva-nvidia-driver

sudo pacman -S --needed --noconfirm \
base-devel \
git \
flatpak \
egl-wayland \
openbsd-netcat \
vulkan-icd-loader \
lib32-vulkan-icd-loader \
libva-utils \
v4l2loopback-dkms \
v4l2loopback-utils \
solaar \
piper \
libratbag \
openrgb \
lact \
lm_sensors \
liquidctl \
pipewire \
wireplumber \
pipewire-audio \
pipewire-pulse \
pipewire-alsa \
pipewire-jack \
alsa-utils \
libfreeaptx \
pavucontrol \
easyeffects \
bluez \
bluez-utils \
blueman \
cups \
hplip \
brightnessctl \
network-manager-applet \
xdg-user-dirs \
man-db \
man-pages \
dosfstools \
e2fsprogs \
ntfs-3g \
exfatprogs \
parted \
gparted \
bash-completion \
snapper \
snap-pac \
grub-btrfs \
inotify-tools \
pacman-contrib \
reflector \
zram-generator \
cmake \
ninja \
nasm \
gdb \
valgrind \
perf \
jdk-openjdk \
lua \
python \
python-pip \
nodejs \
npm \
ripgrep \
fd \
neovim \
tmux \
hyprland \
hyprpaper \
hyprlock \
hypridle \
hyprpicker \
hyprsunset \
hyprpolkitagent \
qt5-wayland \
qt6-wayland \
qt5ct \
qt6ct \
adw-gtk-theme \
xorg-xrdb \
swayosd \
playerctl \
pamixer \
swappy \
imagemagick \
waybar \
kitty \
rofi \
dunst \
zenity \
xdg-desktop-portal-hyprland \
xdg-desktop-portal-gtk \
grim \
slurp \
flameshot \
obs-studio \
wl-clipboard \
cliphist \
ttf-jetbrains-mono-nerd \
noto-fonts \
noto-fonts-cjk \
noto-fonts-emoji \
papirus-icon-theme \
thunar \
thunar-archive-plugin \
thunar-volman \
gvfs \
tumbler \
7zip \
unrar \
tar \
unzip \
zip \
galculator \
btop \
nvtop \
smartmontools \
baobab \
ncdu \
zathura \
zathura-pdf-mupdf \
fastfetch \
pkgfile \
firefox \
chromium \
qbittorrent \
handbrake \
ffmpeg \
vlc \
vlc-plugins-all \
libdvdcss \
gst-plugins-good \
gst-plugins-bad \
gst-plugins-ugly \
gst-libav \
steam \
gamescope \
mangohud \
lib32-mangohud \
gamemode \
lib32-gamemode \
prismlauncher \
wine-staging \
winetricks \
wine-mono \
giflib \
lib32-giflib \
loupe \
gimp \
keepassxc \
obsidian \
qemu-full \
virt-manager \
virt-viewer \
dnsmasq \
vde2 \
bridge-utils \
libguestfs \
wireshark-qt \
docker \
docker-compose \
nginx \
openssh \
lynis \
tpm2-tools \
openrazer-meta \
wireless-regdb \
lazygit \
github-cli \
clang \
lldb \
luarocks \
stylua \
shellcheck \
shfmt

paru -S --needed --noconfirm \
wl-clip-persist \
bambu-studio-bin \
notepadqq \
polychromatic \
flutter-bin \
android-studio \
coolercontrol-bin \
mkinitcpio-sd-numlock \
vscodium-bin \
rustdesk-bin \
immich-cli \
betterdiscordctl

flatpak install -y flathub \
com.heroicgameslauncher.hgl \
com.discordapp.Discord \
dev.vencord.Vesktop \
com.stremio.Stremio \
com.github.tchx84.Flatseal \
com.github.iwalton3.jellyfin-media-player \
org.onlyoffice.desktopeditors \
org.signal.Signal \
com.viber.Viber \
us.zoom.Zoom

# ==============================================================================
# 5. Enabling services and setting user groups
# ==============================================================================

sudo tee /etc/xdg/reflector/reflector.conf << 'EOF'
--save /etc/pacman.d/mirrorlist
--protocol https
--country Greece,Germany,Bulgaria
--latest 15
--sort rate
EOF

sudo mkdir -p /etc/systemd/system/paccache.service.d
sudo tee /etc/systemd/system/paccache.service.d/override.conf << 'EOF'
[Service]
ExecStart=
ExecStart=/usr/bin/paccache -rk2
ExecStart=/usr/bin/paccache -ruk0
EOF
sudo systemctl enable --now paccache.timer

sudo sed -i 's/^#WIRELESS_REGDOM="GR"/WIRELESS_REGDOM="GR"/' /etc/conf.d/wireless-regdom

sudo tee /etc/modules-load.d/openrgb.conf << 'EOF'
i2c-dev
i2c-piix4
EOF

sudo tee /etc/systemd/zram-generator.conf << 'EOF'
[zram0]
zram-size = ram
compression-algorithm = zstd
EOF

sudo systemctl daemon-reload
sudo systemctl start systemd-zram-setup@zram0.service
sudo systemctl enable bluetooth.service
sudo systemctl enable cups.service
sudo systemctl enable sshd.service
sudo systemctl enable --now coolercontrold.service
sudo systemctl enable --now openrgb.service
sudo systemctl enable --now lactd.service
sudo systemctl enable --now nvidia-persistenced.service
sudo systemctl enable nvidia-suspend.service nvidia-hibernate.service nvidia-resume.service
sudo systemctl enable --now systemd-oomd.service
sudo systemctl enable --now reflector.timer
sudo systemctl enable --now btrfs-scrub@-.timer
sudo systemctl enable --now libvirtd.service
sudo systemctl enable --now docker.service
sudo systemctl enable --now swayosd-libinput-backend.service
systemctl --user enable openrazer-daemon.service

sudo chown -R "$USERNAME:$USERNAME" /opt/flutter
cat << 'EOF' >> ~/.bashrc

export PATH="$PATH:/opt/flutter/bin:/opt/flutter/bin/cache/dart-sdk/bin"
EOF

sudo usermod -aG libvirt,kvm,docker,wireshark,openrazer "$USERNAME"

sudo useradd -m -s /bin/bash -G docker "$SERVER_USERNAME"
sudo loginctl enable-linger "$SERVER_USERNAME"

xdg-user-dirs-update
sudo pkgfile --update

sudo btrfs quota enable /
sudo btrfs quota enable /home

sudo tee /etc/modprobe.d/nvidia-power-management.conf << 'EOF'
options nvidia NVreg_PreserveVideoMemoryAllocations=1
options nvidia NVreg_TemporaryFilePath=/var/tmp
EOF

SWAP_OFFSET=$(sudo btrfs inspect-internal map-swapfile -r /swap/swapfile)

sudo sed -i "s|\(GRUB_CMDLINE_LINUX_DEFAULT=\".*\)\"|\1 resume=/dev/mapper/${MAPPER_NAME} resume_offset=${SWAP_OFFSET}\"|" /etc/default/grub

sudo grub-mkconfig -o /boot/grub/grub.cfg

sudo sed -i 's/^MODULES=(nvme)/MODULES=(nvme nvidia nvidia_modeset nvidia_uvm nvidia_drm)/' /etc/mkinitcpio.conf
sudo sed -i 's/keyboard sd-vconsole/keyboard sd-numlock sd-vconsole/' /etc/mkinitcpio.conf

sudo mkinitcpio -P

# ==============================================================================
# 6. Setting colors in the terminal
# ==============================================================================

cat << 'EOF' >> ~/.bashrc

if [ -x /usr/bin/dircolors ]; then
    test -r ~/.dircolors && eval "$(dircolors -b ~/.dircolors)" || eval "$(dircolors -b)"
    alias dir='dir --color=auto'
    alias vdir='vdir --color=auto'
fi

alias diff='diff --color=auto'

alias ip='ip -color=auto'

export LESS='-R --use-color -Dd+r -Du+b'
export MANPAGER="less -R --use-color -Dd+r -Du+b"
export MANROFFOPT="-P -c"

if [ -f /usr/share/doc/pkgfile/command-not-found.bash ]; then
    source /usr/share/doc/pkgfile/command-not-found.bash
fi

EOF

git config --global color.ui auto

chmod +x "Boot Setup.sh"
"./Boot Setup.sh"
