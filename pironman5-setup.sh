#!/bin/bash
# =============================================================
# setup-pironman5.sh
# Automates the software setup for the SunFounder Pironman 5 MAX
# case on a Raspberry Pi 5.
#
# Based on official SunFounder documentation:
# https://docs.sunfounder.com/projects/pironman5/en/latest/pironman5_max/set_up/set_up_rpi_os.html
#
# Usage: sudo bash setup-pironman5.sh
# =============================================================

# --- SAFETY: Stop the script immediately if any command fails ---
set -e

# --- COLOR CODES ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

print_info()    { echo -e "${GREEN}[INFO]${NC} $1"; }
print_warning() { echo -e "${YELLOW}[WARN]${NC} $1"; }
print_error()   { echo -e "${RED}[ERROR]${NC} $1"; }
print_step()    { echo -e "\n${CYAN}==>${NC} $1"; }

# --- CHECK: must be run as root ---
if [ "$EUID" -ne 0 ]; then
    print_error "Please run this script with sudo: sudo bash setup-pironman5.sh"
    exit 1
fi

# ============================================================
# HEADER
# ============================================================
clear
echo ""
echo "================================================"
echo "   Pironman 5 — Automated Software Setup"
echo "================================================"
echo ""
echo -e "  Based on official docs by ${CYAN}SunFounder${NC}"
echo -e "  ${CYAN}https://sunfounder.com${NC}"
echo ""
echo -e "  ${YELLOW}Tip: Press Ctrl+C at any time to quit${NC}"
echo "================================================"
echo ""
echo "  This script will:"
echo "    1) Ask which Pironman 5 model you have"
echo "    2) Update your system packages"
echo "    3) Install git and Python3 dependencies"
echo "    4) Clone the correct repo from SunFounder"
echo "    5) Run the installer"
echo "    6) Prompt you to reboot"
echo ""
read -r -p "Press Enter to begin, or Ctrl+C to cancel: "
echo ""

# ============================================================
# MODEL SELECTION
# Each model has its own GitHub repo and installs into its
# own folder. We set REPO_URL and REPO_DIR here so the rest
# of the script just uses those variables — no model-specific
# logic needed further down.
# ============================================================
echo "  Which Pironman 5 model do you have?"
echo -e "  Not sure? Visit: ${CYAN}https://docs.sunfounder.com/projects/pironman5/en/latest/index.html${NC}"
echo ""
echo "    1) Pironman 5          — single NVMe, aluminum case"
echo "    2) Pironman 5 MAX      — dual NVMe, black case, RGB tower fan"
echo "    3) Pironman 5 Mini     — compact case, single fan"
echo "    4) Pironman 5 Pro Max  — dual NVMe, 4.3\" touchscreen, camera, audio"
echo ""

while true; do
    read -r -p "Enter model number (1-4): " MODEL_NUM
    case "$MODEL_NUM" in
        1)
            MODEL_NAME="Pironman 5"
            REPO_URL="https://github.com/sunfounder/pironman5.git"
            REPO_DIR="pironman5"
            break
            ;;
        2)
            MODEL_NAME="Pironman 5 MAX"
            REPO_URL="https://github.com/sunfounder/pironman5-max.git"
            REPO_DIR="pironman5-max"
            break
            ;;
        3)
            MODEL_NAME="Pironman 5 Mini"
            REPO_URL="https://github.com/sunfounder/pironman5-mini.git"
            REPO_DIR="pironman5-mini"
            break
            ;;
        4)
            MODEL_NAME="Pironman 5 Pro Max"
            REPO_URL="https://github.com/sunfounder/pironman5-pro-max.git"
            REPO_DIR="pironman5-pro-max"
            print_warning "Note: Pro Max repo is unconfirmed — clone may fail if SunFounder"
            print_warning "has not published it yet. Check https://github.com/sunfounder"
            break
            ;;
        *)
            print_error "Invalid selection — enter a number between 1 and 4"
            ;;
    esac
done

echo ""
print_info "Model selected: ${YELLOW}${MODEL_NAME}${NC}"
print_info "Repository:     ${CYAN}${REPO_URL}${NC}"
echo ""

