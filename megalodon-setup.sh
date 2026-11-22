#!/usr/bin/env bash
# =====================================================================
#  LINUX MEGALODON  -  post-install for a fresh, ENCRYPTED Kali install
#  FLIPPER X family. Hardens the box, wires in the Flipper toolchain,
#  and paints it in FLIPPER X colours.
#
#  Run ONCE, from the unpacked LINUX-MEGALODON folder, as your normal
#  user through sudo:      sudo ./megalodon-setup.sh
#  Options:   --lite         skip the big Kali tool metapackages (small disks)
#             --no-usbguard  do not lock down USB
#  Then reboot, log in, and run (no sudo):   ./megalodon-desktop.sh
# =====================================================================
set -Eeuo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LITE=0; USBGUARD=1
for a in "$@"; do
  case "$a" in
    --lite) LITE=1 ;;
    --no-usbguard) USBGUARD=0 ;;
    *) echo "unknown option: $a"; exit 2 ;;
  esac
done

# Your FLIPPER X phone's USB serial: lets USBGuard admit that one phone and no other MediaTek device.
FLIPPERX_SERIAL="YOUR_FLIPPERX_SERIAL"

say()  { printf '\n\033[1;32m[megalodon]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[megalodon] %s\033[0m\n' "$*"; }
die()  { printf '\033[1;31m[megalodon] %s\033[0m\n' "$*"; exit 1; }
trap 'die "failed at line $LINENO: $BASH_COMMAND  (full log: /var/log/megalodon-setup.log)"' ERR

[[ $EUID -eq 0 ]] || die "run it with sudo:  sudo ./megalodon-setup.sh"
USER_NAME="${SUDO_USER:-}"
[[ -n "$USER_NAME" && "$USER_NAME" != root ]] || die "run it through sudo from your normal user, not from a root shell"
exec > >(tee -a /var/log/megalodon-setup.log) 2>&1

. /etc/os-release
[[ "${ID:-}" == kali || "${ID_LIKE:-}" == *debian* ]] || die "this script expects Kali (or Debian); found ${PRETTY_NAME:-unknown}"
[[ -f "$HERE/assets/wallpaper.svg" ]] || die "run it from inside the LINUX-MEGALODON folder (assets/ is missing)"

# ---------------------------------------------------------------------
say "0/9  pre-flight"
if [[ $'\n'"$(lsblk -no TYPE)"$'\n' == *$'\n'crypt$'\n'* ]]; then
  say "full-disk encryption: ON (LUKS found)"
else
  warn "NO encrypted volume found. The OPSEC model assumes the disk is LUKS-encrypted."
  warn "Reinstall and pick 'Guided - use entire disk and set up encrypted LVM'. Continuing anyway in 10 s (Ctrl+C to stop)."
  sleep 10
fi
AVAIL_GB=$(df --output=avail -BG / | tail -1 | tr -dc '0-9')
say "free space on / : ${AVAIL_GB} GB"
if (( LITE == 0 && AVAIL_GB < 14 )); then
  warn "under 14 GB free: switching to --lite (core Flipper/RF tools only, no Kali metapackages)"
  LITE=1
fi

