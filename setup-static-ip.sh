#!/bin/bash
# =============================================================
# setup-static-ip.sh
# Configures a static IP address using netplan (Ubuntu/Debian)
# Usage: sudo bash setup-static-ip.sh
# =============================================================

# --- SAFETY: Stop the script immediately if any command fails ---
set -e

# --- COLOR CODES for pretty terminal output ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'   # NC = "No Color" — resets color back to normal

# --- FUNCTION: print a colored message ---
# In bash, you define a function like: name() { ... }
# "$1" means "the first argument passed to this function"
print_info()    { echo -e "${GREEN}[INFO]${NC} $1"; }
print_warning() { echo -e "${YELLOW}[WARN]${NC} $1"; }
print_error()   { echo -e "${RED}[ERROR]${NC} $1"; }

# --- CHECK: make sure the script is being run as root (sudo) ---
# $EUID is a special variable that holds your user ID. Root = 0.
if [ "$EUID" -ne 0 ]; then
    print_error "Please run this script with sudo: sudo bash setup-static-ip.sh"
    exit 1   # exit 1 means "quit with an error"
fi

# ============================================================
# GATHER INPUT FROM THE USER
# "read -p" prints a prompt and waits for the user to type
# The value they type gets stored in the variable after -p "..."
# ============================================================

echo ""
echo "=============================="
echo "  Static IP Setup Script"
echo "=============================="
echo -e "  ${YELLOW}Tip: Press Ctrl+C at any time to quit${NC}"
echo "=============================="
echo ""

# --- BUILD a numbered list of interfaces ---
# "mapfile -t" reads lines from a command into an array, one element per line
# The array is called IFACES — bash arrays use () and are indexed from 0
mapfile -t IFACES < <(ip -o link show | awk '{print $2}' | sed 's/://')

print_info "Available network interfaces:"
# Loop through the array using an index
# ${#IFACES[@]} = the total count of elements in the array
for i in "${!IFACES[@]}"; do
    # i is 0-based, so we print i+1 to show humans a 1-based list
    echo "  $((i+1))) ${IFACES[$i]}"
done
echo ""

# --- LOOP until the user picks a valid number ---
while true; do
    read -p "Select interface number (1-${#IFACES[@]}): " IFACE_NUM

    # Check the input is a number and within range
    # The =~ operator matches against a regex; ^[0-9]+$ means "only digits"
    if [[ "$IFACE_NUM" =~ ^[0-9]+$ ]] && \
       [ "$IFACE_NUM" -ge 1 ] && \
       [ "$IFACE_NUM" -le "${#IFACES[@]}" ]; then
        # Arrays are 0-based so we subtract 1 from what the user typed
        IFACE="${IFACES[$((IFACE_NUM-1))]}"
        print_info "Selected interface: ${YELLOW}${IFACE}${NC}"
        break
    else
        print_error "Invalid selection — enter a number between 1 and ${#IFACES[@]}"
    fi
done

# --- SHOW the current IP on that interface so the user knows what they're replacing ---
# "ip -4 addr show" gets IPv4 info for that interface
# "awk" scans each line; when it sees the word "inet" it prints the next field (the IP)
CURRENT_IP=$(ip -4 addr show "$IFACE" 2>/dev/null | awk '/inet / {print $2}')
if [ -n "$CURRENT_IP" ]; then
    # -n means "is this string NOT empty?"
    print_info "Current IP on ${IFACE}: ${YELLOW}${CURRENT_IP}${NC}"
    # Build suggested values from the current subnet
    # ${CURRENT_IP%.*} strips the last octet  → "192.168.10"
    # ${CURRENT_IP#*/} strips up to the slash → "24"
    SUGGESTED_IP="${CURRENT_IP%.*}.2/${CURRENT_IP#*/}"
    SUGGESTED_GW="${CURRENT_IP%.*}.1"
else
    print_warning "No current IP found on ${IFACE} (interface may be down or name is wrong)"
fi
echo ""