# ============================================================
# STEP 1 — SYSTEM UPDATE
# ============================================================
print_step "Step 1 of 4 — Updating system packages"
print_info "Running apt update and upgrade (this may take a few minutes)..."
apt update && apt upgrade -y
print_info "System packages up to date."

# ============================================================
# STEP 2 — INSTALL DEPENDENCIES
# ============================================================
print_step "Step 2 of 4 — Installing git and Python3 dependencies"
apt install git -y
apt install python3 python3-pip python3-setuptools -y
print_info "Dependencies installed."

# ============================================================
# STEP 3 — CLONE THE PIRONMAN5 REPO
# ============================================================
print_step "Step 3 of 4 — Cloning pironman5 repository from SunFounder"

# If the folder already exists from a previous attempt, remove it first
# so the clone doesn't fail with "directory already exists"
if [ -d "$HOME/$REPO_DIR" ]; then
    print_warning "Existing ~/${REPO_DIR} folder found — removing before re-cloning..."
    rm -rf "$HOME/$REPO_DIR"
fi

# --depth 1 = only download the latest snapshot, not the full git history
#             this makes it faster and saves disk space
cd "$HOME"
git clone "$REPO_URL" --depth 1
print_info "Repository cloned to ~/${REPO_DIR}"

# ============================================================
# STEP 4 — RUN THE INSTALLER
# ============================================================
print_step "Step 4 of 4 — Running the pironman5 installer"
print_info "Installing software for: ${YELLOW}${MODEL_NAME}${NC}"
echo ""

cd "$HOME/$REPO_DIR"
python3 install.py

print_info "Pironman5 installer finished."

# --- DETECT the Pi's current IP to build the dashboard URL ---
# We grab the IP from the default route interface so we get the
# "real" network IP, not the loopback (127.0.0.1)
CURRENT_IP=$(ip -4 route get 1.1.1.1 2>/dev/null | awk '{print $7; exit}')

# ============================================================
# WHAT WAS INSTALLED — summary for the user
# ============================================================
echo ""
echo "================================================"
echo -e "  ${GREEN}Setup complete!${NC}"
echo "================================================"
echo ""
echo "  What was installed:"
echo "    - pironman5.service (auto-starts on boot)"
echo "    - OLED display: CPU, RAM, temp, disk, IP"
echo "    - RGB LEDs: blue breathing mode by default"
echo "    - PWM fans: temperature-controlled speed"
echo ""

# ============================================================
# WEB DASHBOARD
# ============================================================
echo "------------------------------------------------"
echo -e "  ${CYAN}Web Dashboard${NC}"
echo "------------------------------------------------"
echo ""
echo "  After rebooting, open this URL in any browser"
echo "  on your network:"
echo ""
if [ -n "$CURRENT_IP" ]; then
    echo -e "    ${GREEN}http://${CURRENT_IP}:34001${NC}"
else
    echo -e "    ${GREEN}http://<your-pi-ip>:34001${NC}"
    print_warning "Could not detect IP — replace <your-pi-ip> with your Pi's IP"
fi
echo ""
echo "  The dashboard lets you:"
echo "    - Monitor CPU, RAM, temp, storage, network"
echo "    - Control RGB LEDs (color, brightness, style)"
echo "    - Configure fan speed and temperature thresholds"
echo "    - View live service logs"
echo ""

echo "------------------------------------------------"
echo "  Useful commands after reboot:"
echo -e "    ${CYAN}sudo systemctl status pironman5${NC}   — check service"
echo -e "    ${CYAN}sudo systemctl restart pironman5${NC}  — restart service"
echo -e "    ${CYAN}sudo pironman5 start${NC}              — manual start"
echo ""
echo "  Full documentation:"
echo -e "    ${CYAN}https://docs.sunfounder.com/projects/pironman5/en/latest${NC}"
echo ""

# ============================================================
# REBOOT PROMPT
# ============================================================
read -r -p "Reboot now to activate pironman5? (yes/no): " REBOOT_ANSWER

if [[ "$REBOOT_ANSWER" =~ ^[Yy][Ee][Ss]$|^[Yy]$ ]]; then
    print_info "Rebooting in 5 seconds... (Ctrl+C to cancel)"
    sleep 5
    reboot
else
    print_warning "Reboot skipped. Run 'sudo reboot' when ready to activate."
fi
