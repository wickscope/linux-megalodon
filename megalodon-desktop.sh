#!/usr/bin/env bash
# LINUX MEGALODON - your desktop, in FLIPPER X colours. Run AFTER megalodon-setup.sh
# and a reboot, logged in to the desktop, WITHOUT sudo:   ./megalodon-desktop.sh
set -uo pipefail
[[ $EUID -ne 0 ]] || { echo "run this one WITHOUT sudo"; exit 1; }
say() { printf '\033[1;32m[megalodon]\033[0m %s\n' "$*"; }
WP=/usr/share/backgrounds/megalodon/wallpaper.png
[[ -f "$WP" ]] || { echo "run sudo ./megalodon-setup.sh first"; exit 1; }

say "wallpaper"
if command -v xfconf-query >/dev/null; then
  props=$(xfconf-query -c xfce4-desktop -l 2>/dev/null | grep 'last-image$' || true)
  if [[ -z "$props" ]]; then
    for m in $(xrandr --listmonitors 2>/dev/null | awk 'NR>1{print $NF}'); do
      props+=$'\n'"/backdrop/screen0/monitor${m}/workspace0/last-image"
    done
  fi
  for p in $props; do
    xfconf-query -c xfce4-desktop -p "$p" -n -t string -s "$WP" 2>/dev/null || xfconf-query -c xfce4-desktop -p "$p" -s "$WP"
    xfconf-query -c xfce4-desktop -p "${p%last-image}image-style" -n -t int -s 5 2>/dev/null || true
  done
elif command -v gsettings >/dev/null; then
  gsettings set org.gnome.desktop.background picture-uri "file://$WP"
  gsettings set org.gnome.desktop.background picture-uri-dark "file://$WP"
fi

say "terminal colours"
QT="$HOME/.config/qterminal.org/qterminal.ini"
mkdir -p "$(dirname "$QT")"
if [[ -f "$QT" ]] && grep -q '^colorScheme=' "$QT"; then
  sed -i 's/^colorScheme=.*/colorScheme=Megalodon/' "$QT"
elif [[ -f "$QT" ]] && grep -q '^\[General\]' "$QT"; then
  sed -i '/^\[General\]/a colorScheme=Megalodon' "$QT"
else
  printf '[General]\ncolorScheme=Megalodon\n' >> "$QT"
fi
if command -v xfconf-query >/dev/null; then
  xfconf-query -c xfce4-terminal -p /color-use-theme -n -t bool -s false 2>/dev/null || true
  xfconf-query -c xfce4-terminal -p /color-foreground -n -t string -s '#c6ead9' 2>/dev/null || true
  xfconf-query -c xfce4-terminal -p /color-background -n -t string -s '#060d0b' 2>/dev/null || true
  xfconf-query -c xfce4-terminal -p /color-cursor -n -t string -s '#2bd48a' 2>/dev/null || true
  xfconf-query -c xfce4-terminal -p /color-palette -n -t string -s \
    '#0b1613;#e2564a;#2bd48a;#e0ad4e;#1d9e75;#5f9d87;#5dcaa5;#c6ead9;#3f9e80;#f0786c;#5dcaa5;#ffd36b;#5dcaa5;#8cc8b4;#96e6cd;#eafff6' 2>/dev/null || true
fi

say "menu button = the shark"
for rc in "$HOME"/.config/xfce4/panel/whiskermenu-*.rc; do
  [[ -f "$rc" ]] || continue
  if grep -q '^button-icon=' "$rc"; then
    sed -i 's#^button-icon=.*#button-icon=/usr/share/megalodon/logo.png#' "$rc"
  else
    echo "button-icon=/usr/share/megalodon/logo.png" >> "$rc"
  fi
done
command -v xfce4-panel >/dev/null && xfce4-panel -r 2>/dev/null &

say "panic key: Ctrl+Alt+Backspace = power off now"
if command -v xfconf-query >/dev/null; then
  xfconf-query -c xfce4-keyboard-shortcuts -p '/commands/custom/<Primary><Alt>BackSpace' -n -t string \
    -s 'sudo -n /usr/local/bin/megalodon panic' 2>/dev/null || true
fi

say "shell greeting"
mkdir -p "$HOME/.config/fastfetch"
cat > "$HOME/.config/fastfetch/config.jsonc" <<'EOF'
{
  "logo": { "source": "/usr/share/megalodon/ascii.txt", "color": { "1": "green", "2": "bright_green", "3": "yellow" } },
  "display": { "color": { "keys": "green", "title": "bright_green" } },
  "modules": ["title", "separator", "os", "kernel", "uptime", "cpu", "memory", "disk", "battery", "localip"]
}
EOF
for rcf in "$HOME/.zshrc" "$HOME/.bashrc"; do
  [[ -f "$rcf" ]] || continue
  grep -q 'MEGALODON-GREETING' "$rcf" || cat >> "$rcf" <<'EOF'

# MEGALODON-GREETING
if [[ $- == *i* ]] && command -v fastfetch >/dev/null; then fastfetch; fi
EOF
done

say "Flipper SDK (ufbt) for building Flipper Zero apps"
if command -v pipx >/dev/null; then
  pipx install ufbt >/dev/null 2>&1 && say "ufbt installed" || say "ufbt: already there or needs network - retry: pipx install ufbt"
  pipx ensurepath >/dev/null 2>&1 || true
fi

say "done - open a new terminal to see it. (Log out and back in once so the dialout/plugdev groups apply.)"
