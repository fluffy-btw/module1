#!/bin/bash

# Настройка NFS клиента
echo "Configuring NFS client..."

# Устанавливаем NFS клиент
apt-get update
apt-get install nfs-common -y

# Создаем точку монтирования
mkdir -p /mnt/nfs

# Добавляем в fstab
echo "192.168.1.2:/raid5/nfs /mnt/nfs nfs intr,soft,_netdev,x-systemd.automount 0 0" >> /etc/fstab

# Монтируем
mount -a

# Проверяем подключение
if mountpoint -q /mnt/nfs; then
    echo "NFS mounted successfully"
    # Создаем тестовый файл
    touch /mnt/nfs/test_file
else
    echo "NFS mount failed!"
    exit 1
fi

echo "NFS client configuration completed!"