#!/bin/bash

# Function to print characters with delay
print_with_delay() {
    text="$1"
    delay="$2"
    for ((i=0; i<${#text}; i++)); do
        echo -n "${text:$i:1}"
        sleep $delay
    done
    echo
}

# Function to clean domain input (removes http://, https://, and trailing slashes/paths)
clean_domain_input() {
    local domain="$1"
    domain="${domain#http://}"
    domain="${domain#https://}"
    domain="${domain%%/*}"
    echo "$domain"
}

# Introduction animation
echo ""
echo ""
print_with_delay "tuic-installer by DEATHLINE | @NamelesGhoul (Enhanced Version) | @cranch_fur (TLS support)" 0.05
echo ""
echo ""

# Check for and install required packages
install_required_packages() {
    REQUIRED_PACKAGES=("curl" "jq" "openssl" "uuid-runtime" "socat" "wget" "cron" "qrencode")
    for pkg in "${REQUIRED_PACKAGES[@]}"; do
        if ! command -v $pkg &> /dev/null; then
            apt-get update > /dev/null 2>&1
            apt-get install -y $pkg > /dev/null 2>&1
        fi
    done
}

# Apply network tuning for maximum QUIC/UDP performance
tune_network() {
    echo "Applying network optimizations (BBR & UDP buffers)..."
    # Clean up previous entries to avoid duplication
    sed -i '/# TUIC Tuning/d' /etc/sysctl.conf
    sed -i '/net.core.default_qdisc=fq/d' /etc/sysctl.conf
    sed -i '/net.ipv4.tcp_congestion_control=bbr/d' /etc/sysctl.conf
    sed -i '/net.core.rmem_max=8388608/d' /etc/sysctl.conf
    sed -i '/net.core.wmem_max=8388608/d' /etc/sysctl.conf
    sed -i '/net.core.rmem_default=1048576/d' /etc/sysctl.conf
    sed -i '/net.core.wmem_default=1048576/d' /etc/sysctl.conf

    # Append new optimized parameters
    cat >> /etc/sysctl.conf <<EOF
# TUIC Tuning
net.core.default_qdisc=fq
net.ipv4.tcp_congestion_control=bbr
net.core.rmem_max=8388608
net.core.wmem_max=8388608
net.core.rmem_default=1048576
net.core.wmem_default=1048576
EOF
    sysctl -p > /dev/null 2>&1
}

# Function to safely remove acme.sh auto-renewal task if it was used
remove_acme_task() {
    if [ -f "/root/tuic/acme_domain.txt" ] && [ -f "$HOME/.acme.sh/acme.sh" ]; then
        domain_to_remove=$(cat /root/tuic/acme_domain.txt)
        echo "Removing acme.sh auto-renewal task for $domain_to_remove..."
        $HOME/.acme.sh/acme.sh --remove -d "$domain_to_remove" > /dev/null 2>&1
    fi
}

# Check if the directory /root/tuic already exists
if [ -d "/root/tuic" ]; then
    echo "tuic seems to be already installed."
    echo ""
    echo "Choose an option:"
    echo ""
    echo "1) Reinstall"
    echo ""
    echo "2) Modify"
    echo ""
    echo "3) Uninstall"
    echo ""
    read -p "Enter your choice: " choice

    case $choice in
        1)
            remove_acme_task
            rm -rf /root/tuic
            systemctl stop tuic
            pkill -f tuic-server
            systemctl disable tuic > /dev/null 2>&1
            rm /etc/systemd/system/tuic.service
            ;;
        2)
            cd /root/tuic
            current_port=$(jq -r '.server' config.json | cut -d':' -f2)
            current_uuid=$(jq -r '.users | keys[0]' config.json)
            current_password=$(jq -r ".users.\"$current_uuid\"" config.json)
            
            echo ""
            read -p "Enter a new port (or press enter to keep the current one [$current_port]): " new_port
            [ -z "$new_port" ] && new_port=$current_port
            echo ""
            read -p "Enter a new password (or press enter to keep the current one [$current_password]): " new_password
            [ -z "$new_password" ] && new_password=$current_password
            
            jq ".server = \"[::]:$new_port\"" config.json > temp.json && mv temp.json config.json
            jq ".users = {\"$current_uuid\":\"$new_password\"}" config.json > temp.json && mv temp.json config.json
            
            systemctl daemon-reload
            systemctl restart tuic
            
            public_ip=$(curl -s https://api.ipify.org | tr -d '\r\n ')
            
            cert_mode="insecure"
            [ -f "/root/tuic/cert_mode.txt" ] && cert_mode=$(cat /root/tuic/cert_mode.txt)
            saved_domain="bing.com"
            [ -f "/root/tuic/domain.txt" ] && saved_domain=$(cat /root/tuic/domain.txt)

            echo -e "\n--- Modified URLs ---"
            > /root/tuic/client_links.txt
            
            if [ "$cert_mode" = "secure" ]; then
                SECURE_URL="tuic://${current_uuid}:${new_password}@${saved_domain}:${new_port}/?congestion_control=bbr&alpn=h3,spdy/3.1&sni=${saved_domain}&udp_relay_mode=native&allow_insecure=0"
                SECURE_URL=$(echo "$SECURE_URL" | tr -d '\r\n\t ')
                
                echo -e "\nSecure URL (Valid TLS via Domain):"
                echo "$SECURE_URL"
                echo "$SECURE_URL" >> /root/tuic/client_links.txt
                echo -e "\nQR Code:"
                qrencode -t ANSIUTF8 "$SECURE_URL"
            fi
            
            INSECURE_URL="tuic://${current_uuid}:${new_password}@${public_ip}:${new_port}/?congestion_control=bbr&alpn=h3,spdy/3.1&sni=${saved_domain}&udp_relay_mode=native&allow_insecure=1"
            INSECURE_URL=$(echo "$INSECURE_URL" | tr -d '\r\n\t ')
            
            echo -e "\nDirect IP URL (AllowInsecure):"
            echo "$INSECURE_URL"
            echo "$INSECURE_URL" >> /root/tuic/client_links.txt
            echo -e "\nQR Code:"
            qrencode -t ANSIUTF8 "$INSECURE_URL"
            
            echo -e "\n[i] Links have been saved to: /root/tuic/client_links.txt"
            echo ""
            exit 0
            ;;
        3)
            remove_acme_task
            rm -rf /root/tuic
            systemctl stop tuic
            pkill -f tuic-server
            systemctl disable tuic > /dev/null 2>&1
            rm /etc/systemd/system/tuic.service
            echo "tuic uninstalled successfully!"
            echo ""
            exit 0
            ;;
        *)
            echo "Invalid choice."
            exit 1
            ;;
    esac
