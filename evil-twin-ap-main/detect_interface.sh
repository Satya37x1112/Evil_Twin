#!/bin/bash

#########################################################
# Evil Twin AP - Interface Detection Script
# Purpose: Detect and verify wireless interfaces for AP mode
# Usage: ./detect_interface.sh
#########################################################

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

print_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[✓]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[!]${NC} $1"
}

print_error() {
    echo -e "${RED}[✗]${NC} $1"
}

echo -e "${GREEN}"
echo "=========================================="
echo "   Wireless Interface Detection"
echo "=========================================="
echo -e "${NC}"

# Get all wireless interfaces
print_info "Scanning for wireless interfaces..."
echo ""

WIRELESS_INTERFACES=$(iw dev 2>/dev/null | grep Interface | awk '{print $2}')

if [ -z "$WIRELESS_INTERFACES" ]; then
    print_error "No wireless interfaces found!"
    echo ""
    print_info "Checking if wireless drivers are loaded..."
    lsusb | grep -i "wireless\|wi-fi\|802.11\|network"
    exit 1
fi

INTERFACE_COUNT=$(echo "$WIRELESS_INTERFACES" | wc -l)
print_success "Found ${INTERFACE_COUNT} wireless interface(s)"
echo ""

# Analyze each interface
declare -a AP_CAPABLE_INTERFACES=()

for iface in $WIRELESS_INTERFACES; do
    echo -e "${CYAN}═══════════════════════════════════════════${NC}"
    echo -e "${CYAN}Interface: ${iface}${NC}"
    echo -e "${CYAN}═══════════════════════════════════════════${NC}"

    # Check if interface exists
    if ! ip link show "$iface" &>/dev/null; then
        print_error "Interface $iface not found in ip link"
        echo ""
        continue
    fi

    # Get interface state
    STATE=$(ip link show "$iface" | grep -oP "state \K\w+")
    echo -e "State: ${STATE}"

    # Get MAC address
    MAC=$(ip link show "$iface" | grep -oP "link/ether \K[0-9a-f:]+")
    echo -e "MAC Address: ${MAC}"

    # Get driver info
    DRIVER=$(basename $(readlink /sys/class/net/$iface/device/driver 2>/dev/null) 2>/dev/null)
    if [ -n "$DRIVER" ]; then
        echo -e "Driver: ${DRIVER}"
    else
        echo -e "Driver: ${YELLOW}Unknown${NC}"
    fi

    # Check chipset (from USB devices)
    USB_INFO=$(lsusb -v 2>/dev/null | grep -B 5 -A 10 "$iface" | grep -i "realtek\|atheros\|ralink\|mediatek" | head -1)
    if [ -n "$USB_INFO" ]; then
        echo -e "Chipset: $(echo $USB_INFO | awk '{print $1}')"
    fi

    # Check supported modes using iw
    echo ""
    print_info "Checking capabilities for ${iface}..."

    SUPPORTS_AP=false
    SUPPORTS_MONITOR=false

    if iw list 2>/dev/null | grep -A 15 "Supported interface modes" | grep -q "* AP"; then
        SUPPORTS_AP=true
    fi

    if iw list 2>/dev/null | grep -A 15 "Supported interface modes" | grep -q "* monitor"; then
        SUPPORTS_MONITOR=true
    fi

    # Display capabilities
    if [ "$SUPPORTS_AP" = true ]; then
        print_success "Supports AP mode (Access Point) ✓"
        AP_CAPABLE_INTERFACES+=("$iface")
    else
        print_error "Does NOT support AP mode ✗"
    fi

    if [ "$SUPPORTS_MONITOR" = true ]; then
        print_success "Supports Monitor mode ✓"
    else
        print_warning "Does NOT support Monitor mode"
    fi

    # Check current mode
    CURRENT_MODE=$(iw dev "$iface" info 2>/dev/null | grep type | awk '{print $2}')
    echo -e "Current Mode: ${CURRENT_MODE:-Unknown}"

    # Check if interface is busy
    if [ "$STATE" = "UP" ]; then
        CONNECTED_TO=$(iw dev "$iface" link 2>/dev/null | grep "Connected to" | awk '{print $3}')
        if [ -n "$CONNECTED_TO" ]; then
            print_warning "Currently connected to: ${CONNECTED_TO}"
        fi
    fi

    # Check power management
    PM_STATUS=$(iw dev "$iface" get power_save 2>/dev/null | awk '{print $NF}')
    if [ "$PM_STATUS" = "on" ]; then
        print_warning "Power management is ON (may cause issues)"
    fi

    echo ""