apt_have() { apt-cache show "$1" >/dev/null 2>&1; }
install_list() {
  local want=() p
  for p in "$@"; do
    if apt_have "$p"; then want+=("$p"); else warn "not in the repos, skipped: $p"; fi
  done
  if (( ${#want[@]} )); then
want=($(for p in ${want[@]}; do apt-get -s install $p &>/dev/null && echo $p; done))
    DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends "${want[@]}"
  fi
}

# ---------------------------------------------------------------------
say "1/9  system update"
apt-get update
DEBIAN_FRONTEND=noninteractive apt-get -y full-upgrade

# ---------------------------------------------------------------------
say "2/9  OPSEC base"
echo "wireshark-common wireshark-common/install-setuid boolean true" | debconf-set-selections
install_list ufw apparmor apparmor-utils apparmor-profiles apparmor-profiles-extra \
  tor torbrowser-launcher keepassxc gnupg mat2 bleachbit macchanger \
  wireguard-tools openvpn firejail rfkill network-manager systemd-resolved
if (( USBGUARD )); then install_list usbguard; fi

# ---------------------------------------------------------------------
say "3/9  Flipper family toolchain (Zero, One, FLIPPER X)"
install_list adb fastboot android-sdk-platform-tools-common dfu-util \
  python3-pip pipx python3-serial picocom minicom tio screen qflipper
if ! apt_have qflipper; then
  warn "qFlipper is not packaged here. Get the Linux AppImage from the official Flipper downloads page"
  warn "(flipper.net -> Downloads), check its SHA-256, then run it."
fi

# Official Flipper Devices udev rules: serial, DFU recovery, Wi-Fi devboard, U2F
cat > /etc/udev/rules.d/42-flipperzero.rules <<'EOF'
# Flipper Zero serial port (qFlipper, CLI, ufbt)
SUBSYSTEMS=="usb", ATTRS{idVendor}=="0483", ATTRS{idProduct}=="5740", ATTRS{manufacturer}=="Flipper Devices Inc.", TAG+="uaccess", GROUP="dialout"
# Flipper Zero DFU (firmware recovery)
SUBSYSTEMS=="usb", ATTRS{idVendor}=="0483", ATTRS{idProduct}=="df11", TAG+="uaccess", GROUP="dialout"
# Flipper Wi-Fi devboard (ESP32-S2)
SUBSYSTEMS=="usb", ATTRS{idVendor}=="303a", ATTRS{idProduct}=="40??", ATTRS{manufacturer}=="Flipper Devices Inc.", TAG+="uaccess", GROUP="dialout"
# Flipper Zero U2F security key
SUBSYSTEMS=="usb", ATTRS{idVendor}=="0483", ATTRS{idProduct}=="5741", ATTRS{manufacturer}=="Flipper Devices Inc.", ENV{ID_SECURITY_TOKEN}="1"
EOF
# FLIPPER X phone (MediaTek adb/MTP + fastbootd)
cat > /etc/udev/rules.d/43-flipperx.rules <<'EOF'
SUBSYSTEM=="usb", ATTR{idVendor}=="0e8d", MODE="0660", GROUP="plugdev", TAG+="uaccess"
SUBSYSTEM=="usb", ATTR{idVendor}=="18d1", ATTR{idProduct}=="4ee0", MODE="0660", GROUP="plugdev", TAG+="uaccess"
EOF
udevadm control --reload-rules && udevadm trigger
for g in dialout plugdev wireshark kismet; do
  if getent group "$g" >/dev/null; then usermod -aG "$g" "$USER_NAME"; fi
done

# ---------------------------------------------------------------------
say "4/9  RF / NFC / Wi-Fi / hardware tools"
CORE_TOOLS=(rtl-sdr hackrf gqrx-sdr inspectrum urh libnfc-bin mfoc pcsc-tools proxmark3
            esptool aircrack-ng wireshark bluez sigrok-cli flashrom openocd)
install_list "${CORE_TOOLS[@]}"
if (( LITE == 0 )); then
  install_list kali-tools-sdr kali-tools-rfid kali-tools-wireless kali-tools-bluetooth \
    kali-tools-hardware gnuradio kismet bettercap hcxdumptool hcxtools pulseview mfcuk
else
  warn "--lite: skipped the Kali metapackages. Add them later with: sudo apt install kali-tools-sdr kali-tools-rfid"
fi

# ---------------------------------------------------------------------
say "5/9  network OPSEC: random MACs, no hostname leak, encrypted DNS"
mkdir -p /etc/NetworkManager/conf.d /etc/systemd/resolved.conf.d
cat > /etc/NetworkManager/conf.d/90-megalodon-privacy.conf <<'EOF'
[device]
wifi.scan-rand-mac-address=yes

[connection]
# a fresh random MAC every time you join a network
wifi.cloned-mac-address=random
ethernet.cloned-mac-address=random
# never announce the hostname to the router
ipv4.dhcp-send-hostname=false
ipv6.dhcp-send-hostname=false
ipv6.ip6-privacy=2
EOF
# DNS goes only to Quad9 over TLS; DHCP-supplied ISP DNS servers are ignored.
cat > /etc/NetworkManager/conf.d/91-megalodon-dns.conf <<'EOF'
[main]
dns=none
EOF
cat > /etc/systemd/resolved.conf.d/90-megalodon.conf <<'EOF'
[Resolve]
DNS=9.9.9.9#dns.quad9.net 149.112.112.112#dns.quad9.net 2620:fe::fe#dns.quad9.net
DNSOverTLS=yes
DNSSEC=allow-downgrade
FallbackDNS=
LLMNR=no
MulticastDNS=no
EOF
systemctl enable systemd-resolved
# DNS-over-TLS needs a correct clock (certificate check) - sync it now
timedatectl set-ntp true || true
ln -sf /run/systemd/resolve/stub-resolv.conf /etc/resolv.conf
# chatty discovery services off; Bluetooth off until you ask (megalodon bt on)
for s in avahi-daemon.service avahi-daemon.socket cups-browsed.service bluetooth.service; do
  if systemctl list-unit-files "$s" >/dev/null 2>&1 && systemctl cat "$s" >/dev/null 2>&1; then
    systemctl disable --now "$s" || true
  fi
done
ufw default deny incoming
ufw default allow outgoing
ufw --force enable

# ---------------------------------------------------------------------
say "6/9  kernel + device hardening"
cat > /etc/sysctl.d/90-megalodon.conf <<'EOF'
kernel.kptr_restrict=2
kernel.dmesg_restrict=1
kernel.unprivileged_bpf_disabled=1
net.core.bpf_jit_harden=2
kernel.kexec_load_disabled=1
kernel.yama.ptrace_scope=1
kernel.sysrq=0
fs.protected_hardlinks=1
fs.protected_symlinks=1
fs.protected_fifos=2
fs.protected_regular=2
fs.suid_dumpable=0
net.ipv4.tcp_syncookies=1
net.ipv4.conf.all.rp_filter=1
net.ipv4.conf.default.rp_filter=1
net.ipv4.conf.all.accept_redirects=0
net.ipv4.conf.default.accept_redirects=0
net.ipv4.conf.all.send_redirects=0
net.ipv6.conf.all.accept_redirects=0
net.ipv6.conf.default.accept_redirects=0
net.ipv4.conf.all.accept_source_route=0
net.ipv6.conf.all.accept_source_route=0
net.ipv4.icmp_echo_ignore_broadcasts=1
net.ipv6.conf.all.use_tempaddr=2
net.ipv6.conf.default.use_tempaddr=2
EOF
sysctl --system >/dev/null
systemctl enable apparmor || true
# webcam off by default; 'megalodon cam on' brings it back
echo "blacklist uvcvideo" > /etc/modprobe.d/megalodon-cam.conf
modprobe -r uvcvideo 2>/dev/null || true

if (( USBGUARD )); then
  say "      USBGuard: allow what is plugged in now + the Flipper family; block every new device"
  usbguard generate-policy > /etc/usbguard/rules.conf
  cat >> /etc/usbguard/rules.conf <<EOF

# ---- Flipper family (serial/DFU only: a HID keyboard on these IDs is refused,
#      so a BadUSB payload can never type into this laptop by accident) ----
allow id 0483:5740 with-interface none-of { 03:*:* }
allow id 0483:df11 with-interface none-of { 03:*:* }
allow id 303a:* with-interface none-of { 03:*:* }
# Flipper Zero as a U2F 2FA key: uncomment to use it
# allow id 0483:5741
# FLIPPER X phone (this exact handset only) and its fastbootd mode
allow id 0e8d:* serial "$FLIPPERX_SERIAL" with-interface none-of { 03:*:* }
allow id 18d1:4ee0 with-interface none-of { 03:*:* }
# Flipper One: IDs not published yet. When it arrives: megalodon usb, then megalodon usb allow <id>
EOF
  chmod 600 /etc/usbguard/rules.conf
  CONF=/etc/usbguard/usbguard-daemon.conf
  sed -i -E 's/^ImplicitPolicyTarget=.*/ImplicitPolicyTarget=block/; s/^PresentDevicePolicy=.*/PresentDevicePolicy=apply-policy/; s/^InsertedDevicePolicy=.*/InsertedDevicePolicy=apply-policy/; s/^IPCAllowedGroups=.*/IPCAllowedGroups=sudo/' "$CONF"
  grep -q '^IPCAllowedGroups=' "$CONF" || echo "IPCAllowedGroups=sudo" >> "$CONF"
  systemctl enable usbguard
  systemctl restart usbguard
fi

# ---------------------------------------------------------------------
say "6b/9 TAILS LAYER: amnesia, Tor-only ghost mode, kill-cord, nothing written to disk"
install_list nftables conntrack zram-tools onionshare metadata-cleaner electrum obfs4proxy snowflake-client
mkdir -p /etc/megalodon /usr/local/lib/megalodon

# (1) No disk swap, like Tails: RAM pages never land on the disk. zram (compressed RAM swap) instead.
[[ -f /etc/megalodon/fstab.orig ]] || cp /etc/fstab /etc/megalodon/fstab.orig
sed -i -E '/^[^#].*[[:space:]]swap[[:space:]]/s/^/#megalodon-noswap# /' /etc/fstab
swapoff -a || warn "swapoff failed (swap in use) - it is disabled from the next boot"
printf 'ALGO=zstd\nPERCENT=50\nPRIORITY=100\n' > /etc/default/zramswap
systemctl enable zramswap || true
mkdir -p /etc/initramfs-tools/conf.d && echo "RESUME=none" > /etc/initramfs-tools/conf.d/resume
systemctl mask hibernate.target hybrid-sleep.target suspend-then-hibernate.target

# (2) Logs and crash dumps live in RAM only and die at power-off.
mkdir -p /etc/systemd/journald.conf.d /etc/systemd/coredump.conf.d /etc/security/limits.d
printf '[Journal]\nStorage=volatile\nRuntimeMaxUse=64M\n' > /etc/systemd/journald.conf.d/90-megalodon.conf
printf '[Coredump]\nStorage=none\nProcessSizeMax=0\n' > /etc/systemd/coredump.conf.d/90-megalodon.conf
echo "* hard core 0" > /etc/security/limits.d/90-megalodon.conf
rm -rf /var/log/journal
systemctl restart systemd-journald

# (3) Ghost mode = Tails' network model: every packet goes through Tor or it dies.
#     Tor is OFF at boot; 'megalodon ghost on' (or logging in as the ghost user) turns it on.
if ! grep -q 'MEGALODON-GHOST' /etc/tor/torrc; then
cat >> /etc/tor/torrc <<'EOF'

# MEGALODON-GHOST (transparent Tor for ghost mode)
VirtualAddrNetworkIPv4 10.192.0.0/10
AutomapHostsOnResolve 1
TransPort 127.0.0.1:9040 IsolateClientAddr IsolateDestAddr
DNSPort 127.0.0.1:5353
SocksPort 127.0.0.1:9050
EOF
fi
systemctl disable --now tor || true
cat > /etc/megalodon/ghost.nft <<'EOF'
table inet megalodon_ghost
delete table inet megalodon_ghost
table inet megalodon_ghost {
  chain nat_out {
    type nat hook output priority -100; policy accept;
    meta skuid "debian-tor" return
    ip daddr 127.0.0.0/8 return
    meta nfproto ipv4 udp dport 53 redirect to :5353
    meta nfproto ipv4 meta l4proto tcp redirect to :9040
  }
  chain filter_out {
    type filter hook output priority 0; policy drop;
    oifname "lo" accept
    ip daddr 127.0.0.0/8 accept
    ip6 daddr ::1 accept
    meta skuid "debian-tor" accept
    udp sport 68 udp dport 67 accept
  }
}
EOF

# (4) The ghost user = a Tails session on this laptop: home lives in RAM, wiped at logout and
#     power-off, network forced through Tor for as long as it is logged in. No sudo, no password
#     (the disk passphrase at boot already gates the machine).
GHOST_SHELL="$(command -v zsh || echo /bin/bash)"
id ghost >/dev/null 2>&1 || useradd -M -d /home/ghost -s "$GHOST_SHELL" -c "ghost - amnesic Tor session" ghost
passwd -l ghost >/dev/null
getent group nopasswdlogin >/dev/null || groupadd -r nopasswdlogin
usermod -aG nopasswdlogin ghost
if [[ -f /etc/pam.d/lightdm ]] && ! grep -q nopasswdlogin /etc/pam.d/lightdm; then
  sed -i '1a auth    sufficient      pam_succeed_if.so user ingroup nopasswdlogin' /etc/pam.d/lightdm
fi
GUID=$(id -u ghost); GGID=$(id -g ghost)
mkdir -p /home/ghost
grep -q 'megalodon-ghost' /etc/fstab || \
  echo "tmpfs /home/ghost tmpfs rw,nosuid,nodev,size=1G,mode=0700,uid=$GUID,gid=$GGID 0 0 # megalodon-ghost" >> /etc/fstab

SK=/etc/megalodon/ghost-skel
rm -rf "$SK"; mkdir -p "$SK"; cp -a /etc/skel/. "$SK/"
mkdir -p "$SK/.config/qterminal.org" "$SK/.config/fastfetch" "$SK/.config/xfce4/xfconf/xfce-perchannel-xml"
printf '[General]\ncolorScheme=Megalodon\n' > "$SK/.config/qterminal.org/qterminal.ini"
cat > "$SK/.config/fastfetch/config.jsonc" <<'EOF'
{ "logo": { "source": "/usr/share/megalodon/ascii.txt", "color": { "1": "green", "2": "bright_green", "3": "yellow" } },
  "modules": ["title", "separator", "os", "kernel", "uptime", "memory"] }
EOF
{
  echo '<?xml version="1.0" encoding="UTF-8"?>'
  echo '<channel name="xfce4-desktop" version="1.0"><property name="backdrop" type="empty"><property name="screen0" type="empty">'
  for m in monitoreDP-1 monitoreDP1 monitor0; do
    echo "<property name=\"$m\" type=\"empty\"><property name=\"workspace0\" type=\"empty\">"
    echo '<property name="last-image" type="string" value="/usr/share/backgrounds/megalodon/wallpaper.png"/>'
    echo '<property name="image-style" type="int" value="5"/></property></property>'
  done
  echo '</property></property></channel>'
} > "$SK/.config/xfce4/xfconf/xfce-perchannel-xml/xfce4-desktop.xml"
for rcf in .profile .zshrc .bashrc; do
  cat >> "$SK/$rcf" <<'EOF'

# MEGALODON ghost session
umask 077
export TOR_SKIP_LAUNCH=1 TOR_SOCKS_HOST=127.0.0.1 TOR_SOCKS_PORT=9050
unset HISTFILE
case $- in *i*)
  command -v fastfetch >/dev/null && fastfetch
  printf '\n  \033[1;32mGHOST SESSION\033[0m  every packet goes through Tor; nothing here survives logout.\n\n' ;;
esac
EOF
done

cat > /usr/local/lib/megalodon/ghost-session <<'EOF'
#!/bin/bash
# start/stop = ghost user logs in/out; seed = fill the empty RAM home at boot
seed() {
  find /home/ghost -mindepth 1 -delete 2>/dev/null
  cp -a /etc/megalodon/ghost-skel/. /home/ghost/
  chown -R ghost:ghost /home/ghost && chmod 700 /home/ghost
}
case "$1" in
  start) /usr/local/bin/megalodon ghost on ;;
  stop)  pkill -KILL -u ghost 2>/dev/null; seed; /usr/local/bin/megalodon ghost off ;;
  seed)  seed ;;
