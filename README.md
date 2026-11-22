# LINUX MEGALODON: Chromebook rebuild

Kali Linux on full-disk encryption, with a Tails-grade privacy layer, the Flipper family wired in, and painted in FLIPPER X colours.
Target: **Acer Chromebook 512 (CB512, model N18Q7)**.

## Your one USB stick

One stick carries everything. A suggested layout:

| # | Partition | What it is |
|---|---|---|
| 1 | TAILS (FAT32, 8 GB) | a bootable Tails (optional, for zero-trace sessions) |
| 2 | your data | anything else you keep on the stick |
| 3 | **MEGALODON (FAT32, 10 GB)** | the Kali installer, this kit (as `LINUX-MEGALODON/`), and space for the firmware backup |

Verify the Kali image before copying it: check that its `SHA256SUMS` file is signed by Kali's archive key `827C8569F2518CC677FECA1AED65462EC8D5E4C5`, and that the ISO's SHA-256 matches the entry in it. Keep no cable between your PC and the Chromebook: the stick is the only bridge.

---

## Phase 0: confirm the board (1 min)

Hold **Esc + Refresh + Power**. The board name is printed at the bottom of the recovery screen.

* **SPARKY** (Acer 512 C851, most likely for N18Q7): supported. Write-protect is turned off by **unplugging the battery** (below).
* **MAGLET** (Acer 512 C852): also supported, but write-protect needs a **SuzyQ cable or a jumper** (see the MrChromebox docs). The battery method below will not work.

Power it off again.

## Phase 1: turn off firmware write-protect (SPARKY, battery method)

1. Unplug the charger. Remove the bottom-cover screws and lift the cover off gently.
2. **Unplug the battery connector** from the board.
3. Close it up loosely, plug in **only the charger**, and power on. Running on the charger with no battery disables write-protect.
4. Keep it on the charger with the battery disconnected until Phase 2 is finished.

## Phase 2: flash the UEFI firmware (this is the "rewire")

1. **Developer mode:** at the recovery screen (Esc + Refresh + Power), press **Ctrl+D**, then confirm. This wipes the Chromebook, as you intended. On the next screen press **Ctrl+D** again.
2. Join Wi-Fi on the welcome screen. **Do not sign in.** Press **Ctrl+Alt+→**, then log in as `chronos` (no password).
3. Run:
   ```
   cd; curl -LOf https://mrchromebox.tech/firmware-util.sh && sudo bash firmware-util.sh
   ```
4. Plug in the stick. Choose **Install/Update UEFI (Full ROM) Firmware**.
5. When it offers to **back up the stock firmware, say YES** and save it to the stick. If it asks which partition, pick **MEGALODON**.
   This is the un-brick file, the only copy of the original firmware. Copy it somewhere safe off the stick (and keep a second copy).
6. When it finishes, power off. Plug the battery back in and close the case.

## Phase 3: install Kali, encrypted

1. Power on with the stick in. Press **Esc** at the logo for the boot menu.
2. **Pick the MEGALODON partition, not Tails.** The stick holds two bootable systems:
   * If the USB entry starts Tails, go back and choose **Boot Maintenance Manager → Boot From File**. Pick the entry whose label says **MEGALODON** (otherwise the 4th one on the USB), then `EFI` → `boot` → `bootx64.efi`.
   * You'll see the Kali menu with the Megalodon-family boot screen to come.
3. Choose **Graphical install**:
   * **User name:** not your real name.
   * **Partitioning:** **Guided - use entire disk and set up encrypted LVM.** Choose the **internal eMMC**, never the USB stick. Let it overwrite the disk with random data.
   * **Encryption passphrase:** 6+ random words. This is the whole wall.
   * **Software:** Xfce plus the default tools. The 512 has a 32 or 64 GB disk, so on 32 GB untick the large "everything" sets.
   * **GRUB:** install it to the **internal disk** (usually `/dev/mmcblk0`), not the stick.
4. Reboot, remove the stick at the restart, unlock with the passphrase, and log in.

## Phase 4: become Megalodon

Plug the stick back in. MEGALODON mounts by itself. Then run:

```
cp -r /media/$USER/MEGALODON/LINUX-MEGALODON ~/ && cd ~/LINUX-MEGALODON
sudo bash megalodon-setup.sh          # it switches itself to --lite if the disk is small
sudo reboot
cd ~/LINUX-MEGALODON && bash megalodon-desktop.sh
```

Log out and back in once so the device groups apply, then run `megalodon status`.

**Gemini Lake audio:** speakers on Gemini Lake Chromebooks need the community audio fix, the `chromebook-linux-audio` script (WeirdTreeThing on GitHub). Read it before running it.

## What the setup builds

**Baseline OPSEC**
* Inbound firewall (deny all).
* A random MAC address on every network, and the hostname is never announced.
* DNS goes only to Quad9 over TLS. No mDNS or LLMNR chatter.
* Bluetooth and webcam are off by default.
* Kernel hardening and AppArmor.
* USBGuard: every new USB device is blocked. The Flipper family is admitted with no keyboard interface, so a BadUSB payload can't type into this laptop.