# --- LOOP until the user enters a valid IP with a prefix length ---
# "while true" loops forever until we explicitly "break" out of it
while true; do
    if [ -n "$CURRENT_IP" ]; then
        read -p "Enter static IP address with subnet (e.g. ${SUGGESTED_IP}): " IP_ADDR
    else
        read -p "Enter static IP address with subnet (e.g. 192.168.1.2/24): " IP_ADDR
    fi

    if [[ "$IP_ADDR" == */* ]]; then
        break   # Input is valid — exit the loop and continue the script
    else
        print_error "Missing prefix length — include the subnet mask (e.g. /24)"
    fi
done

if [ -n "$CURRENT_IP" ]; then
    read -p "Enter default gateway (e.g. ${SUGGESTED_GW}): "                 GATEWAY
else
    read -p "Enter default gateway (e.g. 192.168.1.1): "                     GATEWAY
fi
read -p "Enter primary DNS server (e.g. 8.8.8.8): "                     DNS

# --- SECONDARY DNS: optional — just press Enter to skip ---
# If the user hits Enter without typing, DNS2 will be empty
read -p "Enter secondary DNS server (press Enter to skip): "             DNS2
if [ -n "$DNS2" ]; then
    print_info "Using two DNS servers: ${DNS}, ${DNS2}"
else
    print_info "Using one DNS server: ${DNS}"
fi

# ============================================================
# SSH WARNING — always shown regardless of connection type
# ============================================================
echo ""
echo -e "${RED}╔══════════════════════════════════════════════════════╗${NC}"
echo -e "${RED}║                  ⚠  SSH WARNING                     ║${NC}"
echo -e "${RED}╠══════════════════════════════════════════════════════╣${NC}"
echo -e "${RED}║${NC} If you are connected via SSH, your session WILL     "
echo -e "${RED}║${NC} appear to ${YELLOW}freeze or disconnect${NC} once applied.         "
echo -e "${RED}║${NC} This is normal — the IP is changing.                "
echo -e "${RED}║${NC}                                                      "
echo -e "${RED}║${NC} After it disconnects, SSH into the new IP:           "
echo -e "${RED}║${NC}   ${GREEN}ssh user@${IP_ADDR%/*}${NC}"
echo -e "${RED}╚══════════════════════════════════════════════════════╝${NC}"
echo ""
read -r -p "I understand — press Enter to continue, or Ctrl+C to cancel: "
echo ""

# --- VALIDATE: make sure none of the inputs are empty ---
# -z means "is this string empty?"
if [ -z "$IFACE" ] || [ -z "$IP_ADDR" ] || [ -z "$GATEWAY" ] || [ -z "$DNS" ]; then
    print_error "All fields are required. Please run the script again."
    exit 1
fi

# --- FIND the netplan config file ---
# "ls" lists files, "head -1" takes just the first result
# This handles cases where the filename might differ (e.g. 00-installer-config.yaml)
NETPLAN_FILE=$(ls /etc/netplan/*.yaml 2>/dev/null | head -1)

# If no file was found, set a default filename to create
if [ -z "$NETPLAN_FILE" ]; then
    NETPLAN_FILE="/etc/netplan/01-static-ip.yaml"
    print_warning "No existing netplan file found. Creating: $NETPLAN_FILE"
fi

# --- BACKUP the existing netplan file (if it exists) ---
if [ -f "$NETPLAN_FILE" ]; then
    BACKUP="${NETPLAN_FILE}.bak"
    cp "$NETPLAN_FILE" "$BACKUP"
    print_info "Backed up existing config to: $BACKUP"
fi

# ============================================================
# WRITE THE NETPLAN YAML FILE
# "cat > file << EOF" is a "heredoc" — it writes everything
# between the two EOF markers directly into the file.
# The variables ($IFACE, $IP_ADDR etc.) get substituted in.
# YAML indentation is critical — do not change the spaces!
# ============================================================

print_info "Writing netplan config to: $NETPLAN_FILE"

# --- WRITE the YAML ---
# We use two separate heredocs depending on whether DNS2 was provided.
# This keeps the YAML indentation clean and readable.
if [ -n "$DNS2" ]; then
    cat > "$NETPLAN_FILE" << EOF
network:
  version: 2
  ethernets:
    ${IFACE}:
      dhcp4: no
      addresses:
        - ${IP_ADDR}
      nameservers:
        addresses:
          - ${DNS}
          - ${DNS2}
      routes:
        - to: default
          via: ${GATEWAY}
EOF
else
    cat > "$NETPLAN_FILE" << EOF
network:
  version: 2
  ethernets:
    ${IFACE}:
      dhcp4: no
      addresses:
        - ${IP_ADDR}
      nameservers:
        addresses:
          - ${DNS}
      routes:
        - to: default
          via: ${GATEWAY}
EOF
fi

# --- SHOW the user what was written ---
echo ""
print_info "Config written:"
cat "$NETPLAN_FILE"
echo ""

# --- APPLY the netplan configuration ---
print_info "Applying netplan configuration..."
netplan apply

print_info "Netplan applied successfully."
echo ""

# ============================================================
# REBOOT PROMPT
# "read -r -p" reads input; [[ ]] is a conditional test
# =~ is a "matches pattern" operator in bash
# ============================================================

read -r -p "Reboot now to apply changes? (yes/no): " REBOOT_ANSWER

if [[ "$REBOOT_ANSWER" =~ ^[Yy][Ee][Ss]$|^[Yy]$ ]]; then
    print_info "Rebooting in 5 seconds... (Ctrl+C to cancel)"
    sleep 5
    reboot
else
    print_warning "Reboot skipped. Please reboot manually: sudo reboot"
fi