esac
EOF
chmod 755 /usr/local/lib/megalodon/ghost-session
cat > /etc/systemd/system/megalodon-ghost-home.service <<'EOF'
[Unit]
Description=Megalodon: fill the ghost user's RAM home
RequiresMountsFor=/home/ghost
Before=display-manager.service

[Service]
Type=oneshot
ExecStart=/usr/local/lib/megalodon/ghost-session seed

[Install]
WantedBy=multi-user.target
EOF
cat > /etc/systemd/system/megalodon-ghost-session.service <<EOF
[Unit]
Description=Megalodon: Tor-only network while the ghost user is logged in
Before=user@$GUID.service
PartOf=user@$GUID.service

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/usr/local/lib/megalodon/ghost-session start
ExecStop=/usr/local/lib/megalodon/ghost-session stop
EOF
mkdir -p "/etc/systemd/system/user@$GUID.service.wants"
ln -sf ../megalodon-ghost-session.service "/etc/systemd/system/user@$GUID.service.wants/megalodon-ghost-session.service"
systemctl daemon-reload
mount /home/ghost 2>/dev/null || true
systemctl enable megalodon-ghost-home.service
/usr/local/lib/megalodon/ghost-session seed || true

# (5) Panic button without a password prompt (kill-cord and keyboard shortcut use it)
echo 'ALL ALL=(root) NOPASSWD: /usr/local/bin/megalodon panic' > /etc/sudoers.d/megalodon-panic
chmod 440 /etc/sudoers.d/megalodon-panic
visudo -cf /etc/sudoers.d/megalodon-panic >/dev/null || { rm -f /etc/sudoers.d/megalodon-panic; warn "panic sudoers rule rejected - removed"; }

