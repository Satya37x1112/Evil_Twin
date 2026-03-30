#!/bin/bash

#########################################################
# Evil Twin AP - Dependency Installation Script
# Purpose: Install all required tools and dependencies
# Usage: sudo ./install_dependencies.sh
#########################################################

set -e  # Exit on error

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

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
    echo "   Evil Twin AP - Dependency Installer"
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
# Function: Detect Linux distribution
#########################################################
detect_distro() {
    print_info "Detecting Linux distribution..."

    if [ -f /etc/os-release ]; then
        . /etc/os-release
        DISTRO=$ID
        VERSION=$VERSION_ID
        print_success "Detected: ${NAME} ${VERSION}"
    else
        print_error "Cannot detect Linux distribution"
        exit 1
    fi
}

#########################################################
# Function: Update package lists
#########################################################
update_package_lists() {
    print_info "Updating package lists..."

    case $DISTRO in
        kali|debian|ubuntu)
            apt-get update -qq
            ;;
        fedora|centos|rhel)
            dnf check-update -q || true
            ;;
        arch|manjaro)
            pacman -Sy --noconfirm
            ;;
        *)
            print_warning "Unknown distribution, attempting apt-get..."
            apt-get update -qq || true
            ;;
    esac

    print_success "Package lists updated"
}

#########################################################
# Function: Install dependencies based on distro
#########################################################
install_dependencies() {
    print_info "Installing required packages..."

    local packages=(
        "hostapd"
        "dnsmasq"
        "iptables"
        "iproute2"
        "wireless-tools"
        "net-tools"
    )

    case $DISTRO in
        kali|debian|ubuntu)
            print_info "Using apt-get package manager..."
            DEBIAN_FRONTEND=noninteractive apt-get install -y -qq \
                hostapd \
                dnsmasq \
                iptables \
                iproute2 \
                wireless-tools \
                net-tools \
                iw
            ;;

        fedora|centos|rhel)
            print_info "Using dnf/yum package manager..."
            dnf install -y -q \
                hostapd \
                dnsmasq \
                iptables \
                iproute \
                wireless-tools \
                net-tools \
                iw
            ;;

        arch|manjaro)
            print_info "Using pacman package manager..."
            pacman -S --noconfirm --needed \
                hostapd \
                dnsmasq \
                iptables \
                iproute2 \
                wireless_tools \
                net-tools \
                iw
            ;;

        *)
            print_warning "Unknown distribution"
            print_info "Attempting to install with apt-get..."
            apt-get install -y -qq \
                hostapd \
                dnsmasq \
                iptables \
                iproute2 \
                wireless-tools \
                net-tools \
                iw || print_error "Failed to install dependencies"
            ;;
    esac

    print_success "Dependencies installed"
}

#########################################################
# Function: Check wireless interface capability
#########################################################
check_wireless_capability() {
    print_info "Checking wireless interface capabilities..."

    # Find wireless interfaces
    local wireless_interfaces=$(iw dev | grep Interface | awk '{print $2}')

    if [ -z "$wireless_interfaces" ]; then
        print_warning "No wireless interfaces found"
        print_info "Please ensure your wireless adapter is connected"
        return 1
    fi

    echo -e "${GREEN}Found wireless interfaces:${NC}"
    for iface in $wireless_interfaces; do
        echo "  - $iface"

        # Check if interface supports AP mode
        if iw list | grep -A 10 "Supported interface modes" | grep -q "AP"; then
            print_success "Interface $iface supports AP mode"
        else
            print_warning "Interface $iface may not support AP mode"
        fi
    done

    return 0
}

