#!/bin/bash
# ======================================================
# AUTONET - Комплексный скрипт настройки сетевой инфраструктуры
# Версия 2.1
# ======================================================

set -euo pipefail
BACKUP_DIR="/root/backup_configs"
LOG_FILE="/var/log/autonet_setup.log"
CURRENT_DEVICE=""

# Цвета для вывода
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Логирование
log() {
    echo -e "${BLUE}[$(date '+%Y-%m-%d %H:%M:%S')]${NC} $1" | tee -a "$LOG_FILE"
}

success() {
    echo -e "${GREEN}✓${NC} $1" | tee -a "$LOG_FILE"
}

warning() {
    echo -e "${YELLOW}⚠${NC} $1" | tee -a "$LOG_FILE"
}

error() {
    echo -e "${RED}✗${NC} $1" | tee -a "$LOG_FILE"
    exit 1
}

# Проверка прав root
check_root() {
    if [[ $EUID -ne 0 ]]; then
        error "Этот скрипт должен быть запущен с правами root"
    fi
}

# Создание резервных копий
backup_config() {
    local file="$1"
    if [[ -f "$file" ]]; then
        mkdir -p "$BACKUP_DIR"
        cp "$file" "$BACKUP_DIR/$(basename "$file").backup.$(date +%Y%m%d_%H%M%S)"
        log "Создана резервная копия: $file"
    fi
}

# Добавление в cron
add_cron_job() {
    local line="$1"
    if ! crontab -l 2>/dev/null | grep -Fq "$line"; then
        (crontab -l 2>/dev/null; echo "$line") | crontab -
        log "Добавлено задание в cron: $line"
    fi
}

# Безопасный перезапуск сетевых служб
restart_networking() {
    log "Перезапуск сетевых служб..."
    systemctl restart networking 2>/dev/null || \
    systemctl restart network 2>/dev/null || \
    warning "Не удалось перезапустить сетевые службы"
}

# ======================================================
# ОСНОВНЫЕ ФУНКЦИИ НАСТРОЙКИ
# ======================================================

setup_hostname() {
    local hostname="$1"
    hostnamectl set-hostname "$hostname"
    success "Установлено имя хоста: $hostname"
}

setup_timezone() {
    timedatectl set-timezone Asia/Yekaterinburg
    success "Установлен часовой пояс Asia/Yekaterinburg"
}

setup_forwarding() {
    sed -i 's/^#*net.ipv4.ip_forward=.*/net.ipv4.ip_forward=1/' /etc/sysctl.conf
    echo "net.ipv4.ip_forward=1" >> /etc/sysctl.conf
    sysctl -p >/dev/null
    success "Включен IP forwarding"
}

setup_nat() {
    local network="$1"
    local interface="$2"
    
    if ! iptables -t nat -C POSTROUTING -s "$network" -o "$interface" -j MASQUERADE 2>/dev/null; then
        iptables -t nat -A POSTROUTING -s "$network" -o "$interface" -j MASQUERADE
    fi
    
    iptables-save > /root/iptables.rules
    add_cron_job "@reboot /sbin/iptables-restore < /root/iptables.rules"
    success "Настроен NAT для сети $network на интерфейсе $interface"
}

# ======================================================
# ФУНКЦИИ ДЛЯ КОНКРЕТНЫХ УСТРОЙСТВ
# ======================================================

setup_isp() {
    CURRENT_DEVICE="ISP"
    log "Настройка ISP..."
    
    setup_hostname "isp"
    setup_timezone
    
    backup_config "/etc/network/interfaces"
    cat > /etc/network/interfaces << EOF
auto lo
iface lo inet loopback

auto eth0
iface eth0 inet dhcp

auto eth1
iface eth1 inet static
address 172.16.4.1/28

auto eth2
iface eth2 inet static
address 172.16.5.1/28
EOF

    restart_networking
    setup_forwarding
    setup_nat "172.16.4.0/28" "eth0"
    setup_nat "172.16.5.0/28" "eth0"
    
    success "Настройка ISP завершена"
}

setup_hq_rtr() {
    CURRENT_DEVICE="HQ-RTR"
    log "Настройка HQ-RTR..."
    
    setup_hostname "hq-rtr.au-team.irpo"
    setup_timezone
    
    backup_config "/etc/network/interfaces"
    cat > /etc/network/interfaces << EOF
auto lo
iface lo inet loopback

auto eth0
iface eth0 inet static
address 172.16.4.2/28
gateway 172.16.4.1

auto eth1
iface eth1 inet manual

auto eth1.100
iface eth1.100 inet static
address 192.168.1.1/26
vlan-raw-device eth1

auto eth1.200
iface eth1.200 inet static
address 192.168.2.1/28
vlan-raw-device eth1

auto eth1.999
iface eth1.999 inet static
address 192.168.3.1/29
vlan-raw-device eth1
EOF

    restart_networking
    setup_forwarding
    setup_nat "192.168.1.0/26" "eth0"
    setup_nat "192.168.2.0/28" "eth0"
    setup_nat "192.168.3.0/29" "eth0"
    
    success "Настройка HQ-RTR завершена"
}

