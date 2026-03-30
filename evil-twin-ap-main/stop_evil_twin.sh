#!/bin/bash

#########################################################
# Evil Twin AP Stop Script
# Purpose: Cleanly stop the evil twin access point
# Usage: sudo ./stop_evil_twin.sh
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
PID_FILE="${SCRIPT_DIR}/.evil_twin.pid"
LOG_DIR="${SCRIPT_DIR}/logs"

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
    echo -e "${RED}"
    echo "=========================================="
    echo "   Evil Twin AP - Stop Script"
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
# Function: Load PIDs and configuration
#########################################################
load_pids() {
    print_info "Loading process information..."

    if [ ! -f "$PID_FILE" ]; then
        print_warning "PID file not found. Attempting to stop all related processes..."
        return 1
    fi

    source "$PID_FILE"
    print_success "Process information loaded"
    return 0
}

#########################################################
# Function: Stop hostapd
#########################################################
stop_hostapd() {
    print_info "Stopping hostapd..."

    if [ -n "$HOSTAPD_PID" ] && ps -p "$HOSTAPD_PID" > /dev/null 2>&1; then
        kill "$HOSTAPD_PID" 2>/dev/null
        sleep 1
        if ps -p "$HOSTAPD_PID" > /dev/null 2>&1; then
            kill -9 "$HOSTAPD_PID" 2>/dev/null
        fi
        print_success "hostapd stopped (PID: ${HOSTAPD_PID})"
    else
        # Fallback: kill all hostapd processes
        if pgrep -x hostapd > /dev/null; then
            pkill -9 hostapd
            print_success "hostapd processes killed"
        else
            print_warning "hostapd was not running"
        fi
    fi
}

#########################################################
# Function: Stop dnsmasq
#########################################################
stop_dnsmasq() {
    print_info "Stopping dnsmasq..."

    if [ -n "$DNSMASQ_PID" ] && ps -p "$DNSMASQ_PID" > /dev/null 2>&1; then
        kill "$DNSMASQ_PID" 2>/dev/null
        sleep 1
        if ps -p "$DNSMASQ_PID" > /dev/null 2>&1; then
            kill -9 "$DNSMASQ_PID" 2>/dev/null
        fi
        print_success "dnsmasq stopped (PID: ${DNSMASQ_PID})"
    else
        # Fallback: kill all dnsmasq processes
        if pgrep -x dnsmasq > /dev/null; then
            pkill -9 dnsmasq
            print_success "dnsmasq processes killed"
        else
            print_warning "dnsmasq was not running"
        fi
    fi
}

#########################################################
# Function: Stop connection monitor
#########################################################
stop_monitor() {
    print_info "Stopping connection monitor..."

    if [ -n "$MONITOR_PID" ] && ps -p "$MONITOR_PID" > /dev/null 2>&1; then
        kill "$MONITOR_PID" 2>/dev/null
        print_success "Connection monitor stopped (PID: ${MONITOR_PID})"
    else
        print_warning "Connection monitor was not running"
    fi
}

#########################################################
# Function: Stop captive portal server
#########################################################
stop_portal() {
    print_info "Stopping captive portal server..."

    if [ -n "$PORTAL_PID" ] && ps -p "$PORTAL_PID" > /dev/null 2>&1; then
        kill "$PORTAL_PID" 2>/dev/null
        sleep 1
        if ps -p "$PORTAL_PID" > /dev/null 2>&1; then
            kill -9 "$PORTAL_PID" 2>/dev/null
        fi
        print_success "Captive portal stopped (PID: ${PORTAL_PID})"
    else
        # Fallback: kill all portal server processes
        if pgrep -f 'python3.*server.py' > /dev/null; then
            pkill -f 'python3.*server.py'
            print_success "Portal server processes killed"
        else
            print_warning "Captive portal was not running"
        fi
    fi
}

#########################################################
# Function: Clear iptables rules
#########################################################
clear_iptables() {
    print_info "Clearing iptables rules..."

    iptables -F
    iptables -t nat -F
    iptables -X

    # Reset to default policies
    iptables -P INPUT ACCEPT
    iptables -P FORWARD ACCEPT
    iptables -P OUTPUT ACCEPT

    print_success "iptables rules cleared"
}

