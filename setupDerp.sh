#!/bin/bash

# Function to validate port numbers
validate_port() {
    if ! [[ $1 =~ ^[0-9]+$ ]] || [ $1 -lt 1 ] || [ $1 -gt 65535 ]; then
        echo "Invalid port: $1. Port must be a number between 1 and 65535."
        exit 1
    fi
}

# Prompt user for input
read -p "Enter DERP host (e.g., beta-derp): " DERP_HOST
if [[ -z "$DERP_HOST" ]]; then
    echo "DERP host cannot be empty."
    exit 1
fi

read -p "Enter DERP port (e.g., 1560): " DERP_PORT
validate_port $DERP_PORT

read -p "Enter STUN port (e.g., 1561): " STUN_PORT
validate_port $STUN_PORT

# Download and install Go
wget https://go.dev/dl/go1.22.3.linux-amd64.tar.gz
rm -rf /usr/local/go && tar -C /usr/local -xzf go1.22.3.linux-amd64.tar.gz
rm ./go1.22.3.linux-amd64.tar.gz
export PATH=$PATH:/usr/local/go/bin

# Verify Go installation
go version
GOROOT=$(go env | grep GOROOT)
GOPATH=$(go env | grep GOPATH)

if [ -z "$GOROOT" ]; then
    echo "GOROOT is not set. Exiting."
    exit 1
fi

if [ -z "$GOPATH" ]; then
    echo "GOPATH is not set. Exiting."
    exit 1
fi

# Install Tailscale
curl -fsSL https://tailscale.com/install.sh | sh
sudo tailscale up

# Setup certificates
mkdir -p ~/certdir && cd ~/certdir
openssl genpkey -algorithm RSA -out ${DERP_HOST}.key
openssl req -new -key ${DERP_HOST}.key -out ${DERP_HOST}.csr
openssl x509 -req -days 36500 -in ${DERP_HOST}.csr -signkey ${DERP_HOST}.key -out ${DERP_HOST}.crt -extfile <(printf "subjectAltName=DNS:${DERP_HOST}")

# Start derper service
~/go/bin/derper -c ~/.derper.key -a :${DERP_PORT} -http-port -1 -stun-port ${STUN_PORT} -hostname ${DERP_HOST} --certmode manual -certdir ~/certdir --verify-clients

# Create systemd service file for Tailscale derp service
echo "[Unit]
Description=Tailscale derp service
After=network.target

[Service]
ExecStart=/home/${USER}/go/bin/derper \
    -c /home/${USER}/.derper.key \
    -a :${DERP_PORT} -http-port -1 \
    -stun-port ${STUN_PORT} \
    -hostname ${DERP_HOST} \
    --certmode manual \
    -certdir /home/${USER}/certdir \
    --verify-clients
Restart=always
User=${USER}

[Install]
WantedBy=multi-user.target" | sudo tee /etc/systemd/system/tailscale-derp.service

# Reload Systemd configuration and start the service
sudo systemctl daemon-reload
sudo systemctl start tailscale-derp
sudo systemctl enable tailscale-derp