# ---------------------------------------------------------------------
say "7/9  branding: Linux Megalodon"
install_list librsvg2-bin plymouth plymouth-label fonts-dejavu-core fastfetch qterminal
mkdir -p /usr/share/megalodon /usr/share/backgrounds/megalodon /etc/megalodon
cp "$HERE"/assets/*.svg "$HERE/assets/ascii.txt" /usr/share/megalodon/
rsvg-convert -w 1920 -h 1080 "$HERE/assets/wallpaper.svg" -o /usr/share/backgrounds/megalodon/wallpaper.png
rsvg-convert -w 256 -h 256 "$HERE/assets/logo.svg" -o /usr/share/megalodon/logo.png
for d in /usr/share/qtermwidget5/color-schemes /usr/share/qtermwidget6/color-schemes; do
  if [[ -d "$d" ]]; then cp "$HERE/assets/Megalodon.colorscheme" "$d/"; fi
done

hostnamectl set-hostname megalodon
if grep -q '^127\.0\.1\.1' /etc/hosts; then
  sed -i -E 's/^127\.0\.1\.1.*/127.0.1.1\tmegalodon/' /etc/hosts
else
  printf '127.0.1.1\tmegalodon\n' >> /etc/hosts
fi
printf '\n  LINUX MEGALODON  \\l\n\n' > /etc/issue
printf '\n  LINUX MEGALODON  ::  FLIPPER X family  ::  nothing leaks\n  megalodon status   - radios, firewall, USB lock, DNS, ghost mode, kill-cord\n\n' > /etc/motd