setup_br_rtr() {
    CURRENT_DEVICE="BR-RTR"
    log "Настройка BR-RTR..."
    
    setup_hostname "br-rtr.au-team.irpo"
    setup_timezone
    
    backup_config "/etc/network/interfaces"
    cat > /etc/network/interfaces << EOF
auto lo
iface lo inet loopback

auto eth0
iface eth0 inet static
address 172.16.5.2/28
gateway 172.16.5.1

auto eth1
iface eth1 inet static
address 192.168.4.1/27
EOF

    restart_networking
    setup_forwarding
    setup_nat "192.168.4.0/27" "eth0"
    
    success "Настройка BR-RTR завершена"
}

setup_hq_srv() {
    CURRENT_DEVICE="HQ-SRV"
    log "Настройка HQ-SRV..."
    
    setup_hostname "hq-srv.au-team.irpo"
    setup_timezone
    
    # Настройка VLAN
    mkdir -p /etc/net/ifaces/enp0s3.100
    cat > /etc/net/ifaces/enp0s3.100/options << EOF
TYPE=vlan
HOST=enp0s3
VID=100
DISABLED=no
BOOTPROTO=static
EOF

    echo "192.168.1.2/26" > /etc/net/ifaces/enp0s3.100/ipv4address
    echo "default via 192.168.1.1" > /etc/net/ifaces/enp0s3.100/ipv4route
    
    restart_networking
    success "Настройка HQ-SRV завершена"
}

setup_br_srv() {
    CURRENT_DEVICE="BR-SRV"
    log "Настройка BR-SRV..."
    
    setup_hostname "br-srv.au-team.irpo"
    setup_timezone
    
    mkdir -p /etc/net/ifaces/enp0s3
    cat > /etc/net/ifaces/enp0s3/options << EOF
TYPE=eth
DISABLED=no
BOOTPROTO=static
NM_CONTROLLED=no
EOF

    echo "192.168.4.2/27" > /etc/net/ifaces/enp0s3/ipv4address
    echo "default via 192.168.4.1" > /etc/net/ifaces/enp0s3/ipv4route
    
    restart_networking
    success "Настройка BR-SRV завершена"
}

setup_hq_cli() {
    CURRENT_DEVICE="HQ-CLI"
    log "Настройка HQ-CLI..."
    
    setup_hostname "hq-cli.au-team.irpo"
    setup_timezone
    
    mkdir -p /etc/net/ifaces/enp0s3.200
    cat > /etc/net/ifaces/enp0s3.200/options << EOF
TYPE=vlan
VID=200
HOST=enp0s3
DISABLED=no
BOOTPROTO=dhcp
EOF

    restart_networking
    success "Настройка HQ-CLI завершена"
}

# ======================================================
# ДОПОЛНИТЕЛЬНЫЕ СЕРВИСЫ
# ======================================================

setup_gre_tunnel() {
    log "Настройка GRE-туннеля..."
    
    case "$CURRENT_DEVICE" in
        "HQ-RTR")
            cat >> /etc/network/interfaces << EOF

auto gre1
iface gre1 inet tunnel
address 10.10.10.1
netmask 255.255.255.252
mode gre
local 172.16.4.2
endpoint 172.16.5.2
ttl 255
EOF
            ;;
        "BR-RTR")
            cat >> /etc/network/interfaces << EOF

auto gre1
iface gre1 inet tunnel
address 10.10.10.2
netmask 255.255.255.252
mode gre
local 172.16.5.2
endpoint 172.16.4.2
ttl 255
EOF
            ;;
        *)
            warning "GRE не поддерживается на $CURRENT_DEVICE"
            return
            ;;
    esac
    
    restart_networking
    
    if [[ "$CURRENT_DEVICE" == "BR-RTR" ]]; then
        ping -c 4 10.10.10.1 && success "GRE-туннель настроен и проверен" || warning "Проблемы с GRE-туннелем"
    else
        success "GRE-туннель настроен"
    fi
}