fi

# Install required packages and apply network tuning
install_required_packages
tune_network

# Detect the architecture of the server
detect_arch() {
    local arch=$(uname -m)
    case $arch in
        x86_64)
            echo "x86_64-unknown-linux-gnu"
            ;;
        i686)
            echo "i686-unknown-linux-gnu"
            ;;
        armv7l)
            echo "armv7-unknown-linux-gnueabi"
            ;;
        aarch64)
            echo "aarch64-unknown-linux-gnu"
            ;;
        *)
            echo "Unsupported architecture: $arch"
            exit 1
            ;;
    esac
}

server_arch=$(detect_arch)
latest_release_version=$(curl -s "https://api.github.com/repos/etjec4/tuic/releases/latest" | jq -r ".tag_name")

# Download the binary
mkdir -p /root/tuic
cd /root/tuic
download_url="https://github.com/etjec4/tuic/releases/download/$latest_release_version/$latest_release_version-$server_arch"
wget -O tuic-server -q "$download_url"
if [[ $? -ne 0 ]]; then
    echo "Failed to download the tuic binary."
    exit 1
fi
chmod 755 tuic-server

# Handle Certificates Selection
echo ""
echo "--- SSL Certificate Setup ---"
echo "1) Use existing certificate (e.g., from 3X-UI)"
echo "2) Generate new Let's Encrypt certificate (with auto-renewal task)"
echo "3) No certificate (Self-signed, AllowInsecure connections only)"
echo ""
read -p "Choose an option [1-3]: " cert_choice

