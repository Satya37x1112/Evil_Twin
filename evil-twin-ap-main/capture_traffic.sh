#!/bin/bash

#########################################################
# Evil Twin AP - Traffic Capture Script
# Purpose: Capture network traffic on the evil twin interface
# Usage: sudo ./capture_traffic.sh [options]
#########################################################

set -e  # Exit on error

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOSTAPD_CONF="${SCRIPT_DIR}/hostapd.conf"

# Read interface from hostapd.conf (can be overridden with -i flag)
WLAN_INTERFACE=$(grep "^interface=" "$HOSTAPD_CONF" 2>/dev/null | cut -d'=' -f2)
if [ -z "$WLAN_INTERFACE" ]; then
    WLAN_INTERFACE="wlan0"  # Fallback to default
fi

OUTPUT_DIR="${SCRIPT_DIR}/output"
PID_FILE="${SCRIPT_DIR}/.capture.pid"
CAPTURE_FILTER=""
ROTATE_SIZE="100"  # MB
MAX_FILES="10"

# Parse command line arguments
DURATION=""
CAPTURE_NAME=""
VERBOSE=false

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

print_stat() {
    echo -e "${CYAN}[STAT]${NC} $1"
}

print_banner() {
    echo -e "${GREEN}"
    echo "=========================================="
    echo "   Evil Twin AP - Traffic Capture"
    echo "=========================================="
    echo -e "${NC}"
}

#########################################################
# Function: Show usage
#########################################################
show_usage() {
    cat << EOF
Usage: sudo $0 [OPTIONS]

Capture network traffic on the evil twin wireless interface.

OPTIONS:
    -i, --interface <name>    Wireless interface to capture (default: wlan0)
    -d, --duration <seconds>  Capture duration in seconds (default: continuous)
    -n, --name <name>         Custom capture filename prefix (default: auto-generated)
    -f, --filter <filter>     BPF capture filter (e.g., "tcp port 80")
    -s, --size <MB>           Rotate files when size reaches MB (default: 100)
    -m, --max-files <num>     Maximum number of rotated files (default: 10)
    -v, --verbose             Show verbose packet statistics
    -h, --help                Show this help message

EXAMPLES:
    # Basic capture (continuous)
    sudo $0

    # Capture for 60 seconds
    sudo $0 -d 60

    # Capture only HTTP traffic
    sudo $0 -f "tcp port 80 or tcp port 443"

    # Capture with custom name and verbose output
    sudo $0 -n test_capture -v

    # Capture on specific interface with file rotation
    sudo $0 -i wlx98038eb494c2 -s 50 -m 20

OUTPUT:
    PCAP files saved to: ${OUTPUT_DIR}/
    Filename format: capture_YYYYMMDD_HHMMSS.pcap

NOTES:
    - Requires root/sudo privileges
    - Use Ctrl+C to stop capture gracefully
    - View captures with: wireshark <filename>.pcap
    - Analyze with: tcpdump -r <filename>.pcap

EOF
}