# login screen
GREETER=/etc/lightdm/lightdm-gtk-greeter.conf
if [[ -f "$GREETER" ]]; then
  [[ -f /etc/megalodon/lightdm-gtk-greeter.conf.orig ]] || cp "$GREETER" /etc/megalodon/lightdm-gtk-greeter.conf.orig
  if grep -q '^background=' "$GREETER"; then
    sed -i 's#^background=.*#background=/usr/share/backgrounds/megalodon/wallpaper.png#' "$GREETER"
  else
    sed -i '/^\[greeter\]/a background=/usr/share/backgrounds/megalodon/wallpaper.png' "$GREETER"
  fi
fi

# boot splash (keeps the old theme name so 'megalodon unbrand' can restore it)
T=/usr/share/plymouth/themes/megalodon
mkdir -p "$T"
cp "$HERE/plymouth/megalodon.plymouth" "$HERE/plymouth/megalodon.script" "$T/"
rsvg-convert -w 220 -h 220 "$HERE/assets/logo.svg" -o "$T/logo.png"
printf '<svg xmlns="http://www.w3.org/2000/svg" width="320" height="3"><rect width="320" height="3" fill="#2bd48a"/></svg>' > /tmp/megalodon-bar.svg
rsvg-convert /tmp/megalodon-bar.svg -o "$T/bar.png"
rm -f /tmp/megalodon-bar.svg
if [[ ! -f /etc/megalodon/plymouth.prev ]]; then
  plymouth-set-default-theme > /etc/megalodon/plymouth.prev 2>/dev/null || true
