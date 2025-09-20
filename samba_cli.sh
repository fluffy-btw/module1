#!/bin/bash
# Настройка клиента для работы с доменом AD

# Установка необходимых пакетов
apt-get update
apt-get install -y realmd sssd sssd-tools libnss-sss libpam-sss adcli samba-common-bin

# Присоединение к домену
echo "P@ssw0rd" | realm join --user=administrator AU-TEAM.IRPO

# Настройка SSSD
cat > /etc/sssd/sssd.conf << EOF
[sssd]
domains = AU-TEAM.IRPO
services = nss, pam, sudo

[domain/AU-TEAM.IRPO]
id_provider = ad
access_provider = ad
sudo_provider = ad
ad_domain = AU-TEAM.IRPO
krb5_realm = AU-TEAM.IRPO
realmd_tags = manages-system joined-with-adcli
cache_credentials = True
ldap_id_mapping = True
use_fully_qualified_names = False
fallback_homedir = /home/%u
default_shell = /bin/bash
ad_gpo_map_permit = +sudoers
EOF

chmod 600 /etc/sssd/sssd.conf

# Настройка sudo для работы с AD
cat > /etc/nsswitch.conf << EOF
passwd:         compat systemd sss
group:          compat systemd sss
shadow:         compat sss
gshadow:        files sss
sudoers:        files sss
EOF

# Перезапуск служб
systemctl restart sssd
systemctl enable sssd

# Проверка присоединения к домену
realm list