#!/bin/bash

# CyberPatriot Linux Hardener Script
# Run as: sudo ./secure_linux.sh
# Logs to /var/log/cyberpatriot_harden.log
# WARNING: Test on VM first!

LOGFILE="/var/log/cyberpatriot_harden.log"
exec > >(tee -a "$LOGFILE") 2>&1

echo "$(date): Starting CyberPatriot hardening..."

check_status() {
    if [ $? -eq 0 ]; then
        echo "Success: $1"
    else
        echo "Failed: $1"
    fi
}

# 1. UPDATE SYSTEM
echo "=== 1. Updating system ==="
apt update && apt upgrade -y && apt dist-upgrade -y && apt autoremove -y && apt autoclean -y
check_status "System update"

apt install -y unattended-upgrades ufw libpam-cracklib auditd chkrootkit rkhunter clamav clamav-daemon fail2ban lynis
dpkg-reconfigure --priority=low unattended-upgrades

# 2. FIREWALL
echo "=== 2. Configuring Firewall (UFW) ==="
ufw default deny incoming
ufw default allow outgoing
ufw allow ssh
ufw --force enable
check_status "UFW enable"

# 3. USER MANAGEMENT
echo "=== 3. User Management & Password Policies ==="
passwd -l root
check_status "Root lock"

sed -i 's/PASS_MAX_DAYS.*/PASS_MAX_DAYS   90/' /etc/login.defs
sed -i 's/PASS_MIN_DAYS.*/PASS_MIN_DAYS   7/' /etc/login.defs
sed -i 's/PASS_WARN_AGE.*/PASS_WARN_AGE   14/' /etc/login.defs

echo 'auth required pam_tally2.so deny=5 onerr=fail unlock_time=1800' >> /etc/pam.d/common-auth
sed -i 's/\(pam_unix.so.*\)$/\1 remember=5 minlen=8/' /etc/pam.d/common-password
sed -i 's/\(pam_cracklib.so.*\)$/\1 ucredit=-1 lcredit=-1 dcredit=-1 ocredit=-1/' /etc/pam.d/common-password

# 4. REMOVE GAMES & HACKING TOOLS
echo "=== 4. Removing Unnecessary Packages ==="
apt purge '~ngames' -y
apt purge -y telnet vsftpd samba apache2 nginx lighttpd hydra john nikto nmap wireshark netcat-traditional
check_status "Package purge"

# 5. SSH HARDENING
if [ -f /etc/ssh/sshd_config ]; then
    sed -i 's/#*PermitRootLogin.*/PermitRootLogin no/' /etc/ssh/sshd_config
    sed -i 's/#*PasswordAuthentication.*/PasswordAuthentication yes/' /etc/ssh/sshd_config
    sed -i 's/#*ClientAliveInterval.*/ClientAliveInterval 300/' /etc/ssh/sshd_config
    sed -i 's/#*ClientAliveCountMax.*/ClientAliveCountMax 0/' /etc/ssh/sshd_config
    systemctl restart ssh
    check_status "SSH hardening"
fi

# 6. AUDITING & SCANS
echo "=== 6. Auditing & Malware Scans ==="
auditctl -e 1
rkhunter --update && rkhunter --propupd && rkhunter --check
chkrootkit -q
freshclam && clamscan -r --bell -i /
systemctl enable fail2ban && systemctl start fail2ban
lynis audit system > /var/log/lynis-report.txt

# 7. KERNEL HARDENING
echo "=== 7. Kernel Hardening ==="
cat >> /etc/sysctl.conf << SYSCTL
net.ipv4.conf.all.rp_filter = 1
net.ipv4.conf.default.rp_filter = 1
net.ipv4.icmp_echo_ignore_broadcasts = 1
net.ipv4.conf.all.accept_redirects = 0
net.ipv4.conf.default.accept_redirects = 0
net.ipv4.conf.all.send_redirects = 0
net.ipv4.conf.default.send_redirects = 0
net.ipv4.tcp_syncookies = 1
net.ipv4.ip_forward = 0
SYSCTL
sysctl -p
check_status "Sysctl"

# 8. CLEANUP
echo "=== 8. Cleanup ==="
find /home -type f \( -iname "*.mp3" -o -iname "*.mp4" -o -iname "*.jpg" -o -iname "*.png" -o -iname "*.zip" -o -iname "*.tar.gz" \) -delete
chmod -R 750 /home/* 2>/dev/null

echo "$(date): Hardening complete! Log: $LOGFILE"
echo "Reboot recommended: sudo reboot"