#########################################################
# Function: Parse command line arguments
#########################################################
parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            -i|--interface)
                WLAN_INTERFACE="$2"
                shift 2
                ;;
            -d|--duration)
                DURATION="$2"
                shift 2
                ;;
            -n|--name)
                CAPTURE_NAME="$2"
                shift 2
                ;;
            -f|--filter)
                CAPTURE_FILTER="$2"
                shift 2
                ;;
            -s|--size)
                ROTATE_SIZE="$2"
                shift 2
                ;;
            -m|--max-files)
                MAX_FILES="$2"
                shift 2
                ;;
            -v|--verbose)
                VERBOSE=true
                shift
                ;;
            -h|--help)
                show_usage
                exit 0
                ;;
            *)
                print_error "Unknown option: $1"
                show_usage
                exit 1
                ;;
        esac
    done
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
# Function: Check dependencies
#########################################################
check_dependencies() {
    print_info "Checking dependencies..."
    local missing_deps=()

    for cmd in tcpdump ip; do
        if ! command -v "$cmd" &> /dev/null; then
            missing_deps+=("$cmd")
        fi
    done

    if [ ${#missing_deps[@]} -ne 0 ]; then
        print_error "Missing dependencies: ${missing_deps[*]}"
        print_info "Install with: apt-get install tcpdump iproute2"
        exit 1
    fi
    print_success "All dependencies found"
}

#########################################################
# Function: Check if interface exists and is up
#########################################################
check_interface() {
    print_info "Checking interface ${WLAN_INTERFACE}..."

    if ! ip link show "$WLAN_INTERFACE" &> /dev/null; then
        print_error "Interface ${WLAN_INTERFACE} not found"
        print_info "Available interfaces:"
        ip link show | grep -E "^[0-9]+:" | awk -F': ' '{print "  - " $2}'
        exit 1
    fi

    # Check if interface is up
    if ! ip link show "$WLAN_INTERFACE" | grep -q "state UP"; then
        print_warning "Interface ${WLAN_INTERFACE} is not UP"
        print_info "Is the evil twin AP running?"
    else
        print_success "Interface ${WLAN_INTERFACE} is UP"
    fi
}

#########################################################
# Function: Check if already capturing
#########################################################
check_already_running() {
    if [ -f "$PID_FILE" ]; then
        local old_pid=$(cat "$PID_FILE")
        if ps -p "$old_pid" > /dev/null 2>&1; then
            print_error "Capture already running (PID: ${old_pid})"
            print_info "Stop it first or check: ps -p ${old_pid}"
            exit 1
        else
            # Stale PID file
            rm "$PID_FILE"
        fi
    fi
}

#########################################################
# Function: Setup output directory
#########################################################
setup_output_dir() {
    print_info "Setting up output directory..."

    if [ ! -d "$OUTPUT_DIR" ]; then
        mkdir -p "$OUTPUT_DIR"
    fi

    # Set proper permissions
    chmod 755 "$OUTPUT_DIR"

    print_success "Output directory: ${OUTPUT_DIR}"
}

#########################################################
# Function: Generate capture filename
#########################################################
generate_filename() {
    local timestamp=$(date +"%Y%m%d_%H%M%S")

    if [ -n "$CAPTURE_NAME" ]; then
        echo "${OUTPUT_DIR}/${CAPTURE_NAME}_${timestamp}.pcap"
    else
        echo "${OUTPUT_DIR}/capture_${timestamp}.pcap"
    fi
}

#########################################################
# Function: Display capture configuration
#########################################################
display_config() {
    echo ""
    echo -e "${GREEN}=========================================="
    echo "   Capture Configuration"
    echo -e "==========================================${NC}"
    echo -e "${BLUE}Interface:${NC} ${WLAN_INTERFACE}"
    echo -e "${BLUE}Output Directory:${NC} ${OUTPUT_DIR}"
    echo -e "${BLUE}Output File:${NC} $(basename "$CAPTURE_FILE")"

    if [ -n "$CAPTURE_FILTER" ]; then
        echo -e "${BLUE}BPF Filter:${NC} ${CAPTURE_FILTER}"
    else
        echo -e "${BLUE}Filter:${NC} None (capturing all traffic)"
    fi

    if [ -n "$DURATION" ]; then
        echo -e "${BLUE}Duration:${NC} ${DURATION} seconds"
    else
        echo -e "${BLUE}Duration:${NC} Continuous (press Ctrl+C to stop)"
    fi

    echo -e "${BLUE}File Rotation:${NC} ${ROTATE_SIZE}MB (max ${MAX_FILES} files)"
    echo -e "${BLUE}Verbose Mode:${NC} ${VERBOSE}"
    echo ""
}

#########################################################
# Function: Start packet capture
#########################################################
start_capture() {
    print_info "Starting packet capture..."

    # Build tcpdump command
    local tcpdump_cmd="tcpdump -i ${WLAN_INTERFACE} -w ${CAPTURE_FILE}"

    # Add file rotation
    tcpdump_cmd+=" -W ${MAX_FILES} -C ${ROTATE_SIZE}"

    # Add capture filter if specified
    if [ -n "$CAPTURE_FILTER" ]; then
        tcpdump_cmd+=" ${CAPTURE_FILTER}"
    fi

    # Add verbose flag if enabled
    if [ "$VERBOSE" = true ]; then
        tcpdump_cmd+=" -v"
    else
        tcpdump_cmd+=" -q"
    fi

    # Add duration if specified
    if [ -n "$DURATION" ]; then
        tcpdump_cmd+=" -G ${DURATION} -W 1"
    fi

    print_success "Capture started"
    echo ""
    print_info "Press Ctrl+C to stop capture"
    echo ""

    # Save PID for cleanup
    echo "$$" > "$PID_FILE"

    # Start capture with live statistics
    if [ "$VERBOSE" = true ]; then
        $tcpdump_cmd &
        TCPDUMP_PID=$!
        echo "$TCPDUMP_PID" > "$PID_FILE"

        # Monitor capture statistics
        monitor_capture
    else
        # Run in foreground
        $tcpdump_cmd
    fi
}

#########################################################
# Function: Monitor capture statistics
#########################################################
monitor_capture() {
    local start_time=$(date +%s)
    local packet_count=0

    while kill -0 $TCPDUMP_PID 2>/dev/null; do
        sleep 5

        # Calculate runtime
        local current_time=$(date +%s)
        local runtime=$((current_time - start_time))

        # Get file size
        if [ -f "$CAPTURE_FILE" ]; then
            local file_size=$(du -h "$CAPTURE_FILE" | cut -f1)
            local packet_count=$(tcpdump -r "$CAPTURE_FILE" 2>/dev/null | wc -l)

            clear
            print_banner
            echo -e "${CYAN}╔════════════════════════════════════════╗${NC}"
            echo -e "${CYAN}║        Live Capture Statistics        ║${NC}"
            echo -e "${CYAN}╚════════════════════════════════════════╝${NC}"
            echo ""
            print_stat "Runtime: ${runtime} seconds"
            print_stat "File Size: ${file_size}"
            print_stat "Packets Captured: ${packet_count}"
            print_stat "Interface: ${WLAN_INTERFACE}"
            print_stat "Output: $(basename "$CAPTURE_FILE")"
            echo ""
            print_info "Press Ctrl+C to stop capture"
        fi
    done
}

#########################################################
# Function: Cleanup on exit
#########################################################
cleanup() {
    echo ""
    print_info "Stopping capture..."

    # Kill tcpdump if running
    if [ -f "$PID_FILE" ]; then
        local pid=$(cat "$PID_FILE")
        if ps -p "$pid" > /dev/null 2>&1; then
            kill "$pid" 2>/dev/null
            sleep 1
            # Force kill if still running
            kill -9 "$pid" 2>/dev/null || true
        fi
        rm "$PID_FILE"
    fi

    display_summary
    exit 0
}

#########################################################
# Function: Display capture summary
#########################################################
display_summary() {
    echo ""
    echo -e "${GREEN}=========================================="
    echo "   Capture Summary"
    echo -e "==========================================${NC}"

    if [ -f "$CAPTURE_FILE" ]; then
        local file_size=$(du -h "$CAPTURE_FILE" | cut -f1)
        local packet_count=$(tcpdump -r "$CAPTURE_FILE" 2>/dev/null | wc -l)

        print_success "Capture completed successfully"
        echo ""
        echo -e "${BLUE}Output File:${NC} ${CAPTURE_FILE}"
        echo -e "${BLUE}File Size:${NC} ${file_size}"
        echo -e "${BLUE}Packets Captured:${NC} ${packet_count}"
        echo ""
        echo -e "${YELLOW}Analysis Commands:${NC}"
        echo "  # View with Wireshark"
        echo "  wireshark ${CAPTURE_FILE}"
        echo ""
        echo "  # Analyze with tcpdump"
        echo "  tcpdump -r ${CAPTURE_FILE} -n"
        echo ""
        echo "  # Filter HTTP traffic"
        echo "  tcpdump -r ${CAPTURE_FILE} -A 'tcp port 80'"
        echo ""
        echo "  # View statistics"
        echo "  capinfos ${CAPTURE_FILE}"
        echo ""

        # List all capture files
        local capture_files=$(find "$OUTPUT_DIR" -name "*.pcap" -type f | wc -l)
        if [ "$capture_files" -gt 1 ]; then
            print_info "Total capture files in output directory: ${capture_files}"
            echo ""
            echo -e "${BLUE}Recent captures:${NC}"
            ls -lht "$OUTPUT_DIR"/*.pcap | head -5 | awk '{print "  " $9 " (" $5 ")"}'
        fi
    else
        print_warning "No capture file found"
    fi

    echo ""
}

#########################################################
# Main execution
#########################################################
main() {
    # Setup signal handlers
    trap cleanup SIGINT SIGTERM

    print_banner

    # Parse arguments
    parse_arguments "$@"

    check_root
    check_dependencies
    check_interface
    check_already_running
    setup_output_dir

    # Generate filename
    CAPTURE_FILE=$(generate_filename)

    display_config
    start_capture

    # If we get here, capture finished naturally (duration expired)
    cleanup
}

# Run main function
main "$@"