#########################################################
# Function: Check kernel modules
#########################################################
check_kernel_modules() {
    print_info "Checking kernel modules..."

    local modules=("cfg80211" "mac80211")
    local missing_modules=()

    for module in "${modules[@]}"; do
        if lsmod | grep -q "^$module"; then
            print_success "Module $module is loaded"
        else
            print_warning "Module $module is not loaded"
            missing_modules+=("$module")
        fi
    done

    if [ ${#missing_modules[@]} -ne 0 ]; then
        print_info "Attempting to load missing modules..."
        for module in "${missing_modules[@]}"; do
            modprobe "$module" 2>/dev/null && print_success "Loaded $module" || print_warning "Failed to load $module"
        done
    fi
}

#########################################################
# Function: Verify installation
#########################################################
verify_installation() {
    print_info "Verifying installation..."

    local tools=("hostapd" "dnsmasq" "iptables" "ip" "iwconfig")
    local missing_tools=()

    for tool in "${tools[@]}"; do
        if command -v "$tool" &> /dev/null; then
            local version=$(
                case $tool in
                    hostapd) hostapd -v 2>&1 | head -n1 | awk '{print $2}' ;;
                    dnsmasq) dnsmasq -v 2>&1 | head -n1 | awk '{print $3}' ;;
                    iptables) iptables --version | awk '{print $2}' ;;
                    ip) ip -V 2>&1 | awk '{print $2}' ;;
                    iwconfig) iwconfig --version 2>&1 | grep version | awk '{print $4}' ;;
                esac
            )
            print_success "$tool installed ${version:+(version: $version)}"
        else
            missing_tools+=("$tool")
            print_error "$tool not found"
        fi
    done

    if [ ${#missing_tools[@]} -ne 0 ]; then
        print_error "Some tools are still missing: ${missing_tools[*]}"
        return 1
    fi

    print_success "All tools verified successfully"
    return 0
}

#########################################################
# Function: Create README
#########################################################
create_readme() {
    local script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    local readme_file="${script_dir}/README.md"

    print_info "Creating README.md..."

    cat > "$readme_file" <<'EOF'
# Evil Twin Access Point Setup

A modular and reproducible evil twin AP setup for defensive security testing and wireless security research.

## Description

This toolkit creates a rogue access point (evil twin) that mimics a legitimate wireless network. It's designed for:
- Wireless security testing
- Network penetration testing
- Security awareness demonstrations
- Educational purposes

**⚠️ LEGAL WARNING**: Only use this tool on networks you own or have explicit written permission to test.

## Features

- 🔧 Modular bash scripts with clear separation of concerns
- 📊 Verbose output with color-coded status messages
- 🔍 Real-time monitoring of connected clients
- 📝 Comprehensive logging (hostapd, dnsmasq, connections)
- 🌐 Automatic internet sharing through NAT
- 🔄 Automatic network interface discovery
- 🧹 Clean teardown with system restoration
- ✅ Dependency checking and installation

## Prerequisites

- Linux system (Kali, Debian, Ubuntu, etc.)
- Wireless adapter supporting AP mode
- Root/sudo privileges
- Ethernet connection for internet sharing (optional)

## Installation

### 1. Install Dependencies

```bash
sudo ./install_dependencies.sh
```

This will install:
- hostapd (AP software)
- dnsmasq (DHCP/DNS server)
- iptables (firewall/NAT)
- iproute2 (network configuration)
- wireless-tools (wireless utilities)

### 2. Configure Settings

Edit `hostapd.conf` to customize:
- SSID (network name)
- Channel
- Password (default: letitrain2)
- Interface (default: wlan0)

Edit `dnsmasq.conf` to customize:
- DHCP range
- Subnet
- DNS servers

## Usage

### Start Evil Twin AP

```bash
sudo ./start_evil_twin.sh
```

The script will:
1. Check dependencies and privileges
2. Discover internet interface automatically
3. Configure wireless interface (192.168.99.1)
4. Set up NAT and IP forwarding
5. Start DHCP/DNS server
6. Start access point
7. Begin monitoring connections

### Stop Evil Twin AP

```bash
sudo ./stop_evil_twin.sh
```

The script will:
1. Stop all services gracefully
2. Clear iptables rules
3. Reset network interfaces
4. Restore NetworkManager
5. Display session statistics

### Monitor Connections

```bash
# Watch connection log
tail -f logs/connections.log

# Watch DHCP assignments
tail -f logs/dnsmasq.log

# View hostapd status
tail -f logs/hostapd.log
```

## Configuration

### Network Settings

- **Subnet**: 192.168.99.0/24
- **AP IP**: 192.168.99.1
- **DHCP Range**: 192.168.99.10 - 192.168.99.250
- **Channel**: 6
- **Password**: letitrain2

### File Structure

```
evil_twin_ap/
├── hostapd.conf              # AP configuration
├── dnsmasq.conf              # DHCP/DNS configuration
├── start_evil_twin.sh        # Start script
├── stop_evil_twin.sh         # Stop script
├── install_dependencies.sh   # Dependency installer
├── README.md                 # This file
└── logs/                     # Created at runtime
    ├── hostapd.log          # AP logs
    ├── dnsmasq.log          # DHCP/DNS logs
    └── connections.log      # Client connection logs
```

## Troubleshooting

### Wireless adapter not supporting AP mode

```bash
# Check if your adapter supports AP mode
iw list | grep -A 10 "Supported interface modes"
```

Look for "AP" in the output. If not present, your adapter doesn't support AP mode.

### NetworkManager conflicts

The start script automatically stops NetworkManager. If issues persist:

```bash
sudo systemctl stop NetworkManager
sudo systemctl disable NetworkManager  # Temporarily
```

Remember to re-enable after testing:

```bash
sudo systemctl enable NetworkManager
sudo systemctl start NetworkManager
```

### Check logs

```bash
# View all logs
cat logs/hostapd.log
cat logs/dnsmasq.log
cat logs/connections.log
```

### Permission denied errors

Ensure you're running with sudo:

```bash
sudo ./start_evil_twin.sh
```

## Security Considerations

- This tool is for authorized testing only
- Always get written permission before testing
- Be aware of local laws regarding wireless security testing
- Use in controlled environments (e.g., test labs)
- Monitor and log all activities for accountability

## Legal Disclaimer

This tool is provided for educational and authorized security testing purposes only. Unauthorized access to computer networks is illegal. Users are solely responsible for ensuring compliance with applicable laws and regulations.

## Contributing

Contributions welcome! Please ensure any modifications:
- Maintain modular structure
- Include verbose logging
- Add appropriate error handling
- Update documentation

## License

For educational and authorized security testing purposes only.

---

**Remember**: With great power comes great responsibility. Use ethically and legally.
EOF

    print_success "README.md created at ${readme_file}"
}

#########################################################
# Function: Display final summary
#########################################################
display_summary() {
    echo ""
    echo -e "${GREEN}=========================================="
    echo "   Installation Complete!"
    echo -e "==========================================${NC}"
    echo ""
    echo -e "${BLUE}Installed packages:${NC}"
    echo "  ✓ hostapd"
    echo "  ✓ dnsmasq"
    echo "  ✓ iptables"
    echo "  ✓ iproute2"
    echo "  ✓ wireless-tools"
    echo "  ✓ net-tools"
    echo ""
    echo -e "${YELLOW}Next steps:${NC}"
    echo "  1. Edit hostapd.conf to customize SSID"
    echo "  2. Review dnsmasq.conf settings"
    echo "  3. Run: sudo ./start_evil_twin.sh"
    echo ""
    echo -e "${BLUE}Documentation:${NC}"
    echo "  Read README.md for detailed usage instructions"
    echo ""
    echo -e "${RED}⚠️  LEGAL WARNING:${NC}"
    echo "  Only use on networks you own or have written permission to test"
    echo ""
}

#########################################################
# Main execution
#########################################################
main() {
    print_banner

    check_root
    detect_distro
    update_package_lists
    install_dependencies
    check_kernel_modules
    verify_installation
    check_wireless_capability
    create_readme

    display_summary
}

# Run main function
main
