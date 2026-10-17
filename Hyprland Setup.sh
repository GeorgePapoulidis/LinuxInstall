#!/usr/bin/env bash
set -euo pipefail

source "Config.env"

mkdir -p ~/.config/{hypr,waybar,dunst,rofi,kitty,gtk-3.0,gtk-4.0,qt5ct,qt6ct,environment.d}
mkdir -p ~/.local/bin
mkdir -p ~/Pictures/{Wallpapers,Screenshots}

magick -size 1920x1080 gradient:'#1e1e2e-#11111b' ~/Pictures/Wallpapers/default.png 2>/dev/null || \
    cp /usr/share/hypr/wall0.png ~/Pictures/Wallpapers/default.png 2>/dev/null || true

gsettings set org.gnome.desktop.interface color-scheme 'prefer-dark'
gsettings set org.gnome.desktop.interface gtk-theme 'adw-gtk3-dark'
gsettings set org.gnome.desktop.interface icon-theme 'Papirus-Dark'
gsettings set org.gnome.desktop.interface font-name 'JetBrainsMono Nerd Font 10'

cat << 'EOF' > ~/.config/gtk-3.0/settings.ini
[Settings]
gtk-application-prefer-dark-theme=1
gtk-theme-name=adw-gtk3-dark
gtk-icon-theme-name=Papirus-Dark
gtk-font-name=JetBrainsMono Nerd Font 10
EOF

cp ~/.config/gtk-3.0/settings.ini ~/.config/gtk-4.0/settings.ini

cat << 'EOF' > ~/.config/qt5ct/qt5ct.conf
[Appearance]
color_scheme_path=/usr/share/qt5ct/colors/darker.conf
custom_palette=true
icon_theme=Papirus-Dark
standard_dialogs=default
style=Fusion
EOF

cat << 'EOF' > ~/.config/qt6ct/qt6ct.conf
[Appearance]
color_scheme_path=/usr/share/qt6ct/colors/darker.conf
custom_palette=true
icon_theme=Papirus-Dark
standard_dialogs=default
style=Fusion
EOF

cat << 'EOF' > ~/.Xresources
Xft.dpi: 96
EOF

cat << 'EOF' > ~/.local/bin/check-nvme-space.sh
#!/usr/bin/env bash
set -euo pipefail

usage=$(df --output=pcent / | tail -n 1 | tr -dc '0-9')
if (( usage >= 90 )); then
    zenity --warning \
        --title="Storage Alert: NVMe Pool Critical" \
        --text="Btrfs pool usage on nvme0n1 is at ${usage}% (exceeds 90% threshold).\nOld snapshots or archived kernels should be pruned." \
        --width=420
fi
EOF
chmod +x ~/.local/bin/check-nvme-space.sh

cat << 'EOF' > ~/.local/bin/gamescope-hdr
#!/usr/bin/env bash
exec gamescope --hdr-enabled --hdr-sdr-content-nits 400 -f -- "$@"
EOF
chmod +x ~/.local/bin/gamescope-hdr

cat << 'EOF' > ~/.config/hypr/hyprpaper.conf
preload = ~/Pictures/Wallpapers/default.png
wallpaper = ,~/Pictures/Wallpapers/default.png
splash = false
EOF

cat << 'EOF' > ~/.config/hypr/hypridle.conf
general {
    lock_cmd = pidof hyprlock || hyprlock
    before_sleep_cmd = loginctl lock-session
    after_sleep_cmd = hyprctl dispatch dpms on
}

listener {
    timeout = 300
    on-timeout = loginctl lock-session
}

listener {
    timeout = 600
    on-timeout = hyprctl dispatch dpms off
    on-resume = hyprctl dispatch dpms on
}
EOF

cat << 'EOF' > ~/.config/hypr/hyprlock.conf
general {
    hide_cursor = true
    grace = 0
}

background {
    monitor =
    path = screenshot
    blur_passes = 3
    blur_size = 6
    color = rgba(30, 30, 46, 1.0)
}

input-field {
    monitor =
    size = 280, 55
    outline_thickness = 2
    dots_size = 0.25
    dots_spacing = 0.2
    outer_color = rgba(137, 180, 250, 1.0)
    inner_color = rgba(30, 30, 46, 0.85)
    font_color = rgb(205, 214, 244)
    fade_on_empty = false
    placeholder_text = <i>Password...</i>
    position = 0, -40
    halign = center
    valign = center
}
EOF

cat << 'EOF' > ~/.config/hypr/hyprland.conf
monitor = ,preferred,auto,1