setup_ospf() {
    log "Настройка OSPF..."
    
    if [[ "$CURRENT_DEVICE" != "HQ-RTR" && "$CURRENT_DEVICE" != "BR-RTR" ]]; then
        warning "OSPF не поддерживается на $CURRENT_DEVICE"
        return
    fi
    
    # Временный репозиторий для установки FRR
    echo "deb [trusted=yes] http://archive.debian.org/debian buster main" >> /etc/apt/sources.list
    echo "nameserver 8.8.8.8" > /etc/resolv.conf
    
    apt-get update
    apt-get install -y frr
    
    # Настройка OSPF
    sed -i 's/^ospfd=no/ospfd=yes/' /etc/frr/daemons
    systemctl restart frr
    
    # Конфигурация OSPF
    vtysh << EOF
conf t
router ospf
network 10.10.10.0/30 area 0
EOF

    if [[ "$CURRENT_DEVICE" == "HQ-RTR" ]]; then
        vtysh << EOF
conf t
router ospf
network 192.168.1.0/26 area 0
network 192.168.2.0/28 area 0
network 192.168.3.0/29 area 0
EOF
    else
        vtysh << EOF
conf t
router ospf
network 192.168.4.0/27 area 0
EOF
    fi

    vtysh << EOF
interface gre1
ip ospf authentication message-digest
ip ospf message-digest-key 1 md5 P@ssw0rd
exit
exit
wr mem
EOF

    # Очистка временного репозитория
    sed -i '/deb \[trusted=yes\] http:\/\/archive.debian.org\/debian buster main/d' /etc/apt/sources.list
    
    if [[ "$CURRENT_DEVICE" == "BR-RTR" ]]; then
        vtysh -c "show ip ospf neighbor" && success "OSPF настроен" || warning "Проблемы с OSPF"
    else
        success "OSPF настроен"
    fi
}

setup_dhcp() {
    log "Настройка DHCP..."
    
    if [[ "$CURRENT_DEVICE" != "HQ-RTR" ]]; then
        warning "DHCP не поддерживается на $CURRENT_DEVICE"
        return
    fi
    
    apt-get update
    apt-get install -y dnsmasq
    
    backup_config "/etc/dnsmasq.conf"
    cat > /etc/dnsmasq.conf << EOF
no-resolv
dhcp-range=192.168.2.2,192.168.2.14,9999h
dhcp-option=3,192.168.2.1
dhcp-option=6,192.168.1.2
interface=eth1.200
EOF

    systemctl restart dnsmasq
    systemctl status dnsmasq && success "DHCP настроен" || error "Ошибка настройки DHCP"
}

setup_dns() {
    log "Настройка DNS..."
    
    if [[ "$CURRENT_DEVICE" != "HQ-SRV" ]]; then
        warning "DNS не поддерживается на $CURRENT_DEVICE"
        return
    fi
    
    systemctl disable --now bind 2>/dev/null || true
    
    apt-get update
    apt-get install -y dnsmasq
    
    backup_config "/etc/dnsmasq.conf"
    cat > /etc/dnsmasq.conf << EOF
no-resolv
domain=au-team.irpo
server=8.8.8.8
interface=*

address=/hq-rtr.au-team.irpo/192.168.1.1
ptr-record=1.1.168.192.in-addr.arpa,hq-rtr.au-team.irpo
cname=moodle.au-team.irpo,hq-rtr.au-team.irpo
cname=wiki.au-team.irpo,hq-rtr.au-team.irpo

address=/br-rtr.au-team.irpo/192.168.4.1

address=/hq-srv.au-team.irpo/192.168.1.2
ptr-record=2.1.168.192.in-addr.arpa,hq-srv.au-team.irpo

address=/hq-cli.au-team.irpo/192.168.2.11
ptr-record=11.2.168.192.in-addr.arpa,hq-cli.au-team.irpo

address=/br-srv.au-team.irpo/192.168.4.2
EOF

    echo "192.168.1.1 hq-rtr.au-team.irpo" >> /etc/hosts
    
    systemctl enable --now dnsmasq
    systemctl restart dnsmasq
    
    # Проверка работы DNS
    if ping -c 2 hq-rtr.au-team.irpo &>/dev/null; then
        success "DNS настроен и работает"
    else
        warning "DNS настроен, но есть проблемы с разрешением имен"
    fi
}

setup_users() {
    log "Настройка пользователей..."
    
    case "$CURRENT_DEVICE" in
        "HQ-SRV"|"BR-SRV")
            useradd -u 1010 -m -s /bin/bash sshuser 2>/dev/null || true
            echo "sshuser:P@ssw0rd" | chpasswd
            
            if ! grep -q "^%wheel" /etc/sudoers; then
                echo "%wheel ALL=(ALL:ALL) NOPASSWD: ALL" >> /etc/sudoers
            fi
            
            usermod -aG wheel sshuser
            success "Создан пользователь sshuser"
            ;;
        "HQ-RTR"|"BR-RTR")
            useradd -m -s /bin/bash net_admin 2>/dev/null || true
            echo "net_admin:P@\$\$word" | chpasswd
            echo "net_admin ALL=(ALL:ALL) NOPASSWD: ALL" >> /etc/sudoers
            success "Создан пользователь net_admin"
            ;;
        *)
            warning "Создание пользователей не требуется на $CURRENT_DEVICE"
            return
            ;;
    esac
}

