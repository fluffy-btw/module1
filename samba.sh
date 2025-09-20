#!/bin/bash

# Скрипт автоматической настройки Samba Domain Controller
echo "Starting Samba Domain Controller automated setup..."

# Переменные
DOMAIN="AU-TEAM"
REALM="AU-TEAM.IRPO"
ADMIN_PASS="P@ssw0rd"
HOST_IP="192.168.4.2"
HOST_NAME="br-srv.au-team.irpo"

# Обновление системы и установка Samba DC
echo "Updating system and installing Samba DC..."
apt-get update
apt-get install task-samba-dc -y

# Настройка разрешения имен
echo "Configuring DNS resolution..."
cat > /etc/resolv.conf << EOF
nameserver 192.168.1.2
EOF

# Настройка hostname и hosts
echo "Configuring hostname and hosts file..."
hostnamectl set-hostname $HOST_NAME
cat >> /etc/hosts << EOF
$HOST_IP   $HOST_NAME
EOF

# Удаление старой конфигурации Samba
echo "Removing old Samba configuration..."
rm -f /etc/samba/smb.conf

# Provision domain
echo "Provisioning Samba domain..."
samba-tool domain provision \
    --realm=$REALM \
    --domain=$DOMAIN \
    --server-role=dc \
    --dns-backend=SAMBA_INTERNAL \
    --adminpass=$ADMIN_PASS \
    --use-rfc2307 \
    --host-ip=$HOST_IP

# Настройка Kerberos
echo "Configuring Kerberos..."
cp /var/lib/samba/private/krb5.conf /etc/krb5.conf

# Включение и запуск служб
echo "Enabling and starting Samba services..."
systemctl enable samba
systemctl start samba

# Добавление в автозагрузку
echo "Adding to startup..."
(crontab -l 2>/dev/null; echo "@reboot /bin/systemctl restart network") | crontab -
(crontab -l 2>/dev/null; echo "@reboot /bin/systemctl restart samba") | crontab -

# Создание пользователей
echo "Creating users..."
users=("user1.hq" "user2.hq" "user3.hq" "user4.hq" "user5.hq")
for user in "${users[@]}"; do
    samba-tool user add $user $ADMIN_PASS
done

# Создание группы и добавление пользователей
echo "Creating group and adding users..."
samba-tool group add hq
samba-tool group addmembers hq user1.hq,user2.hq,user3.hq,user4.hq,user5.hq

# Установка дополнительных компонентов
echo "Installing additional components..."
apt-get install sudo-samba-schema -y

# Применение sudo схемы
echo "Applying sudo schema..."
echo -e "yes\nAdministrator\n$ADMIN_PASS\nok" | sudo-schema-apply

# Создание правила sudo
echo "Creating sudo rule..."
cat > /tmp/sudo_rule.txt << EOF
Имя правила: prava_hq
sudoHost: ALL
sudoCommand: /bin/cat
sudoUser: %hq
EOF

create-sudo-rule < /tmp/sudo_rule.txt
rm /tmp/sudo_rule.txt

# Импорт пользователей из CSV
echo "Importing users from CSV..."
curl -L https://bit.ly/3C1nEYz > /root/users.zip
unzip -o /root/users.zip -d /root/
mv /root/Users.csv /opt/Users.csv

# Создание скрипта импорта
cat > /root/import_users.sh << 'EOF'
#!/bin/bash
csv_file="/opt/Users.csv"
while IFS=";" read -r firstName lastName role phone ou street zip city country password; do
    if [ "$firstName" == "First Name" ]; then
        continue
    fi
    username="${firstName,,}.${lastName,,}"
    samba-tool user add "$username" 123qweR%
done < "$csv_file"
EOF

chmod +x /root/import_users.sh
/root/import_users.sh

echo "Samba Domain Controller setup completed!"
echo "Please reboot the system with: reboot"
echo "After reboot, verify domain with: samba-tool domain info $HOST_IP"