env = LIBVA_DRIVER_NAME,nvidia
env = __GLX_VENDOR_LIBRARY_NAME,nvidia
env = NVD_BACKEND,direct
env = ELECTRON_OZONE_PLATFORM_HINT,auto
env = XDG_CURRENT_DESKTOP,Hyprland
env = XDG_SESSION_TYPE,wayland
env = XDG_SESSION_DESKTOP,Hyprland
env = QT_QPA_PLATFORM,wayland;xcb
env = QT_QPA_PLATFORMTHEME,qt6ct
env = QT_WAYLAND_DISABLE_WINDOWDECORATION,1
env = GTK_THEME,adw-gtk3-dark
env = XCURSOR_SIZE,24

exec-once = dbus-update-activation-environment --systemd WAYLAND_DISPLAY XDG_CURRENT_DESKTOP
exec-once = systemctl --user import-environment WAYLAND_DISPLAY XDG_CURRENT_DESKTOP
exec-once = /usr/lib/hyprpolkitagent/hyprpolkitagent
exec-once = xrdb -merge ~/.Xresources
exec-once = hyprpaper
exec-once = waybar
exec-once = dunst
exec-once = swayosd-server
exec-once = nm-applet --indicator
exec-once = blueman-applet
exec-once = wl-paste --type text --watch cliphist store
exec-once = wl-paste --type image --watch cliphist store
exec-once = hypridle
exec-once = ~/.local/bin/check-nvme-space.sh

input {
    kb_layout = us,gr
    kb_options = grp:alt_shift_toggle
    numlock_by_default = true
    follow_mouse = 1
    sensitivity = 0
}

general {
    gaps_in = 5
    gaps_out = 10
    border_size = 2
    col.active_border = rgba(89b4faee) rgba(cba6f7ee) 45deg
    col.inactive_border = rgba(45475aaa)
    layout = dwindle
    allow_tearing = true
}

decoration {
    rounding = 12
    active_opacity = 1.0
    inactive_opacity = 1.0

    shadow {
        enabled = true
        range = 12
        render_power = 3
        color = rgba(11111b99)
    }

    blur {
        enabled = true
        size = 6
        passes = 2
        new_optimizations = true
        xray = true
        ignore_opacity = true
    }
}

animations {
    enabled = true
    bezier = fluent, 0.05, 0.9, 0.1, 1.05
    bezier = linear, 0.0, 0.0, 1.0, 1.0

    animation = windows, 1, 4, fluent, slide
    animation = windowsOut, 1, 4, fluent, popin 80%
    animation = border, 1, 8, default
    animation = borderangle, 1, 60, linear, loop
    animation = fade, 1, 4, default
    animation = workspaces, 1, 4, fluent, slide
}

dwindle {
    pseudotile = true
    preserve_split = true
}

misc {
    vrr = 2
    disable_hyprland_logo = true
    disable_splash_rendering = true
    force_default_wallpaper = 0
}

windowrule = immediate on, match:class ^(steam_app_.*)$

windowrule = opacity 0.90 0.82, match:class ^(kitty)$
windowrule = opacity 0.92 0.85, match:class ^(thunar)$
windowrule = float on, match:class ^(org.pulseaudio.pavucontrol)$
windowrule = float on, match:class ^(blueman-manager)$
windowrule = float on, match:class ^(nm-connection-editor)$
windowrule = float on, match:class ^(zenity)$

layerrule = blur on, ignore_alpha 0, match:namespace waybar
layerrule = blur on, ignore_alpha 0, match:namespace notifications
layerrule = blur on, ignore_alpha 0, match:namespace rofi

$mainMod = SUPER

bind = $mainMod, Return, exec, kitty
bind = $mainMod, Q, killactive,
bind = $mainMod, E, exec, thunar
bind = $mainMod, V, togglefloating,
bind = $mainMod, F, fullscreen, 0
bind = $mainMod, D, exec, rofi -show drun -show-icons
bind = $mainMod, C, exec, cliphist list | rofi -dmenu -p "Clipboard" | cliphist decode | wl-copy
bind = $mainMod, L, exec, hyprlock
bind = $mainMod SHIFT, M, exit,

bind = , Print, exec, grim -g "$(slurp)" - | wl-copy
bind = SHIFT, Print, exec, grim -g "$(slurp)" - | swappy -f -