fi
plymouth-set-default-theme -R megalodon

# ---------------------------------------------------------------------
say "8/9  GRUB theme"
G=/boot/grub/themes/megalodon
mkdir -p "$G"
cp "$HERE/grub/theme.txt" "$G/"
rsvg-convert -w 1920 -h 1080 "$HERE/assets/grub-bg.svg" -o "$G/background.png"
grub-mkfont -s 16 -o "$G/dejavu_mono_16.pf2" /usr/share/fonts/truetype/dejavu/DejaVuSansMono.ttf
grub-mkfont -s 16 -o "$G/dejavu_mono_bold_16.pf2" /usr/share/fonts/truetype/dejavu/DejaVuSansMono-Bold.ttf
# 'zz-' so it is read after Kali's own kali-themes.cfg and wins
# Tails' memory hardening: freed RAM is zeroed, allocator shuffled, no slab merging
HARDEN="init_on_alloc=1 init_on_free=1 page_alloc.shuffle=1 slab_nomerge randomize_kstack_offset=on vsyscall=none debugfs=off"
grep -qs 'splash' /etc/default/grub || HARDEN="$HARDEN splash"
cat > /etc/default/grub.d/zz-megalodon.cfg <<EOF
GRUB_THEME=/boot/grub/themes/megalodon/theme.txt
GRUB_GFXMODE=auto
GRUB_CMDLINE_LINUX_DEFAULT="\$GRUB_CMDLINE_LINUX_DEFAULT $HARDEN"
EOF
update-grub

# ---------------------------------------------------------------------
say "9/9  megalodon command"
install -m 0755 "$HERE/megalodon" /usr/local/bin/megalodon

trap - ERR
say "DONE.  Reboot now:  sudo reboot"
say "After the reboot, log in and run (no sudo):  ./megalodon-desktop.sh"