CERT_MODE="insecure"

case $cert_choice in
    1)
        echo ""
        read -p "Enter absolute path to full-chain certificate (e.g., /root/cert/fullchain.cer): " CERT_PATH
        read -p "Enter absolute path to private key (e.g., /root/cert/www.mydomain.com.key): " KEY_PATH
        read -p "Enter the domain name / SNI (e.g., www.mydomain.com): " raw_sni
        SNI_NAME=$(clean_domain_input "$raw_sni")
        
        if [ -f "$CERT_PATH" ] && [ -f "$KEY_PATH" ]; then
            CERT_MODE="secure"
            echo "$SNI_NAME" > /root/tuic/domain.txt
            echo "secure" > /root/tuic/cert_mode.txt
            echo "Existing certificate configured successfully."
        else
            echo "Error: Certificate or key file not found. Falling back to self-signed (Option 3)."
            cert_choice=3
        fi
        ;;
    2)
        echo ""
        read -p "Enter your domain for Let's Encrypt: " raw_domain
        domain_name=$(clean_domain_input "$raw_domain")
        echo "Attempting to issue a certificate for $domain_name via acme.sh..."
        
        # Install acme.sh if not present
        if [ ! -f "$HOME/.acme.sh/acme.sh" ]; then
            curl -s https://get.acme.sh | sh -s email="admin@$domain_name"
        fi
        
        # Issue cert (requires port 80 to be free)
        $HOME/.acme.sh/acme.sh --issue --standalone -d "$domain_name" --force
        
        if [ $? -eq 0 ]; then
            # Install cert and setup auto-restart hook for TUIC upon renewal
            $HOME/.acme.sh/acme.sh --install-cert -d "$domain_name" \
                --key-file /root/tuic/server.key \
                --fullchain-file /root/tuic/server.crt \
                --reloadcmd "systemctl restart tuic"
                
            CERT_PATH="/root/tuic/server.crt"
            KEY_PATH="/root/tuic/server.key"
            SNI_NAME="$domain_name"
            CERT_MODE="secure"
            
            echo "$domain_name" > /root/tuic/domain.txt
            echo "$domain_name" > /root/tuic/acme_domain.txt
            echo "secure" > /root/tuic/cert_mode.txt
            echo "Successfully installed Let's Encrypt certificate and set up auto-renewal task!"
        else
            echo "Failed to obtain Let's Encrypt certificate. Port 80 might be in use. Falling back to self-signed."
            cert_choice=3
        fi
        ;;
esac

# Fallback or intentional self-signed generation
if [[ "$cert_choice" == "3" || "$cert_choice" != "1" && "$cert_choice" != "2" ]]; then
    echo "Creating self-signed certs for AllowInsecure connections..."
    openssl ecparam -genkey -name prime256v1 -out /root/tuic/ca.key
    openssl req -new -x509 -days 36500 -key /root/tuic/ca.key -out /root/tuic/ca.crt -subj "/CN=bing.com"
    CERT_PATH="/root/tuic/ca.crt"
    KEY_PATH="/root/tuic/ca.key"
    SNI_NAME="bing.com"
    CERT_MODE="insecure"
    echo "insecure" > /root/tuic/cert_mode.txt
    echo "bing.com" > /root/tuic/domain.txt
fi

# Prompt user for port and password
echo ""
read -p "Enter a port (or press enter for a random port between 10000 and 65000): " port
echo ""
[ -z "$port" ] && port=$((RANDOM % 55001 + 10000))