bindel = , XF86AudioRaiseVolume, exec, swayosd-client --output-volume raise
bindel = , XF86AudioLowerVolume, exec, swayosd-client --output-volume lower
bindl  = , XF86AudioMute, exec, swayosd-client --output-volume mute-toggle
bindl  = , XF86AudioPlay, exec, playerctl play-pause
bindl  = , XF86AudioNext, exec, playerctl next
bindl  = , XF86AudioPrev, exec, playerctl previous

bind = $mainMod, left, movefocus, l
bind = $mainMod, right, movefocus, r
bind = $mainMod, up, movefocus, u
bind = $mainMod, down, movefocus, d

bind = $mainMod, 1, workspace, 1
bind = $mainMod, 2, workspace, 2
bind = $mainMod, 3, workspace, 3
bind = $mainMod, 4, workspace, 4
bind = $mainMod, 5, workspace, 5
bind = $mainMod, 6, workspace, 6
bind = $mainMod, 7, workspace, 7
bind = $mainMod, 8, workspace, 8
bind = $mainMod, 9, workspace, 9
bind = $mainMod, 0, workspace, 10

bind = $mainMod SHIFT, 1, movetoworkspace, 1
bind = $mainMod SHIFT, 2, movetoworkspace, 2
bind = $mainMod SHIFT, 3, movetoworkspace, 3
bind = $mainMod SHIFT, 4, movetoworkspace, 4
bind = $mainMod SHIFT, 5, movetoworkspace, 5
bind = $mainMod SHIFT, 6, movetoworkspace, 6
bind = $mainMod SHIFT, 7, movetoworkspace, 7
bind = $mainMod SHIFT, 8, movetoworkspace, 8
bind = $mainMod SHIFT, 9, movetoworkspace, 9
bind = $mainMod SHIFT, 0, movetoworkspace, 10

bindm = $mainMod, mouse:272, movewindow
bindm = $mainMod, mouse:273, resizewindow
EOF

cat << 'EOF' > ~/.config/waybar/config.jsonc
{
    "layer": "top",
    "position": "top",
    "height": 36,
    "margin-top": 6,
    "margin-left": 10,
    "margin-right": 10,
    "spacing": 8,

    "modules-left": [
        "custom/launcher",
        "hyprland/workspaces",
        "wlr/taskbar"
    ],
    "modules-center": [
        "clock"
    ],
    "modules-right": [
        "custom/clipboard",
        "hyprland/language",
        "pulseaudio",
        "network",
        "cpu",
        "memory",
        "tray"
    ],

    "custom/launcher": {
        "format": "  ",
        "on-click": "rofi -show drun -show-icons",
        "tooltip": false
    },

    "hyprland/workspaces": {
        "on-click": "activate",
        "active-only": false,
        "all-outputs": true,
        "format": "{name}"
    },

    "wlr/taskbar": {
        "format": "{icon}",
        "icon-size": 18,
        "tooltip-format": "{title}",
        "on-click": "activate",
        "on-click-middle": "close"
    },

    "clock": {
        "format": "󰥔  {:%H:%M   󰃭  %a, %d %b}",
        "tooltip-format": "<big>{:%Y %B}</big>\n<tt><small>{calendar}</small></tt>"
    },

    "custom/clipboard": {
        "format": "󰅌",
        "on-click": "cliphist list | rofi -dmenu -p 'Clipboard' | cliphist decode | wl-copy",
        "tooltip-format": "Clipboard History (Super+C)"
    },

    "hyprland/language": {
        "format": "󰌌  {}",
        "format-en": "US",
        "format-gr": "GR",
        "on-click": "hyprctl switchxkblayout all next"
    },

    "pulseaudio": {
        "format": "{icon} {volume}%",
        "format-muted": "󰝟 Muted",
        "format-icons": {
            "default": ["󰕿", "󰖀", "󰕾"]
        },
        "on-click": "pavucontrol",
        "on-click-right": "pamixer -t"
    },

    "network": {
        "format-wifi": "󰤨  {essid}",
        "format-ethernet": "󰈀  Wired",
        "format-disconnected": "󰤭  Offline",
        "tooltip-format": "{ifname}: {ipaddr}/{cidr}",
        "on-click": "nm-connection-editor"
    },

    "cpu": {
        "format": "󰻠 {usage}%",
        "interval": 3
    },

    "memory": {
        "format": "󰍛 {percentage}%",
        "interval": 3
    },

    "tray": {
        "icon-size": 18,
        "spacing": 8
    }
}
EOF

cat << 'EOF' > ~/.config/waybar/style.css
* {
    font-family: "JetBrainsMono Nerd Font", sans-serif;
    font-size: 13px;
    font-weight: 600;
    border: none;
    border-radius: 12px;
}

