#!/bin/bash

# Custom PatchMon Agent with Remote Command Execution
# Version: 1.0.0

PATCHMON_SERVER="${PATCHMON_SERVER:-http://localhost:3001}"
CONFIG_FILE="/etc/patchmon/credentials"
API_VERSION="v1"

# Load Credentials
if [ -f "$CONFIG_FILE" ]; then
    source "$CONFIG_FILE"
elif [ -f "./credentials" ]; then
    source "./credentials"
else
    echo "Error: Credentials file not found at $CONFIG_FILE or ./credentials"
    exit 1
fi

if [[ -z "$API_ID" ]] || [[ -z "$API_KEY" ]]; then
    echo "Error: API_ID and API_KEY must be in credentials file"
    exit 1
fi

echo "Starting PatchMon Custom Agent..."
echo "Server: $PATCHMON_SERVER"
echo "API ID: $API_ID"

while true; do
    # Poll for commands
    RESPONSE=$(curl -s -H "X-API-KEY: $API_KEY" "$PATCHMON_SERVER/api/$API_VERSION/commands/agent/$API_ID")
    
    # Check if we got a valid JSON array response (basic check)
    if [[ "$RESPONSE" == \[* ]]; then
        # Parse commands (using simple grep/sed for portability, assuming jq might not be there but recommended)
        # Using grep to find command IDs and content is fragile without jq.
        # Ideally, we should check if 'jq' is installed.
        
        if ! command -v jq &> /dev/null; then
            echo "Error: 'jq' is required for this agent. Please install it (apt-get install jq)."
            sleep 60
            continue
        fi

        # Process each pending command
        echo "$RESPONSE" | jq -c '.[]' | while read -r cmd_obj; do
            CMD_ID=$(echo "$cmd_obj" | jq -r '.id')
            CMD_TEXT=$(echo "$cmd_obj" | jq -r '.command')
            
            echo "Received command: $CMD_TEXT (ID: $CMD_ID)"
            
            # Execute Command
            OUTPUT=""
            STATUS="failed"
            
            case "$CMD_TEXT" in
                "update")
                    OUTPUT=$(apt-get update 2>&1)
                    EXIT_CODE=$?
                    ;;
                "upgrade")
                    OUTPUT=$(apt-get upgrade -y 2>&1)
                    EXIT_CODE=$?
                    ;;
                "remove_repo")
                     # Dangerous! Just an example or specific logic needed?
                     # User request was "Remove Repo", assuming removing itself or specific repo?
                     # For now, just a placeholder or removing patchmon repo if intended.
                     # "remove_repo" usually means removing the repo source list?
                     # Implementation: Remove /etc/apt/sources.list.d/patchmon.list
                     if [ -f "/etc/apt/sources.list.d/patchmon.list" ]; then
                        rm /etc/apt/sources.list.d/patchmon.list
                        OUTPUT="Removed patchmon.list"
                        EXIT_CODE=0
                     else
                        OUTPUT="Repo list not found"
                        EXIT_CODE=0 # Not an error per se
                     fi
                    ;;
                *)
                    OUTPUT="Unknown command: $CMD_TEXT"
                    EXIT_CODE=1
                    ;;
            esac
            
            if [ $EXIT_CODE -eq 0 ]; then
                STATUS="success"
            fi
            
            # Report Status
            # Escape output for JSON
             OUTPUT_JSON=$(echo "$OUTPUT" | jq -R '.')
             
             curl -s -X POST \
                -H "Content-Type: application/json" \
                -H "X-API-KEY: $API_KEY" \
                -d "{\"status\": \"$STATUS\", \"output\": $OUTPUT_JSON}" \
                "$PATCHMON_SERVER/api/$API_VERSION/commands/$CMD_ID/status" > /dev/null
                
             echo "Command executed. Status: $STATUS"
        done
    else
        # Echo only on error or if verbose
        # echo "No valid commands or error polling: $RESPONSE"
        :
    fi

    sleep 10
done
