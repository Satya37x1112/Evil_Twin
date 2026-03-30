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
