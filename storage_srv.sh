#!/bin/bash

# Конфигурация файлового хранилища с RAID 5 и NFS
echo "Starting storage configuration..."

# Проверяем наличие дисков
disks=("/dev/sdb" "/dev/sdc" "/dev/sdd")
for disk in "${disks[@]}"; do
    if [ ! -b "$disk" ]; then
        echo "Error: Disk $disk not found!"
        exit 1
    fi
done

# Создаем RAID 5
echo "Creating RAID 5 array..."
mdadm --create /dev/md0 --level=5 --raid-devices=3 ${disks[@]}
if [ $? -ne 0 ]; then
    echo "Error creating RAID array!"
    exit 1
fi

# Ждем завершения создания RAID
echo "Waiting for RAID synchronization..."
while grep -q resync /proc/mdstat; do
    sleep 5
done

# Сохраняем конфигурацию RAID
mdadm --detail --scan >> /etc/mdadm/mdadm.conf
update-initramfs -u

# Создаем раздел на RAID
echo "Creating partition on RAID..."
echo -e "n\np\n1\n\n\nw" | fdisk /dev/md0

# Форматируем раздел в ext4
echo "Formatting partition..."
mkfs.ext4 /dev/md0p1

# Создаем точку монтирования
mkdir -p /raid5

# Добавляем в fstab
echo "/dev/md0p1 /raid5 ext4 defaults 0 0" >> /etc/fstab

# Монтируем
mount -a

# Устанавливаем и настраиваем NFS
echo "Installing NFS server..."
apt-get update
apt-get install nfs-kernel-server -y

# Создаем директорию для NFS
mkdir -p /raid5/nfs
chown nobody:nogroup /raid5/nfs
chmod 777 /raid5/nfs

# Настраиваем экспорт NFS
echo "/raid5/nfs 192.168.2.0/28(rw,sync,no_subtree_check)" >> /etc/exports

# Включаем и запускаем службы
systemctl enable nfs-kernel-server
systemctl restart nfs-kernel-server

# Применяем экспорт
exportfs -a

echo "Storage configuration completed!"
echo "RAID 5 created on /dev/md0"
echo "NFS share available at /raid5/nfs for network 192.168.2.0/28"