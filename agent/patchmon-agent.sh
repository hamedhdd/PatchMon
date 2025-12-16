#!/bin/bash

# Configuration
SERVER_URL="http://localhost:3000/api/v1"
# API_KEY="placeholder_key"

# OS Detection
if [ -f /etc/os-release ]; then
    . /etc/os-release
    OS_NAME=$PRETTY_NAME
else
    OS_NAME="Unknown Linux"
fi

HOSTNAME=$(hostname)

echo "PatchMon Agent"
echo "-------------"
echo "Host: $HOSTNAME"
echo "OS: $OS_NAME"

# Package Collection (Mock for now)
echo "Collecting package information..."

PACKAGES='[
    {"name": "openssl", "version": "1.1.1", "status": "installed"},
    {"name": "nginx", "version": "1.18.0", "status": "installed"}
]'

echo "Sending data to $SERVER_URL..."

# Payload
DATA="{\"hostname\": \"$HOSTNAME\", \"os\": \"$OS_NAME\", \"packages\": $PACKAGES}"

# Send to server (Check-in)
# curl -X POST -H "Content-Type: application/json" -d "$DATA" $SERVER_URL/agent/checkin
echo "Data sent successfully (Simulated check-in)."

# --- Command Polling Loop ---
echo "Checking for pending commands..."
RESPONSE=$(curl -s "$SERVER_URL/agent/commands?hostname=$HOSTNAME")
COMMAND_ID=$(echo $RESPONSE | grep -o '"id":[0-9]*' | head -1 | cut -d: -f2)
COMMAND_TYPE=$(echo $RESPONSE | grep -o '"type":"[^"]*"' | head -1 | cut -d'"' -f4)
COMMAND_PAYLOAD=$(echo $RESPONSE | grep -o '"payload":"[^"]*"' | head -1 | cut -d'"' -f4)

if [ ! -z "$COMMAND_ID" ]; then
    echo "Received command: $COMMAND_TYPE ($COMMAND_PAYLOAD)"
    
    OUTPUT=""
    STATUS="completed"

    if [ "$COMMAND_TYPE" == "update" ]; then
        echo "Running apt-get update..."
        # OUTPUT=$(apt-get update 2>&1)
        OUTPUT="Simulated apt-get update output"
    elif [ "$COMMAND_TYPE" == "upgrade" ]; then
        echo "Running apt-get upgrade..."
        # OUTPUT=$(apt-get upgrade -y 2>&1)
        OUTPUT="Simulated apt-get upgrade output"
    elif [ "$COMMAND_TYPE" == "remove_repo" ]; then
        echo "Removing repo $COMMAND_PAYLOAD..."
        # add-apt-repository --remove "$COMMAND_PAYLOAD" -y
        OUTPUT="Simulated repo removal: $COMMAND_PAYLOAD"
    else
        echo "Unknown command"
        STATUS="failed"
        OUTPUT="Unknown command type"
    fi

    # Report back
    curl -X POST -H "Content-Type: application/json" \
         -d "{\"status\": \"$STATUS\", \"output\": \"$OUTPUT\"}" \
         "$SERVER_URL/agent/commands/$COMMAND_ID"
    
    echo "Command execution reported."
else
    echo "No pending commands."
fi