window#waybar {
    background-color: rgba(30, 30, 46, 0.78);
    color: #cdd6f4;
    border: 1px solid rgba(137, 180, 250, 0.25);
}

#custom-launcher {
    color: #89b4fa;
    font-size: 16px;
    padding: 0 10px;
}

#workspaces button {
    padding: 0 8px;
    color: #7f849c;
    background: transparent;
}

#workspaces button.active {
    color: #1e1e2e;
    background: #89b4fa;
    border-radius: 8px;
}

#taskbar button {
    padding: 0 6px;
    margin: 2px;
    border-radius: 8px;
}

#taskbar button.active {
    background-color: rgba(203, 166, 247, 0.25);
}

#clock,
#custom-clipboard,
#language,
#pulseaudio,
#network,
#cpu,
#memory,
#tray {
    padding: 0 10px;
    margin: 4px 2px;
    background-color: rgba(49, 50, 68, 0.65);
    border-radius: 8px;
}

#language {
    color: #f9e2af;
}

#pulseaudio {
    color: #cba6f7;
}

#network {
    color: #a6e3a1;
}
EOF

cat << 'EOF' > ~/.config/dunst/dunstrc
[global]
    font = JetBrainsMono Nerd Font 10
    width = 340
    height = 140
    origin = top-right
    offset = 14x14
    frame_width = 2
    frame_color = "#89b4fa"
    corner_radius = 12
    padding = 12
    horizontal_padding = 14
    background = "#1e1e2ee0"
    foreground = "#cdd6f4"

[urgency_low]
    background = "#1e1e2ee0"
    foreground = "#a6adc8"
    frame_color = "#45475a"
    timeout = 4

[urgency_normal]
    background = "#1e1e2ee0"
    foreground = "#cdd6f4"
    frame_color = "#89b4fa"
    timeout = 6

[urgency_critical]
    background = "#1e1e2ef5"
    foreground = "#f38ba8"
    frame_color = "#f38ba8"
    timeout = 0
EOF

cat << 'EOF' > ~/.config/rofi/config.rasi
configuration {
    modi: "drun,run";
    show-icons: true;
    icon-theme: "Papirus-Dark";
    font: "JetBrainsMono Nerd Font 11";
    drun-display-format: "{name}";
}

@theme "/dev/null"

* {
    bg: rgba(30, 30, 46, 0.88);
    bg-alt: rgba(49, 50, 68, 0.75);
    fg: #cdd6f4;
    accent: #89b4fa;
    background-color: transparent;
    text-color: @fg;
}

window {
    width: 520px;
    background-color: @bg;
    border: 2px;
    border-color: @accent;
    border-radius: 12px;
    padding: 16px;
}

inputbar {
    children: [prompt, entry];
    background-color: @bg-alt;
    border-radius: 8px;
    padding: 10px;
    margin: 0 0 12px 0;
}

prompt {
    text-color: @accent;
    margin: 0 10px 0 0;
}

listview {
    lines: 8;
    columns: 1;
    fixed-height: false;
    spacing: 6px;
}

element {
    padding: 8px 12px;
    border-radius: 8px;
}

element selected {
    background-color: @accent;
    text-color: #1e1e2e;
}

element-icon {
    size: 24px;
    margin: 0 10px 0 0;
}
EOF

cat << 'EOF' > ~/.config/kitty/kitty.conf
font_family      JetBrainsMono Nerd Font
font_size        11.0
window_padding_width 10
confirm_os_window_close 0

foreground              #CDD6F4
background              #1E1E2E
selection_foreground    #1E1E2E
selection_background    #F5E0DC
cursor                  #F5E0DC
cursor_text_color       #1E1E2E

color0 #45475A
color8 #585B70
color1 #F38BA8
color9 #F38BA8
color2 #A6E3A1
color10 #A6E3A1
color3 #F9E2AF
color11 #F9E2AF
color4 #89B4FA
color12 #89B4FA
color5 #F5C2E7
color13 #F5C2E7
color6 #94E2D5
color14 #94E2D5
color7 #BAC2DE
color15 #A6ADC8
EOF

if ! grep -q "exec Hyprland" ~/.bash_profile 2>/dev/null; then
    cat << 'EOF' >> ~/.bash_profile

if [[ -z "${DISPLAY:-}" && -z "${WAYLAND_DISPLAY:-}" && "${XDG_VTNR:-0}" -eq 1 ]]; then
    exec Hyprland
fi
EOF
fi

chmod +x "Finish.sh"
echo "Executing Finish.sh"
"./Finish.sh"