done

# Summary
echo -e "${GREEN}=========================================="
echo "   Summary & Recommendations"
echo -e "==========================================${NC}"
echo ""

if [ ${#AP_CAPABLE_INTERFACES[@]} -eq 0 ]; then
    print_error "NO interfaces support AP mode!"
    echo ""
    print_warning "You need a wireless adapter that supports AP mode."
    print_info "Recommended adapters:"
    echo "  - Alfa AWUS036ACH (RTL8812AU)"
    echo "  - TP-Link TL-WN722N v1 (Atheros AR9271)"
    echo "  - Alfa AWUS036ACM (MT7612U)"
    echo ""
    exit 1
fi

if [ ${#AP_CAPABLE_INTERFACES[@]} -eq 1 ]; then
    RECOMMENDED="${AP_CAPABLE_INTERFACES[0]}"
    print_success "Found 1 AP-capable interface: ${RECOMMENDED}"
    echo ""
    print_info "Recommendation: Use ${RECOMMENDED} for evil twin AP"
    echo ""
    print_info "To update configuration files, run:"
    echo -e "  ${GREEN}sed -i 's/^interface=.*/interface=${RECOMMENDED}/' hostapd.conf${NC}"
    echo -e "  ${GREEN}sed -i 's/^interface=.*/interface=${RECOMMENDED}/' dnsmasq.conf${NC}"
    echo ""
else
    print_success "Found ${#AP_CAPABLE_INTERFACES[@]} AP-capable interfaces:"
    for iface in "${AP_CAPABLE_INTERFACES[@]}"; do
        echo "  - $iface"
    done
    echo ""

    # Try to recommend the best one
    RECOMMENDED=""

    # Prefer interfaces with "realtek" or external adapters (wlan1, wlan2, etc.)
    for iface in "${AP_CAPABLE_INTERFACES[@]}"; do
        if [[ "$iface" != "wlan0" ]]; then
            RECOMMENDED="$iface"
            break
        fi
    done

    # If all are wlan0, just use first
    if [ -z "$RECOMMENDED" ]; then
        RECOMMENDED="${AP_CAPABLE_INTERFACES[0]}"
    fi

    print_info "Recommendation: Use ${RECOMMENDED} (likely external USB adapter)"
    echo ""
    print_warning "wlan0 is usually built-in WiFi - use external adapter if available"
    echo ""
    print_info "To update configuration files, run:"
    echo -e "  ${GREEN}sed -i 's/^interface=.*/interface=${RECOMMENDED}/' hostapd.conf${NC}"
    echo -e "  ${GREEN}sed -i 's/^interface=.*/interface=${RECOMMENDED}/' dnsmasq.conf${NC}"
    echo ""
fi

# Show current config
echo -e "${BLUE}Current Configuration:${NC}"
if [ -f "hostapd.conf" ]; then
    CURRENT_IFACE=$(grep "^interface=" hostapd.conf | cut -d'=' -f2)
    echo "  hostapd.conf: interface=${CURRENT_IFACE}"
fi
if [ -f "dnsmasq.conf" ]; then
    CURRENT_IFACE=$(grep "^interface=" dnsmasq.conf | cut -d'=' -f2)
    echo "  dnsmasq.conf: interface=${CURRENT_IFACE}"
fi

echo ""
print_info "After updating, verify with: iw list | grep -A 10 'Supported interface modes'"
echo ""