**Tails layer** (Tails is Debian; so is Kali, so its ideas carry over)

| Tails feature | Megalodon version |
|---|---|
| Amnesic session | Log in as **`ghost`**. Its home lives in RAM and is **wiped at logout and power-off**. No sudo, no history. |
| All traffic forced through Tor | **Ghost mode.** Turns on automatically for `ghost`, or by hand with `megalodon ghost on`. A firewall sends every packet through Tor or drops it, so if Tor dies, nothing leaks. `megalodon ghost check` asks the Tor Project to confirm. |
| Emergency shutdown when the stick is pulled | **Kill-cord.** `megalodon killcord arm` lets you pick any USB device (a Flipper Zero on a lanyard works). Pulling it powers the laptop off instantly, and the disk locks behind LUKS. |
| Panic button | `megalodon panic`, or **Ctrl+Alt+Backspace**: powers off now, no password. |
| No swap on disk | Disk swap is off and RAM is never written to storage. Compressed RAM swap (zram) replaces it. Hibernate is disabled. |
| RAM wiped when freed | Tails' kernel options: freed memory is zeroed, the allocator is shuffled, slab merging is off. |
| Logs in RAM only | The system journal and crash dumps never touch the disk. |
| Tails apps | Tor Browser, OnionShare, KeePassXC, MAT2 and Metadata Cleaner, Electrum, GnuPG, plus obfs4 and Snowflake bridges. |

**Flipper:** official udev rules, qFlipper, the `ufbt` SDK, adb and fastboot for FLIPPER X (locked to your handset's serial), DFU recovery, and the ESP32 Wi-Fi devboard.

**Tools:** SDR, NFC/RFID, Wi-Fi, BLE, logic analysers, flashrom and OpenOCD.

**Branding:** shark boot splash (with a visible disk-unlock prompt), GRUB theme, login screen, wallpaper, terminal colours, shark menu button and terminal greeting. Hostname: `megalodon`.

## Phase 5: Flipper devices

| Device | Plug in, then |
|---|---|
| Flipper Zero | `megalodon flipper`, then open qFlipper. CLI: `tio /dev/serial/by-id/*Flipper*` |
| Flipper Wi-Fi devboard | `megalodon flipper`, then flash with `esptool` |
| FLIPPER X phone | `adb devices`. Updates use the install-session flow (`pm install-create` / `install-write` / `install-commit`) |
| Flipper One | its USB IDs aren't published yet. Plug it in, run `megalodon usb`, then `megalodon usb allow <number>` |
| Zero as a 2FA key | uncomment the `0483:5741` line in `/etc/usbguard/rules.conf`, then `sudo systemctl restart usbguard` |

## The `megalodon` command

`status` · `radios off|on` · `bt on|off` · `cam on|off` · `dns strict|portal` · `usb` · `usb allow <n>` · `flipper` · `ghost on|off|check` · `killcord arm|disarm` · `panic` · `unbrand`

## OPSEC: the parts software can't do

* **Shut down, don't sleep,** when you walk away. A sleeping laptop holds the disk key in RAM.
* **Ghost mode vs a real Tails boot:** the ghost session runs on the installed system, which knows your Wi-Fi networks and hardware. For **zero trace on the laptop at all**, boot **Tails from partition 1 of this same stick**. Ghost is for convenience; Tails is for when it really matters.
* **VPN in normal mode:** Mullvad (account number, no email, cash accepted). Install their official .deb and verify the key.
* **Honest limits:**
  * This firmware has no Secure Boot, so `/boot` is not encrypted, and physical tampering is possible. Keep the laptop with you.
  * The microphone can't be reliably killed in software.
  * Ghost mode blocks hotel and cafe sign-in pages: sign in first, then turn ghost on.
  * Kali is a rolling release: `sudo apt update && sudo apt full-upgrade` weekly.
* **The law:** the RF, NFC and Wi-Fi tools are for your own gear and networks, or ones you have written permission to test.

## If something goes wrong

* **The Kali installer says it can't find the installation media:** the fallback is to back up the stick's files to the PC, write Kali to the whole stick, then rebuild the stick layout afterwards.
* **No internet after the reboot** (sign-in page or a wrong clock): `megalodon dns portal`, sign in, then `megalodon dns strict`.
* **Ghost mode on but nothing loads:** Tor is still connecting (give it 30-60 s), or the network blocks Tor. In that case, add a bridge in `/etc/tor/torrc`.
* **A USB device does nothing:** `megalodon usb`, then `megalodon usb allow <number>`.
* **No unlock prompt on the boot splash:** type the passphrase blind and press Enter, then run `megalodon unbrand`.
* **The Chromebook won't boot after Phase 2:** the stock-firmware backup you saved in Phase 2, together with MrChromebox's recovery guide, restores it.
