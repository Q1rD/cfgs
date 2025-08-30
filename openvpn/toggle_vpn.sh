#!/bin/bash

CFG_DIR="$HOME/openvpn/cfgs"
PID_FILE="$HOME/openvpn/openvpn.pid"
LOG_FILE="$HOME/openvpn/openvpn.log"
CONFIG_FILE="$HOME/openvpn/last_config.txt"

# Функция выбора конфига
select_config() {
    # Получаем список .ovpn и .txt файлов
    local configs=$(find "$CFG_DIR" -name "*.ovpn" -o -name "*.txt" | sort)
    
    if [ -z "$configs" ]; then
        notify-send "VPN" "Не найдены конфиги в $CFG_DIR" -t 2000
        exit 1
    fi
    
    # Получаем последний использованный конфиг
    local last_config=""
    if [ -f "$CONFIG_FILE" ]; then
        last_config=$(cat "$CONFIG_FILE")
    fi
    
    # Создаем список с последним конфигом вверху
    local sorted_configs="$configs"
    if [ -n "$last_config" ] && echo "$configs" | grep -q "$last_config"; then
        # Помещаем последний конфиг в начало списка
        sorted_configs=$(echo -e "$last_config\n$(echo "$configs" | grep -v "$last_config")")
    fi
    
    # Выводим имена файлов без пути
    local choices=$(echo "$sorted_configs" | xargs -n1 basename)
    
    # Используем dmenu для выбора
    if command -v dmenu >/dev/null 2>&1; then
        selected=$(echo "$choices" | dmenu -l 10 -p "Выберите конфиг VPN:")
    else
        # Простой текстовый выбор
        echo "Доступные конфиги:"
        echo "$choices" | nl
        read -p "Выберите номер: " choice_num
        selected=$(echo "$choices" | sed -n "${choice_num}p")
    fi
    
    # Находим полный путь к выбранному конфигу
    local full_path=""
    while IFS= read -r config; do
        if [ "$(basename "$config")" = "$selected" ]; then
            full_path="$config"
            break
        fi
    done <<< "$sorted_configs"
    
    if [ -n "$full_path" ] && [ -f "$full_path" ]; then
        echo "$full_path" > "$CONFIG_FILE"
        echo "$full_path"
    else
        notify-send "VPN" "Конфиг не найден: $selected" -t 2000
        exit 1
    fi
}

# Функция проверки VPN соединения
is_vpn_connected() {
    if [ -f "$PID_FILE" ] && kill -0 $(cat "$PID_FILE") 2>/dev/null; then
        return 0
    fi
    if ip link show tun0 2>/dev/null | grep -q "state UP"; then
        return 0
    fi
    return 1
}

# Основная логика
notify-send "VPN" "Проверка подключения" -t 2000
if is_vpn_connected; then
    notify-send "VPN" "Отключаем VPN..." -t 2000
    echo "Отключаем VPN..."
    if [ -f "$PID_FILE" ]; then
        kill -TERM $(cat "$PID_FILE") 2>/dev/null
        sleep 1
        kill -KILL $(cat "$PID_FILE") 2>/dev/null
    fi
    sudo ip link delete tun0 2>/dev/null
    rm -f "$PID_FILE"
    notify-send "VPN" "Отключено" -t 2000
else
    # Выбираем конфиг
    CONFIG=$(select_config)
    
    if [ -z "$CONFIG" ] || [ ! -f "$CONFIG" ]; then
        notify-send "VPN" "Конфиг не выбран или не найден" -t 2000
        exit 1
    fi
    
    echo "Подключаем VPN через $(basename $CONFIG)..."
    mkdir -p "$(dirname "$PID_FILE")"
    
    # Запускаем OpenVPN
    openvpn --config "$CONFIG" --writepid "$PID_FILE" --log "$LOG_FILE" --daemon
    
    # Ждем подключения
    for i in {1..10}; do
        sleep 1
        if is_vpn_connected; then
            notify-send "VPN" "Подключено через $(basename $CONFIG)" -t 2000
            exit 0
        fi
    done
    
    notify-send "VPN" "Ошибка подключения (таймаут)" -t 2000
fi

