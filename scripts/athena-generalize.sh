#!/bin/bash
# Turn the running SD-card system back into a generic first-boot image for
# cloning onto other boxes, then power off. Hardware fixes (bootloader, DTB,
# AC300 clock, Seekwave driver, per-board MAC/hostname) are kept; everything
# that identifies this box or its owner is removed.
#
# Run on the box, booted from the SD card, as root:
#   athena-generalize.sh '<root password hash from the original image>'
set -euo pipefail

ROOT_HASH=${1:?usage: $0 '<original root password hash>'}

case "$(findmnt -no SOURCE /)" in
/dev/mmcblk0*) ;;
*) echo "refusing: / is not on the SD card" >&2; exit 1 ;;
esac

echo "== users and logins"
# Accounts created by the first-login wizard (it recreates them)
for u in $(awk -F: '$3 >= 1000 && $3 < 65000 { print $1 }' /etc/passwd); do
	userdel -r -f "$u" 2>/dev/null || userdel -f "$u"
done
usermod -p "$ROOT_HASH" root
touch /root/.not_logged_in_yet
rm -rf /root/.ssh /root/.bash_history /root/.cache /root/.local/share/nano \
	/root/.lesshst /root/.wget-hsts
rm -rf /root/swt-build /root/mdio.py /root/ac300clk.py /root/netplan-backup \
	/root/sv-build /root/armbianEnv.txt.before-cpufreq /root/swt6621s-modules-load.conf.disabled
chown -R root:root /root/athena

echo "== network credentials"
rm -f /etc/netplan/*.yaml
cat > /etc/netplan/00-default-use-network-manager.yaml <<'EOF'
# Added by Armbian
#
# Reference: https://netplan.readthedocs.io/en/stable/netplan-yaml/
#
# Let NetworkManager manage all devices on this system.
# Any device will come up with DHCP, once carrier is detected.
# This is basically Netplan passing control over to NetworkManager at boot time.

network:
  version: 2
  renderer: NetworkManager
EOF
chmod 600 /etc/netplan/00-default-use-network-manager.yaml
rm -f /etc/NetworkManager/system-connections/* /run/NetworkManager/system-connections/*
rm -f /var/lib/NetworkManager/*.lease /var/lib/NetworkManager/secret_key \
	/var/lib/NetworkManager/seen-bssids /var/lib/NetworkManager/timestamps

echo "== machine identity"
rm -f /etc/ssh/ssh_host_*            # sshd-keygen.service recreates them
: > /etc/machine-id                  # systemd generates a new one on boot
rm -f /var/lib/dbus/machine-id
ln -s /etc/machine-id /var/lib/dbus/machine-id
rm -f /etc/athena-identity.done      # athena-identity.service sets a new hostname
rm -f /etc/modprobe.d/athena-wifi-mac.conf   # and rewrites the Wi-Fi MAC
echo armbian > /etc/hostname
sed -i 's/^127.0.1.1.*/127.0.1.1\tarmbian/' /etc/hosts

echo "== first-boot services"
systemctl enable armbian-resize-filesystem.service armbian-firstrun.service

echo "== logs and caches"
apt-get clean
journalctl --rotate >/dev/null 2>&1 || true
journalctl --vacuum-time=1s >/dev/null 2>&1 || true
find /var/log /var/log.hdd -type f \( -name '*.gz' -o -name '*.[0-9]' \) -delete 2>/dev/null || true
find /var/log /var/log.hdd -type f -exec truncate -s 0 {} + 2>/dev/null || true
rm -rf /var/tmp/* /tmp/* 2>/dev/null || true

sync
echo "== generalized; powering off"
systemctl poweroff