#########################################################
# Function: Disable IP forwarding
#########################################################
disable_ip_forwarding() {
    print_info "Disabling IP forwarding..."
    echo 0 > /proc/sys/net/ipv4/ip_forward
    print_success "IP forwarding disabled"
}

#########################################################
# Function: Reset wireless interface
#########################################################
reset_wireless() {
    print_info "Resetting wireless interface..."

    local wlan_iface="${WLAN_INTERFACE:-wlan0}"

    if ip link show "$wlan_iface" &> /dev/null; then
        # Flush IP addresses
        ip addr flush dev "$wlan_iface"

        # Bring interface down and up
        ip link set "$wlan_iface" down
        sleep 1
        ip link set "$wlan_iface" up

        print_success "Wireless interface ${wlan_iface} reset"
    else
        print_warning "Wireless interface ${wlan_iface} not found"
    fi
}

#########################################################
# Function: Restart NetworkManager
#########################################################
restart_network_manager() {
    print_info "Restarting NetworkManager..."

    if systemctl is-active --quiet NetworkManager; then
        print_warning "NetworkManager is already running"
    else
        systemctl start NetworkManager 2>/dev/null || print_warning "Failed to start NetworkManager"
        if systemctl is-active --quiet NetworkManager; then
            print_success "NetworkManager started"
        fi
    fi
}

#########################################################
# Function: Display final statistics
#########################################################
display_statistics() {
    echo ""
    echo -e "${GREEN}=========================================="
    echo "   Session Statistics"
    echo -e "==========================================${NC}"

    if [ -f "${LOG_DIR}/connections.log" ]; then
        local unique_clients=$(grep -oP '\d+\.\d+\.\d+\.\d+' "${LOG_DIR}/connections.log" | sort -u | wc -l)
        echo -e "${BLUE}Unique clients connected:${NC} ${unique_clients}"

        echo ""
        echo -e "${BLUE}Last 10 DHCP assignments:${NC}"
        if [ -f "${LOG_DIR}/dnsmasq.log" ]; then
            grep "DHCPACK" "${LOG_DIR}/dnsmasq.log" | tail -n 10 | awk '{print "  " $0}' || echo "  No DHCP assignments"
        fi
    else
        print_warning "No connection logs found"
    fi

    echo ""
    echo -e "${BLUE}Log files preserved at:${NC}"
    echo "  ${LOG_DIR}/"
    echo ""
}

#########################################################
# Function: Clean up PID file
#########################################################
cleanup_pid_file() {
    print_info "Cleaning up..."

    # Restore NetworkManager control
    if [ -n "$WLAN_INTERFACE" ] && command -v nmcli &> /dev/null; then
        print_info "Restoring NetworkManager control for ${WLAN_INTERFACE}..."
        nmcli device set "$WLAN_INTERFACE" managed yes || print_warning "Could not restore interface management"
    fi

    if [ -f "$PID_FILE" ]; then
        rm "$PID_FILE"
        print_success "PID file removed"
    fi
}

#########################################################
# Function: Display summary
#########################################################
display_summary() {
    echo ""
    echo -e "${GREEN}=========================================="
    echo "   Evil Twin AP Stopped Successfully!"
    echo -e "==========================================${NC}"
    echo ""
    echo -e "${YELLOW}Network services have been restored${NC}"
    echo ""
    echo -e "${BLUE}To view session logs:${NC}"
    echo "  cat ${LOG_DIR}/hostapd.log"
    echo "  cat ${LOG_DIR}/dnsmasq.log"
    echo "  cat ${LOG_DIR}/connections.log"
    echo "  cat ${LOG_DIR}/captured_creds.log"
    echo ""
}

#########################################################
# Main execution
#########################################################
main() {
    print_banner

    check_root
    load_pids

    stop_monitor
    stop_hostapd
    stop_dnsmasq
    stop_portal
    clear_iptables
    disable_ip_forwarding
    reset_wireless
    restart_network_manager

    display_statistics
    cleanup_pid_file
    display_summary
}

# Run main function
main
