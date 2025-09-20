#!/bin/bash

# Настройка доменного контроллера Samba
echo "Starting Samba Domain Controller setup..."

# Обновление системы и установка Samba DC
apt-get update
apt-get install task-samba-dc -y

# Настройка разрешения имен
cat > /etc/resolv.conf << EOF
nameserver 192.168.1.2
EOF

# Настройка hostname и hosts
hostnamectl set-hostname br-srv.au-team.irpo
cat >> /etc/hosts << EOF
192.168.4.2    br-srv.au-team.irpo
EOF

# Provision domain
samba-tool domain provision \
    --realm=AU-TEAM.IRPO \
    --domain=AU-TEAM \
    --server-role=dc \
    --dns-backend=SAMBA_INTERNAL \
    --adminpass=P@ssw0rd \
    --use-rfc2307 \
    --host-ip=192.168.4.2

# Настройка Kerberos
mv /var/lib/samba/private/krb5.conf /etc/krb5.conf

# Включение служб
systemctl enable samba
systemctl start samba

# Добавление в автозагрузку
(crontab -l 2>/dev/null; echo "@reboot /bin/systemctl restart network") | crontab -
(crontab -l 2>/dev/null; echo "@reboot /bin/systemctl restart samba") | crontab -

# Создание пользователей
users=("user1.hq" "user2.hq" "user3.hq" "user4.hq" "user5.hq")
for user in "${users[@]}"; do
    samba-tool user add $user P@ssw0rd
done

# Создание группы и добавление пользователей
samba-tool group add hq
samba-tool group addmembers hq user1.hq,user2.hq,user3.hq,user4.hq,user5.hq

echo "Samba Domain Controller setup completed!"
echo "Please reboot the system with: reboot"