setup_ssh() {
    log "Настройка SSH..."
    
    if [[ "$CURRENT_DEVICE" != "HQ-SRV" && "$CURRENT_DEVICE" != "BR-SRV" ]]; then
        warning "Настройка SSH не требуется на $CURRENT_DEVICE"
        return
    fi
    
    apt-get install -y openssh-server openssh-common
    
    echo "Authorized access only" > /root/banner
    chmod 644 /root/banner
    
    backup_config "/etc/ssh/sshd_config"
    
    # Используем sed для безопасного изменения конфигурации
    sed -i 's/^#*Port.*/Port 2024/' /etc/ssh/sshd_config
    sed -i 's/^#*MaxAuthTries.*/MaxAuthTries 2/' /etc/ssh/sshd_config
    sed -i 's/^#*PermitRootLogin.*/PermitRootLogin no/' /etc/ssh/sshd_config
    sed -i 's|^#*Banner.*|Banner /root/banner|' /etc/ssh/sshd_config
    
    if ! grep -q "^AllowUsers" /etc/ssh/sshd_config; then
        echo "AllowUsers sshuser" >> /etc/ssh/sshd_config
    else
        sed -i 's/^AllowUsers.*/AllowUsers sshuser/' /etc/ssh/sshd_config
    fi
    
    # Проверка синтаксиса перед перезапуском
    if sshd -t; then
        systemctl enable ssh
        systemctl restart ssh
        
        # Проверка работы SSH
        if netstat -tln | grep -q :2024; then
            success "SSH настроен на порту 2024"
        else
            warning "SSH настроен, но не слушает порт 2024"
        fi
    else
        error "Ошибка в конфигурации SSH"
    fi
}

# ======================================================
# ГЛАВНОЕ МЕНЮ
# ======================================================

show_menu() {
    while true; do
        echo -e "\n${BLUE}======================================${NC}"
        echo -e "${BLUE}    AUTONET - Настройка сети${NC}"
        echo -e "${BLUE}======================================${NC}"
        echo
        echo "Выберите устройство для настройки:"
        echo "1) ISP"
        echo "2) HQ-RTR"
        echo "3) BR-RTR"
        echo "4) HQ-SRV"
        echo "5) BR-SRV"
        echo "6) HQ-CLI"
        echo "0) Выход"
        echo
        read -rp "Ваш выбор: " choice
        
        case $choice in
            1) setup_isp; show_services_menu ;;
            2) setup_hq_rtr; show_services_menu ;;
            3) setup_br_rtr; show_services_menu ;;
            4) setup_hq_srv; show_services_menu ;;
            5) setup_br_srv; show_services_menu ;;
            6) setup_hq_cli; show_services_menu ;;
            0) exit 0 ;;
            *) echo "Неверный выбор"; ;;
        esac
    done
}

show_services_menu() {
    while true; do
        echo -e "\n${BLUE}Дополнительные сервисы для $CURRENT_DEVICE${NC}"
        echo "1) Настроить GRE-туннель"
        echo "2) Настроить OSPF"
        echo "3) Настроить DHCP"
        echo "4) Настроить DNS"
        echo "5) Настроить пользователей"
        echo "6) Настроить SSH"
        echo "7) Настроить все сервисы"
        echo "8) Вернуться в главное меню"
        echo "0) Выход"
        echo
        read -rp "Ваш выбор: " choice
        
        case $choice in
            1) setup_gre_tunnel ;;
            2) setup_ospf ;;
            3) setup_dhcp ;;
            4) setup_dns ;;
            5) setup_users ;;
            6) setup_ssh ;;
            7)
                setup_gre_tunnel
                setup_ospf
                setup_dhcp
                setup_dns
                setup_users
                setup_ssh
                ;;
            8) return ;;
            0) exit 0 ;;
            *) echo "Неверный выбор"; ;;
        esac
        
        read -p "Нажмите Enter для продолжения..."
    done
}

# ======================================================
# ОСНОВНАЯ ПРОГРАММА
# ======================================================

main() {
    check_root
    mkdir -p "$BACKUP_DIR"
    echo "========================================" > "$LOG_FILE"
    echo "AUTONET - Лог настройки" >> "$LOG_FILE"
    echo "Начало: $(date)" >> "$LOG_FILE"
    echo "========================================" >> "$LOG_FILE"
    
    log "Запуск скрипта настройки"
    show_menu
}

# Запуск главной функции
main "$@"