read -p "Enter a password (or press enter for a random password): " password
echo ""
[ -z "$password" ] && password=$(tr -dc 'a-zA-Z0-9' < /dev/urandom | fold -w 8 | head -n 1)

# Generate UUID
UUID=$(uuidgen)
if [ -z "$UUID" ]; then
    echo "Error: Failed to generate UUID."
    exit 1
fi

# Create config.json with optimized parameters
cat > config.json <<EOL
{
  "server": "[::]:$port",
  "users": {
    "$UUID": "$password"
  },
  "certificate": "$CERT_PATH",
  "private_key": "$KEY_PATH",
  "congestion_control": "bbr",
  "alpn": ["h3", "spdy/3.1"],
  "udp_relay_ipv6": true,
  "zero_rtt_handshake": true,
  "dual_stack": true,
  "auth_timeout": "3s",
  "task_negotiation_timeout": "3s",
  "max_idle_time": "30s",
  "max_external_packet_size": 1500,
  "gc_interval": "3s",
  "gc_lifetime": "15s",
  "log_level": "warn"
}
EOL

# Create a systemd service for tuic
cat > /etc/systemd/system/tuic.service <<EOL
[Unit]
Description=tuic service
Documentation=TUIC v5
After=network.target nss-lookup.target

[Service]
User=root
WorkingDirectory=/root/tuic
CapabilityBoundingSet=CAP_NET_ADMIN CAP_NET_BIND_SERVICE CAP_NET_RAW
AmbientCapabilities=CAP_NET_ADMIN CAP_NET_BIND_SERVICE CAP_NET_RAW
ExecStart=/root/tuic/tuic-server -c /root/tuic/config.json
Restart=on-failure
RestartSec=10
LimitNOFILE=infinity

[Install]
WantedBy=multi-user.target
EOL

# Reload systemd, enable and start tuic
systemctl daemon-reload
systemctl enable tuic > /dev/null 2>&1
systemctl start tuic

# Print final configurations and URLs
public_ip=$(curl -s https://api.ipify.org | tr -d '\r\n ')

echo -e "\n============================================="
echo "        TUIC v5 Installation Complete        "
echo "============================================="

> /root/tuic/client_links.txt

if [ "$CERT_MODE" = "secure" ]; then
    SECURE_URL="tuic://${UUID}:${password}@${SNI_NAME}:${port}/?congestion_control=bbr&alpn=h3,spdy/3.1&sni=${SNI_NAME}&udp_relay_mode=native&allow_insecure=0"
    SECURE_URL=$(echo "$SECURE_URL" | tr -d '\r\n\t ')
    
    echo -e "\n[+] Secure URL (Valid TLS via Domain):"
    echo "$SECURE_URL"
    echo "$SECURE_URL" >> /root/tuic/client_links.txt
    
    echo -e "\nScan this QR code in NekoBox / v2rayN:"
    qrencode -t ANSIUTF8 "$SECURE_URL"
fi

INSECURE_URL="tuic://${UUID}:${password}@${public_ip}:${port}/?congestion_control=bbr&alpn=h3,spdy/3.1&sni=${SNI_NAME}&udp_relay_mode=native&allow_insecure=1"
INSECURE_URL=$(echo "$INSECURE_URL" | tr -d '\r\n\t ')

echo -e "\n[+] Direct IP URL (AllowInsecure):"
if [ "$CERT_MODE" != "secure" ]; then
    echo -e "Configured without a valid domain. Connection requires AllowInsecure."
fi
echo "$INSECURE_URL"
echo "$INSECURE_URL" >> /root/tuic/client_links.txt

echo -e "\nScan this QR code in NekoBox / v2rayN:"
qrencode -t ANSIUTF8 "$INSECURE_URL"

echo -e "\n[i] Links have also been saved to: /root/tuic/client_links.txt"
echo -e "=============================================\n"