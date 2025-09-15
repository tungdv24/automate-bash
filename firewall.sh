#!/bin/bash


detect_os() {
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        OS=$ID
    else
        echo "Unable to detect OS."
        exit 1
    fi
}

enable_firewall() {
    if [[ "$OS" =~ centos|rhel ]]; then
        systemctl start firewalld
        systemctl enable firewalld
    elif [[ "$OS" =~ ubuntu|debian ]]; then
        ufw enable <<< "y"
    fi
}

show_rules() {
    echo "========== FIREWALL STATUS =========="
    if [[ "$OS" =~ centos|rhel ]]; then
        firewall-cmd --state
        echo "-------------------------------------"
        firewall-cmd --list-all
        echo "-------------------------------------"
        echo "Rich Rules:"
        firewall-cmd --list-rich-rules
    elif [[ "$OS" =~ ubuntu|debian ]]; then
        ufw status verbose
    fi
    echo "====================================="
}

apply_add_rule() {
    local PORT="$1"
    local IP="$2"
    local ACTION="$3"

    if [[ "$OS" =~ centos|rhel ]]; then
        local verb
        [[ "$ACTION" == "deny" ]] && verb="reject" || verb="accept"

        if [[ "$PORT" =~ "-" ]]; then
            local start_port end_port
            IFS='-' read -r start_port end_port <<< "$PORT"
        fi

        if [[ -n "$IP" ]]; then
            RULE="rule family=ipv4 source address=$IP port protocol=tcp port=$PORT $verb"
            firewall-cmd --permanent --add-rich-rule="$RULE"
        else
            if [[ "$ACTION" == "deny" ]]; then
                RULE="rule family=ipv4 port protocol=tcp port=$PORT reject"
                firewall-cmd --permanent --add-rich-rule="$RULE"
            else
                firewall-cmd --permanent --add-port=${PORT}/tcp
            fi
        fi

    elif [[ "$OS" =~ ubuntu|debian ]]; then
        if [[ "$ACTION" == "deny" ]]; then
            [[ -n "$IP" ]] && ufw deny from "$IP" to any port "$PORT" || ufw deny "$PORT"
        else
            [[ -n "$IP" ]] && ufw allow from "$IP" to any port "$PORT" || ufw allow "$PORT"
        fi
    fi
}

add_rules() {
    local ACTION=${1:-allow}
    echo "=== Add Firewall Rule (${ACTION^^}) ==="
    read -p "Enter ports (comma-separated, can include ranges like 80,100-110,443): " PORTS
    read -p "Enter IPs or CIDRs (comma-separated, leave empty for all): " IPS

    echo "Choose protocol:"
    echo "1) TCP"
    echo "2) UDP"
    echo "3) BOTH"
    read -p "Select [1-3]: " PROTO_CHOICE

    case "$PROTO_CHOICE" in
        1) PROTO="tcp" ;;
        2) PROTO="udp" ;;
        3) PROTO="both" ;;
        *) echo "Invalid choice, defaulting to TCP."; PROTO="tcp" ;;
    esac

    IFS=',' read -ra PORT_LIST <<< "$PORTS"
    IFS=',' read -ra IP_LIST <<< "${IPS:-}"

    for PORT in "${PORT_LIST[@]}"; do
        if [[ "${#IP_LIST[@]}" -eq 0 ]]; then
            apply_add_rule "$PORT" "" "$ACTION" "$PROTO"
        else
            for IP in "${IP_LIST[@]}"; do
                apply_add_rule "$PORT" "$IP" "$ACTION" "$PROTO"
            done
        fi
    done

    if [[ "$OS" =~ centos|rhel ]]; then
        firewall-cmd --reload
    fi

    echo "Rules added successfully."
}

remove_rules() {
    echo "=== Remove Firewall Rules ==="
    if [[ "$OS" =~ centos|rhel ]]; then
        echo "Gathering current firewalld rules..."

        mapfile -t PORTS < <(firewall-cmd --list-ports | tr ' ' '\n')
        mapfile -t SERVICES < <(firewall-cmd --list-services | tr ' ' '\n')
        mapfile -t RICH_RULES < <(firewall-cmd --list-rich-rules)

        echo "Available rules to remove:"
        INDEX=1
        RULE_MAP=()

        for PORT in "${PORTS[@]}"; do
            echo "$INDEX) Port: $PORT"
            RULE_MAP[$INDEX]="port:$PORT"
            ((INDEX++))
        done

        for SERVICE in "${SERVICES[@]}"; do
            echo "$INDEX) Service: $SERVICE"
            RULE_MAP[$INDEX]="service:$SERVICE"
            ((INDEX++))
        done

        for RULE in "${RICH_RULES[@]}"; do
            echo "$INDEX) Rich Rule: $RULE"
            RULE_MAP[$INDEX]="rich:$RULE"
            ((INDEX++))
        done

        echo
        read -p "Enter rule numbers to remove (comma-separated): " INPUT
        IFS=',' read -ra TO_REMOVE <<< "$INPUT"

        for NUM in "${TO_REMOVE[@]}"; do
            RULE_ENTRY="${RULE_MAP[$NUM]}"
            TYPE="${RULE_ENTRY%%:*}"
            VALUE="${RULE_ENTRY#*:}"

            case "$TYPE" in
                port)
                    firewall-cmd --permanent --remove-port="$VALUE" && echo "Removed port: $VALUE"
                    ;;
                service)
                    firewall-cmd --permanent --remove-service="$VALUE" && echo "Removed service: $VALUE"
                    ;;
                rich)
                    firewall-cmd --permanent --remove-rich-rule="$VALUE" && echo "Removed rich rule: $VALUE"
                    ;;
                *)
                    echo "Unknown rule type: $TYPE"
                    ;;
            esac
        done

        firewall-cmd --reload
        echo "Selected rules removed."

    elif [[ "$OS" =~ ubuntu|debian ]]; then
        echo "Current UFW Rules:"
        ufw status numbered
        echo
        read -p "Enter rule numbers to delete (comma-separated): " RULE_NUMS
        for NUM in $(echo "$RULE_NUMS" | tr ',' ' '); do
            yes | ufw delete "$NUM"
        done
        echo "Selected UFW rules deleted."
    else
        echo "Unsupported OS for this function."
    fi
}


main_menu() {
    enable_firewall
    while true; do
        echo
        echo "===== FIREWALL MANAGER ====="
        echo "1) Show firewall status and current rules"
        echo "2) Add firewall rule (ALLOW)"
        echo "3) Add firewall rule (DENY)"
        echo "4) Remove firewall rule"
        echo "5) Exit"
        echo "============================"
        read -p "Select an option: " CHOICE
        echo

        case "$CHOICE" in
            1) show_rules ;;
            2) add_rules "allow" ;;
            3) add_rules "deny" ;;
            4) remove_rules ;;
            5) echo "Exiting..."; exit 0 ;;
            *) echo "Invalid choice." ;;
        esac
    done
}

### START SCRIPT ###
clear
detect_os
main_menu