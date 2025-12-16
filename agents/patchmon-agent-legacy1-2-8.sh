#!/bin/bash

# PatchMon Agent Script v1.2.8
# This script sends package update information to the PatchMon server using API credentials

# Configuration
PATCHMON_SERVER="${PATCHMON_SERVER:-http://localhost:3001}"
API_VERSION="v1"
AGENT_VERSION="1.2.8"
CONFIG_FILE="/etc/patchmon/agent.conf"
CREDENTIALS_FILE="/etc/patchmon/credentials"
LOG_FILE="/var/log/patchmon-agent.log"

# This placeholder will be dynamically replaced by the server when serving this
# script based on the "ignore SSL self-signed" setting. If set to -k, curl will
# ignore certificate validation. Otherwise, it will be empty for secure default.
CURL_FLAGS=""

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    # Try to write to log file, but don't fail if we can't
    if [[ -w "$(dirname "$LOG_FILE")" ]] 2>/dev/null; then
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "$LOG_FILE" 2>/dev/null
    fi
}

# Error handling
error() {
    echo -e "${RED}ERROR: $1${NC}" >&2
    log "ERROR: $1"
    exit 1
}

# Info logging (cleaner output - only stdout, no duplicate logging)
info() {
    echo -e "${BLUE}ℹ️  $1${NC}"
    log "INFO: $1"
}

# Success logging (cleaner output - only stdout, no duplicate logging)
success() {
    echo -e "${GREEN}✅ $1${NC}"
    log "SUCCESS: $1"
}

# Warning logging (cleaner output - only stdout, no duplicate logging)
warning() {
    echo -e "${YELLOW}⚠️  $1${NC}"
    log "WARNING: $1"
}

# Get or generate machine ID
get_machine_id() {
    # Try standard locations for machine-id
    if [[ -f /etc/machine-id ]]; then
        cat /etc/machine-id
    elif [[ -f /var/lib/dbus/machine-id ]]; then
        cat /var/lib/dbus/machine-id
    else
        # Fallback: generate from hardware UUID or hostname+MAC
        if command -v dmidecode &> /dev/null; then
            local uuid=$(dmidecode -s system-uuid 2>/dev/null | tr -d ' -' | tr '[:upper:]' '[:lower:]')
            if [[ -n "$uuid" && "$uuid" != "notpresent" ]]; then
                echo "$uuid"
                return
            fi
        fi
        # Last resort: hash hostname + primary MAC address
        local primary_mac=$(ip link show | grep -oP '(?<=link/ether\s)[0-9a-f:]+' | head -1 | tr -d ':')
        echo "$HOSTNAME-$primary_mac" | sha256sum | cut -d' ' -f1 | cut -c1-32
    fi
}

# Check if running as root
check_root() {
    if [[ $EUID -ne 0 ]]; then
        error "This script must be run as root"
    fi
}

# Verify system datetime and timezone
verify_datetime() {
    info "Verifying system datetime and timezone..."
    
    # Get current system time
    local system_time=$(date)
    local timezone="Unknown"
    
    # Try to get timezone with timeout protection
    if command -v timedatectl >/dev/null 2>&1; then
        timezone=$(timedatectl show --property=Timezone --value 2>/dev/null || echo "Unknown")
    fi
    
    # Log datetime info (non-blocking)
    log "System datetime check - time: $system_time, timezone: $timezone" 2>/dev/null || true
    
    # Simple check - just log the info, don't block execution
    if [[ "$timezone" == "Unknown" ]] || [[ -z "$timezone" ]]; then
        warning "System timezone not configured: $timezone"
        log "WARNING: System timezone not configured - timezone: $timezone" 2>/dev/null || true
    fi
    
    return 0
}

# Create necessary directories
setup_directories() {
    mkdir -p /etc/patchmon
    mkdir -p /var/log
    touch "$LOG_FILE"
    chmod 600 "$LOG_FILE"
}

# Load configuration
load_config() {
    if [[ -f "$CONFIG_FILE" ]]; then
        source "$CONFIG_FILE"
    fi
}

# Load API credentials
load_credentials() {
    if [[ ! -f "$CREDENTIALS_FILE" ]]; then
        error "Credentials file not found at $CREDENTIALS_FILE. Please configure API credentials first."
    fi
    
    source "$CREDENTIALS_FILE"
    
    if [[ -z "$API_ID" ]] || [[ -z "$API_KEY" ]]; then
        error "API_ID and API_KEY must be configured in $CREDENTIALS_FILE"
    fi
    
    # Use PATCHMON_URL from credentials if available, otherwise use default
    if [[ -n "$PATCHMON_URL" ]]; then
        PATCHMON_SERVER="$PATCHMON_URL"
    fi
}

# Configure API credentials
configure_credentials() {
    info "Setting up API credentials..."
    
    if [[ -z "$1" ]] || [[ -z "$2" ]]; then
        echo "Usage: $0 configure <API_ID> <API_KEY> [SERVER_URL]"
        echo ""
        echo "Example:"
        echo "  $0 configure patchmon_1a2b3c4d abcd1234567890abcdef1234567890abcdef1234567890abcdef1234567890"
        echo "  $0 configure patchmon_1a2b3c4d abcd1234567890abcdef1234567890abcdef1234567890abcdef1234567890 http://patchmon.example.com"
        echo ""
        echo "Contact your PatchMon administrator to get your API credentials."
        exit 1
    fi
    
    local api_id="$1"
    local api_key="$2"
    local server_url="${3:-$PATCHMON_SERVER}"
    
    # Validate API ID format
    if [[ ! "$api_id" =~ ^patchmon_[a-f0-9]{16}$ ]]; then
        error "Invalid API ID format. API ID should be in format: patchmon_xxxxxxxxxxxxxxxx"
    fi
    
    # Validate API Key format (64 hex characters)
    if [[ ! "$api_key" =~ ^[a-f0-9]{64}$ ]]; then
        error "Invalid API Key format. API Key should be 64 hexadecimal characters."
    fi
    
    # Validate server URL format
    if [[ ! "$server_url" =~ ^https?:// ]]; then
        error "Invalid server URL format. Must start with http:// or https://"
    fi
    
    # Create credentials file
    cat > "$CREDENTIALS_FILE" << EOF
# PatchMon API Credentials
# Generated on $(date)
PATCHMON_URL="$server_url"
API_ID="$api_id"
API_KEY="$api_key"
EOF
    
    chmod 600 "$CREDENTIALS_FILE"
    success "API credentials configured successfully"
    info "Credentials saved to: $CREDENTIALS_FILE"
    
    # Test credentials
    info "Testing API credentials..."
    test_credentials
}

# Test API credentials
test_credentials() {
    load_credentials
    
    local response=$(curl $CURL_FLAGS -X POST \
        -H "Content-Type: application/json" \
        -H "X-API-ID: $API_ID" \
        -H "X-API-KEY: $API_KEY" \
        "$PATCHMON_SERVER/api/$API_VERSION/hosts/ping")
    
    if [[ $? -eq 0 ]] && echo "$response" | grep -q "success"; then
        success "API credentials are valid"
        local hostname=$(echo "$response" | grep -o '"hostname":"[^"]*' | cut -d'"' -f4)
        if [[ -n "$hostname" ]]; then
            info "Connected as host: $hostname"
        fi
    else
        error "API credentials test failed: $response"
    fi
}

# Detect OS and version
detect_os() {
    if [[ -f /etc/os-release ]]; then
        source /etc/os-release
        OS_TYPE=$(echo "$ID" | tr '[:upper:]' '[:lower:]')
        OS_VERSION="$VERSION_ID"
        
        # Map OS variations to their appropriate categories
        case "$OS_TYPE" in
            "pop"|"linuxmint"|"elementary")
                OS_TYPE="ubuntu"
                ;;
            "opensuse"|"opensuse-leap"|"opensuse-tumbleweed")
                OS_TYPE="suse"
                ;;
            "almalinux")
                OS_TYPE="rhel"
                ;;
            "ol")
                # Keep Oracle Linux as 'ol' for proper frontend identification
                OS_TYPE="ol"
                ;;
            # Rocky Linux keeps its own identity for proper frontend display
        esac
        
    elif [[ -f /etc/redhat-release ]]; then
        if grep -q "CentOS" /etc/redhat-release; then
            OS_TYPE="centos"
        elif grep -q "Red Hat" /etc/redhat-release; then
            OS_TYPE="rhel"
        fi
        OS_VERSION=$(grep -oE '[0-9]+\.[0-9]+' /etc/redhat-release | head -1)
    else
        error "Unable to detect OS version"
    fi
    
    ARCHITECTURE=$(uname -m)
    HOSTNAME=$(hostname)
    IP_ADDRESS=$(hostname -I | awk '{print $1}')
}

# Get repository information based on OS
get_repository_info() {
    local repos_json="["
    local first=true
    
    case "$OS_TYPE" in
        "ubuntu"|"debian")
            get_apt_repositories repos_json first
            ;;
        "centos"|"rhel"|"fedora"|"ol"|"rocky")
            get_yum_repositories repos_json first
            ;;
        *)
            # Return empty array for unsupported OS
            ;;
    esac
    
    repos_json+="]"
    echo "$repos_json"
}

# Get repository info for APT-based systems
get_apt_repositories() {
    local -n repos_ref=$1
    local -n first_ref=$2
    
    # Parse traditional .list files
    local sources_files="/etc/apt/sources.list"
    if [[ -d "/etc/apt/sources.list.d" ]]; then
        sources_files="$sources_files $(find /etc/apt/sources.list.d -name '*.list' 2>/dev/null)"
    fi
    
    for file in $sources_files; do
        if [[ -f "$file" ]]; then
            while IFS= read -r line; do
                # Skip comments and empty lines
                if [[ "$line" =~ ^[[:space:]]*# ]] || [[ -z "$line" ]]; then
                    continue
                fi
                
                # Parse repository line (deb or deb-src)
                if [[ "$line" =~ ^[[:space:]]*(deb|deb-src)[[:space:]]+ ]]; then
                    # Clean the line and extract components
                    local clean_line=$(echo "$line" | xargs)
                    local repo_type=$(echo "$clean_line" | awk '{print $1}')
                    
                    # Handle modern APT format with options like [signed-by=...]
                    local url=""
                    local distribution=""
                    local components=""
                    
                    if [[ "$clean_line" =~ \[.*\] ]]; then
                        # Modern format: deb [options] URL distribution components
                        # Extract URL (first field after the options)
                        url=$(echo "$clean_line" | sed 's/deb[^[:space:]]* \[[^]]*\] //' | awk '{print $1}')
                        distribution=$(echo "$clean_line" | sed 's/deb[^[:space:]]* \[[^]]*\] //' | awk '{print $2}')
                        components=$(echo "$clean_line" | sed 's/deb[^[:space:]]* \[[^]]*\] [^[:space:]]* [^[:space:]]* //')
                    else
                        # Traditional format: deb URL distribution components
                        url=$(echo "$clean_line" | awk '{print $2}')
                        distribution=$(echo "$clean_line" | awk '{print $3}')
                        components=$(echo "$clean_line" | cut -d' ' -f4- | xargs)
                    fi
                    
                    # Skip if URL doesn't look like a valid URL
                    if [[ ! "$url" =~ ^https?:// ]] && [[ ! "$url" =~ ^ftp:// ]]; then
                        continue
                    fi
                    
                    # Skip if distribution is empty or looks malformed
                    if [[ -z "$distribution" ]] || [[ "$distribution" =~ \[.*\] ]]; then
                        continue
                    fi
                    
                    # Determine if repository uses HTTPS
                    local is_secure=false
                    if [[ "$url" =~ ^https:// ]]; then
                        is_secure=true
                    fi
                    
                    # Generate repository name from URL and distribution
                    local repo_name="$distribution"
                    
                    # Extract meaningful name from URL for better identification
                    if [[ "$url" =~ archive\.ubuntu\.com ]]; then
                        repo_name="ubuntu-$distribution"
                    elif [[ "$url" =~ security\.ubuntu\.com ]]; then
                        repo_name="ubuntu-$distribution-security"
                    elif [[ "$url" =~ deb\.nodesource\.com ]]; then
                        repo_name="nodesource-$distribution"
                    elif [[ "$url" =~ packagecloud\.io ]]; then
                        repo_name="packagecloud-$(echo "$url" | cut -d'/' -f4-5 | tr '/' '-')"
                    elif [[ "$url" =~ ppa\.launchpad ]]; then
                        repo_name="ppa-$(echo "$url" | cut -d'/' -f4-5 | tr '/' '-')"
                    elif [[ "$url" =~ packages\.microsoft\.com ]]; then
                        repo_name="microsoft-$(echo "$url" | cut -d'/' -f4-)"
                    elif [[ "$url" =~ download\.docker\.com ]]; then
                        repo_name="docker-$distribution"
                    else
                        # Fallback: use domain name + distribution
                        local domain=$(echo "$url" | cut -d'/' -f3 | cut -d':' -f1)
                        repo_name="$domain-$distribution"
                    fi
                    
                    # Add component suffix if relevant
                    if [[ "$components" =~ updates ]]; then
                        repo_name="$repo_name-updates"
                    elif [[ "$components" =~ security ]]; then
                        repo_name="$repo_name-security"
                    elif [[ "$components" =~ backports ]]; then
                        repo_name="$repo_name-backports"
                    fi
                    
                    if [[ "$first_ref" == true ]]; then
                        first_ref=false
                    else
                        repos_ref+=","
                    fi
                    
                    repos_ref+="{\"name\":\"$repo_name\",\"url\":\"$url\",\"distribution\":\"$distribution\",\"components\":\"$components\",\"repoType\":\"$repo_type\",\"isEnabled\":true,\"isSecure\":$is_secure}"
                fi
            done < "$file"
        fi
    done
    
    # Parse modern DEB822 format (.sources files)
    if [[ -d "/etc/apt/sources.list.d" ]]; then
        local sources_files_deb822=$(find /etc/apt/sources.list.d -name '*.sources' 2>/dev/null)
        for file in $sources_files_deb822; do
            if [[ -f "$file" ]]; then
                local deb822_result=$(parse_deb822_sources_simple "$file")
                if [[ -n "$deb822_result" ]]; then
                    if [[ "$first_ref" == true ]]; then
                        first_ref=false
                        repos_ref+="$deb822_result"
                    else
                        repos_ref+=",$deb822_result"
                    fi
                fi
            fi
        done
    fi
}

# Simple DEB822 parser that returns JSON string
parse_deb822_sources_simple() {
    local file=$1
    local result=""
    local enabled=""
    local types=""
    local uris=""
    local suites=""
    local components=""
    local name=""
    local first_entry=true
    
    while IFS= read -r line; do
        # Skip empty lines and comments
        if [[ -z "$line" ]] || [[ "$line" =~ ^[[:space:]]*# ]]; then
            continue
        fi
        
        # Parse key-value pairs
        if [[ "$line" =~ ^([^:]+):[[:space:]]*(.*)$ ]]; then
            local key="${BASH_REMATCH[1]}"
            local value="${BASH_REMATCH[2]}"
            
            case "$key" in
                "Enabled")
                    enabled="$value"
                    ;;
                "Types")
                    types="$value"
                    ;;
                "URIs")
                    uris="$value"
                    ;;
                "Suites")
                    suites="$value"
                    ;;
                "Components")
                    components="$value"
                    ;;
                "X-Repolib-Name")
                    name="$value"
                    ;;
            esac
        fi
        
        # Process repository entry when we hit a blank line
        if [[ -z "$line" ]] || [[ "$line" =~ ^[[:space:]]*$ ]]; then
            if [[ -n "$uris" && -n "$suites" && "$enabled" == "yes" ]]; then
                local entry_result=$(process_deb822_entry_simple "$name" "$types" "$uris" "$suites" "$components")
                if [[ -n "$entry_result" ]]; then
                    if [[ "$first_entry" == true ]]; then
                        first_entry=false
                        result="$entry_result"
                    else
                        result="$result,$entry_result"
                    fi
                fi
            fi
            # Reset variables for next entry
            enabled=""
            types=""
            uris=""
            suites=""
            components=""
            name=""
        fi
    done < "$file"
    
    # Process the last entry if file doesn't end with blank line
    if [[ -n "$uris" && -n "$suites" && "$enabled" == "yes" ]]; then
        local entry_result=$(process_deb822_entry_simple "$name" "$types" "$uris" "$suites" "$components")
        if [[ -n "$entry_result" ]]; then
            if [[ "$first_entry" == true ]]; then
                result="$entry_result"
            else
                result="$result,$entry_result"
            fi
        fi
    fi
    
    echo "$result"
}

# Process a DEB822 repository entry and return JSON
process_deb822_entry_simple() {
    local name=$1
    local types=$2
    local uris=$3
    local suites=$4
    local components=$5
    local result=""
    local first_entry=true
    
    # Handle multiple URIs
    for uri in $uris; do
        # Skip if URI doesn't look like a valid URL
        if [[ ! "$uri" =~ ^https?:// ]] && [[ ! "$uri" =~ ^ftp:// ]]; then
            continue
        fi
        
        # Handle multiple suites
        for suite in $suites; do
            # Skip if suite looks malformed
            if [[ -z "$suite" ]]; then
                continue
            fi
            
            # Determine if repository uses HTTPS
            local is_secure=false
            if [[ "$uri" =~ ^https:// ]]; then
                is_secure=true
            fi
            
            # Generate repository name
            local repo_name=""
            if [[ -n "$name" ]]; then
                repo_name=$(echo "$name" | tr ' ' '-' | tr '[:upper:]' '[:lower:]')
            else
                repo_name="$suite"
            fi
            
            # Extract meaningful name from URI for better identification
            if [[ "$uri" =~ apt\.pop-os\.org/ubuntu ]]; then
                repo_name="pop-os-ubuntu-$suite"
            elif [[ "$uri" =~ apt\.pop-os\.org/release ]]; then
                repo_name="pop-os-release-$suite"
            elif [[ "$uri" =~ apt\.pop-os\.org/proprietary ]]; then
                repo_name="pop-os-apps-$suite"
            elif [[ "$uri" =~ archive\.ubuntu\.com ]]; then
                repo_name="ubuntu-$suite"
            elif [[ "$uri" =~ security\.ubuntu\.com ]]; then
                repo_name="ubuntu-$suite-security"
            else
                # Fallback: use domain name + suite
                local domain=$(echo "$uri" | cut -d'/' -f3 | cut -d':' -f1)
                repo_name="$domain-$suite"
            fi
            
            # Add component suffix if relevant and not already included
            if [[ "$suite" != *"security"* && "$components" =~ security ]]; then
                repo_name="$repo_name-security"
            elif [[ "$suite" != *"updates"* && "$components" =~ updates ]]; then
                repo_name="$repo_name-updates"
            elif [[ "$suite" != *"backports"* && "$components" =~ backports ]]; then
                repo_name="$repo_name-backports"
            fi
            
            # Determine repo type (prefer deb over deb-src)
            local repo_type="deb"
            if [[ "$types" =~ deb-src ]] && [[ ! "$types" =~ ^deb[[:space:]] ]]; then
                repo_type="deb-src"
            fi
            
            local json_entry="{\"name\":\"$repo_name\",\"url\":\"$uri\",\"distribution\":\"$suite\",\"components\":\"$components\",\"repoType\":\"$repo_type\",\"isEnabled\":true,\"isSecure\":$is_secure}"
            
            if [[ "$first_entry" == true ]]; then
                first_entry=false
                result="$json_entry"
            else
                result="$result,$json_entry"
            fi
        done
    done
    
    echo "$result"
}

# Get repository info for YUM-based systems
get_yum_repositories() {
    local -n repos_ref=$1
    local -n first_ref=$2
    
    # Parse yum/dnf repository configuration
    local repo_info=""
    if command -v dnf >/dev/null 2>&1; then
        repo_info=$(dnf repolist all --verbose 2>/dev/null | grep -E "^Repo-id|^Repo-baseurl|^Repo-mirrors|^Repo-name|^Repo-status")
    elif command -v yum >/dev/null 2>&1; then
        repo_info=$(yum repolist all -v 2>/dev/null | grep -E "^Repo-id|^Repo-baseurl|^Repo-mirrors|^Repo-name|^Repo-status")
    fi
    
    if [[ -z "$repo_info" ]]; then
        return
    fi
    
    # Parse repository information
    local current_repo=""
    local repo_id=""
    local repo_name=""
    local repo_url=""
    local repo_mirrors=""
    local repo_status=""
    
    while IFS= read -r line; do
        if [[ "$line" =~ ^Repo-id[[:space:]]+:[[:space:]]+(.+)$ ]]; then
            # Process previous repository if we have one
            if [[ -n "$current_repo" ]]; then
                process_yum_repo repos_ref first_ref "$repo_id" "$repo_name" "$repo_url" "$repo_mirrors" "$repo_status"
            fi
            
            # Start new repository
            repo_id="${BASH_REMATCH[1]}"
            repo_name="$repo_id"
            repo_url=""
            repo_mirrors=""
            repo_status=""
            current_repo="$repo_id"
            
        elif [[ "$line" =~ ^Repo-name[[:space:]]+:[[:space:]]+(.+)$ ]]; then
            repo_name="${BASH_REMATCH[1]}"
            
        elif [[ "$line" =~ ^Repo-baseurl[[:space:]]+:[[:space:]]+(.+)$ ]]; then
            repo_url="${BASH_REMATCH[1]}"
            
        elif [[ "$line" =~ ^Repo-mirrors[[:space:]]+:[[:space:]]+(.+)$ ]]; then
            repo_mirrors="${BASH_REMATCH[1]}"
            
        elif [[ "$line" =~ ^Repo-status[[:space:]]+:[[:space:]]+(.+)$ ]]; then
            repo_status="${BASH_REMATCH[1]}"
        fi
    done <<< "$repo_info"
    
    # Process the last repository
    if [[ -n "$current_repo" ]]; then
        process_yum_repo repos_ref first_ref "$repo_id" "$repo_name" "$repo_url" "$repo_mirrors" "$repo_status"
    fi
}

# Process a single YUM repository and add it to the JSON
process_yum_repo() {
    local -n _repos_ref=$1
    local -n _first_ref=$2
    local repo_id="$3"
    local repo_name="$4"
    local repo_url="$5"
    local repo_mirrors="$6"
    local repo_status="$7"
    
    # Skip if we don't have essential info
    if [[ -z "$repo_id" ]]; then
        return
    fi
    
    # Determine if repository is enabled
    local is_enabled=false
    if [[ "$repo_status" == "enabled" ]]; then
        is_enabled=true
    fi
    
    # Use baseurl if available, otherwise use mirrors URL
    local final_url=""
    if [[ -n "$repo_url" ]]; then
        # Extract first URL if multiple are listed
        final_url=$(echo "$repo_url" | head -n 1 | awk '{print $1}')
    elif [[ -n "$repo_mirrors" ]]; then
        final_url="$repo_mirrors"
    fi
    
    # Skip if we don't have any URL
    if [[ -z "$final_url" ]]; then
        return
    fi
    
    # Determine if repository uses HTTPS
    local is_secure=false
    if [[ "$final_url" =~ ^https:// ]]; then
        is_secure=true
    fi
    
    # Generate repository name if not provided
    if [[ -z "$repo_name" ]]; then
        repo_name="$repo_id"
    fi
    
    # Clean up repository name and URL - escape quotes and backslashes
    repo_name=$(echo "$repo_name" | sed 's/\\/\\\\/g' | sed 's/"/\\"/g')
    final_url=$(echo "$final_url" | sed 's/\\/\\\\/g' | sed 's/"/\\"/g')
    
    # Add to JSON
    if [[ "$_first_ref" == true ]]; then
        _first_ref=false
    else
        _repos_ref+=","
    fi
    
    _repos_ref+="{\"name\":\"$repo_name\",\"url\":\"$final_url\",\"distribution\":\"$OS_VERSION\",\"components\":\"main\",\"repoType\":\"rpm\",\"isEnabled\":$is_enabled,\"isSecure\":$is_secure}"
}

# Get package information based on OS
get_package_info() {
    local packages_json="["
    local first=true
    
    case "$OS_TYPE" in
        "ubuntu"|"debian")
            get_apt_packages packages_json first
            ;;
        "centos"|"rhel"|"fedora"|"ol"|"rocky")
            get_yum_packages packages_json first
            ;;
        *)
            warning "Unsupported OS type: $OS_TYPE - returning empty package list"
            ;;
    esac
    
    packages_json+="]"
    echo "$packages_json"
}

# Get package info for APT-based systems
get_apt_packages() {
    local -n packages_ref=$1
    local -n first_ref=$2
    
    # Update package lists with retry logic for lock conflicts
    local retry_count=0
    local max_retries=3
    local retry_delay=5
    
    while [[ $retry_count -lt $max_retries ]]; do
        if apt-get update -qq 2>/dev/null; then
            break
        else
            retry_count=$((retry_count + 1))
            if [[ $retry_count -lt $max_retries ]]; then
                warning "APT lock detected, retrying in ${retry_delay} seconds... (attempt $retry_count/$max_retries)"
                sleep $retry_delay
            else
                warning "APT lock persists after $max_retries attempts, continuing without update..."
            fi
        fi
    done
    
    # Determine upgradable packages using apt-get simulation (compatible with Ubuntu 18.04)
    # Example line format:
    # Inst bash [4.4.18-2ubuntu1] (4.4.18-2ubuntu1.2 Ubuntu:18.04/bionic-updates [amd64])
    local upgradable_sim=$(apt-get -s -o Debug::NoLocking=1 upgrade 2>/dev/null | grep "^Inst ")
    
    while IFS= read -r line; do
        # Extract package name, current version (in brackets), and available version (first token inside parentheses)
        if [[ "$line" =~ ^Inst[[:space:]]+([^[:space:]]+)[[:space:]]+\[([^\]]+)\][[:space:]]+\(([^[:space:]]+) ]]; then
            local package_name="${BASH_REMATCH[1]}"
            local current_version="${BASH_REMATCH[2]}"
            local available_version="${BASH_REMATCH[3]}"
            local is_security_update=false
            
            # Mark as security update if the line references a security pocket
            if echo "$line" | grep -qiE "(-|/)security"; then
                is_security_update=true
            fi
            
            # Escape JSON special characters in package data
            package_name=$(echo "$package_name" | sed 's/"/\\"/g' | sed 's/\\/\\\\/g')
            current_version=$(echo "$current_version" | sed 's/"/\\"/g' | sed 's/\\/\\\\/g')
            available_version=$(echo "$available_version" | sed 's/"/\\"/g' | sed 's/\\/\\\\/g')
            
            if [[ "$first_ref" == true ]]; then
                first_ref=false
            else
                packages_ref+="," 
            fi
            
            packages_ref+="{\"name\":\"$package_name\",\"currentVersion\":\"$current_version\",\"availableVersion\":\"$available_version\",\"needsUpdate\":true,\"isSecurityUpdate\":$is_security_update}"
        fi
    done <<< "$upgradable_sim"
    
    # Get installed packages that are up to date
    local installed=$(dpkg-query -W -f='${Package} ${Version}\n')
    
    while IFS=' ' read -r package_name version; do
        if [[ -n "$package_name" && -n "$version" ]]; then
            # Check if this package is not in the upgrade list
            if ! echo "$upgradable_sim" | grep -q "^Inst $package_name "; then
                # Escape JSON special characters in package data
                package_name=$(echo "$package_name" | sed 's/"/\\"/g' | sed 's/\\/\\\\/g')
                version=$(echo "$version" | sed 's/"/\\"/g' | sed 's/\\/\\\\/g')
                
                if [[ "$first_ref" == true ]]; then
                    first_ref=false
                else
                    packages_ref+=","
                fi
                
                packages_ref+="{\"name\":\"$package_name\",\"currentVersion\":\"$version\",\"needsUpdate\":false,\"isSecurityUpdate\":false}"
            fi
        fi
    done <<< "$installed"
}

# Get package info for YUM/DNF-based systems
get_yum_packages() {
    local -n packages_ref=$1
    local -n first_ref=$2
    
    local package_manager="yum"
    if command -v dnf &> /dev/null; then
        package_manager="dnf"
    fi
    
    # Get upgradable packages
    local upgradable=$($package_manager check-update 2>/dev/null | grep -v "^$" | grep -v "^Loaded" | grep -v "^Last metadata" | grep -v "^Security" | tail -n +2)
    
    while IFS= read -r line; do
        # Skip empty lines and lines with special characters
        [[ -z "$line" ]] && continue
        [[ "$line" =~ ^[[:space:]]*$ ]] && continue
        
        if [[ "$line" =~ ^([^[:space:]]+)[[:space:]]+([^[:space:]]+)[[:space:]]+([^[:space:]]+) ]]; then
            local package_name="${BASH_REMATCH[1]}"
            local available_version="${BASH_REMATCH[2]}"
            local repo="${BASH_REMATCH[3]}"
            
            # Sanitize package name and versions (remove any control characters)
            package_name=$(echo "$package_name" | tr -d '[:cntrl:]' | sed 's/[^a-zA-Z0-9._+-]//g')
            available_version=$(echo "$available_version" | tr -d '[:cntrl:]' | sed 's/[^a-zA-Z0-9._+-]//g')
            repo=$(echo "$repo" | tr -d '[:cntrl:]')
            
            # Skip if package name is empty after sanitization
            [[ -z "$package_name" ]] && continue
            
            # Get current version
            local current_version=$($package_manager list installed "$package_name" 2>/dev/null | grep "^$package_name" | awk '{print $2}' | tr -d '[:cntrl:]' | sed 's/[^a-zA-Z0-9._+-]//g')
            
            # Skip if we couldn't get current version
            [[ -z "$current_version" ]] && current_version="unknown"
            
            local is_security_update=false
            if echo "$repo" | grep -q "security"; then
                is_security_update=true
            fi
            
            if [[ "$first_ref" == true ]]; then
                first_ref=false
            else
                packages_ref+=","
            fi
            
            packages_ref+="{\"name\":\"$package_name\",\"currentVersion\":\"$current_version\",\"availableVersion\":\"$available_version\",\"needsUpdate\":true,\"isSecurityUpdate\":$is_security_update}"
        fi
    done <<< "$upgradable"
    
    # Get some installed packages that are up to date
    local installed=$($package_manager list installed 2>/dev/null | grep -v "^Loaded" | grep -v "^Installed")
    
    while IFS= read -r line; do
        # Skip empty lines
        [[ -z "$line" ]] && continue
        [[ "$line" =~ ^[[:space:]]*$ ]] && continue
        
        if [[ "$line" =~ ^([^[:space:]]+)[[:space:]]+([^[:space:]]+) ]]; then
            local package_name="${BASH_REMATCH[1]}"
            local version="${BASH_REMATCH[2]}"
            
            # Sanitize package name and version
            package_name=$(echo "$package_name" | tr -d '[:cntrl:]' | sed 's/[^a-zA-Z0-9._+-]//g')
            version=$(echo "$version" | tr -d '[:cntrl:]' | sed 's/[^a-zA-Z0-9._+-]//g')
            
            # Skip if package name is empty after sanitization
            [[ -z "$package_name" ]] && continue
            [[ -z "$version" ]] && version="unknown"
            
            # Check if this package is not in the upgrade list
            if ! echo "$upgradable" | grep -q "^$package_name "; then
                if [[ "$first_ref" == true ]]; then
                    first_ref=false
                else
                    packages_ref+=","
                fi
                
                packages_ref+="{\"name\":\"$package_name\",\"currentVersion\":\"$version\",\"needsUpdate\":false,\"isSecurityUpdate\":false}"
            fi
        fi
    done <<< "$installed"
}

# Get hardware information
get_hardware_info() {
    local cpu_model=""
    local cpu_cores=0
    local ram_installed=0
    local swap_size=0
    local disk_details="[]"
    
    # CPU Information
    if command -v lscpu >/dev/null 2>&1; then
        cpu_model=$(lscpu | grep "Model name" | cut -d':' -f2 | xargs)
        cpu_cores=$(lscpu | grep "^CPU(s):" | cut -d':' -f2 | xargs)
    elif [[ -f /proc/cpuinfo ]]; then
        cpu_model=$(grep "model name" /proc/cpuinfo | head -1 | cut -d':' -f2 | xargs)
        cpu_cores=$(grep -c "^processor" /proc/cpuinfo)
    fi
    
    # Memory Information
    if command -v free >/dev/null 2>&1; then
        # Use free -m to get MB, then convert to GB with decimal precision
        ram_installed=$(free -m | grep "^Mem:" | awk '{printf "%.2f", $2/1024}')
        swap_size=$(free -m | grep "^Swap:" | awk '{printf "%.2f", $2/1024}')
    elif [[ -f /proc/meminfo ]]; then
        # Convert KB to GB with decimal precision
        ram_installed=$(grep "MemTotal" /proc/meminfo | awk '{printf "%.2f", $2/1048576}')
        swap_size=$(grep "SwapTotal" /proc/meminfo | awk '{printf "%.2f", $2/1048576}')
    fi
    
    # Ensure minimum value of 0.01GB to prevent 0 values
    if (( $(echo "$ram_installed < 0.01" | bc -l) )); then
        ram_installed="0.01"
    fi
    if (( $(echo "$swap_size < 0" | bc -l) )); then
        swap_size="0"
    fi
    
    # Disk Information
    if command -v lsblk >/dev/null 2>&1; then
        disk_details=$(lsblk -J -o NAME,SIZE,TYPE,MOUNTPOINT | jq -c '[.blockdevices[] | select(.type == "disk") | {name: .name, size: .size, mountpoint: .mountpoint}]')
    elif command -v df >/dev/null 2>&1; then
        disk_details=$(df -h | grep -E "^/dev/" | awk '{print "{\"name\":\""$1"\",\"size\":\""$2"\",\"mountpoint\":\""$6"\"}"}' | jq -s .)
    fi
    
    echo "{\"cpuModel\":\"$cpu_model\",\"cpuCores\":$cpu_cores,\"ramInstalled\":$ram_installed,\"swapSize\":$swap_size,\"diskDetails\":$disk_details}"
}

# Get network information
get_network_info() {
    local gateway_ip=""
    local dns_servers="[]"
    local network_interfaces="[]"
    
    # Gateway IP
    if command -v ip >/dev/null 2>&1; then
        gateway_ip=$(ip route | grep default | head -1 | awk '{print $3}')
    elif command -v route >/dev/null 2>&1; then
        gateway_ip=$(route -n | grep '^0.0.0.0' | head -1 | awk '{print $2}')
    fi
    
    # DNS Servers
    if [[ -f /etc/resolv.conf ]]; then
        dns_servers=$(grep "nameserver" /etc/resolv.conf | awk '{print $2}' | jq -R . | jq -s .)
    fi
    
    # Network Interfaces
    if command -v ip >/dev/null 2>&1; then
        network_interfaces=$(ip -j addr show | jq -c '[.[] | {name: .ifname, type: .link_type, addresses: [.addr_info[]? | {address: .local, family: .family}]}]')
    elif command -v ifconfig >/dev/null 2>&1; then
        network_interfaces=$(ifconfig -a | grep -E "^[a-zA-Z]" | awk '{print $1}' | jq -R . | jq -s .)
    fi
    
    echo "{\"gatewayIp\":\"$gateway_ip\",\"dnsServers\":$dns_servers,\"networkInterfaces\":$network_interfaces}"
}

# Get system information
get_system_info() {
    local kernel_version=""
    local selinux_status=""
    local system_uptime=""
    local load_average="[]"
    
    # Kernel Version
    if [[ -f /proc/version ]]; then
        kernel_version=$(cat /proc/version | awk '{print $3}')
    elif command -v uname >/dev/null 2>&1; then
        kernel_version=$(uname -r)
    fi
    
    # SELinux Status
    if command -v getenforce >/dev/null 2>&1; then
        selinux_status=$(getenforce 2>/dev/null | tr '[:upper:]' '[:lower:]')
        # Map "enforcing" to "enabled" for server validation
        if [[ "$selinux_status" == "enforcing" ]]; then
            selinux_status="enabled"
        fi
    elif [[ -f /etc/selinux/config ]]; then
        selinux_status=$(grep "^SELINUX=" /etc/selinux/config | cut -d'=' -f2 | tr '[:upper:]' '[:lower:]')
        # Map "enforcing" to "enabled" for server validation
        if [[ "$selinux_status" == "enforcing" ]]; then
            selinux_status="enabled"
        fi
    else
        selinux_status="disabled"
    fi
    
    # System Uptime
    if [[ -f /proc/uptime ]]; then
        local uptime_seconds=$(cat /proc/uptime | awk '{print int($1)}')
        local days=$((uptime_seconds / 86400))
        local hours=$(((uptime_seconds % 86400) / 3600))
        local minutes=$(((uptime_seconds % 3600) / 60))
        system_uptime="${days}d ${hours}h ${minutes}m"
    elif command -v uptime >/dev/null 2>&1; then
        system_uptime=$(uptime | awk -F'up ' '{print $2}' | awk -F', load' '{print $1}')
    fi
    
    # Load Average
    if [[ -f /proc/loadavg ]]; then
        load_average=$(cat /proc/loadavg | awk '{print "["$1","$2","$3"]"}')
    elif command -v uptime >/dev/null 2>&1; then
        load_average=$(uptime | awk -F'load average: ' '{print "["$2"]"}' | tr -d ' ')
    fi
    
    echo "{\"kernelVersion\":\"$kernel_version\",\"selinuxStatus\":\"$selinux_status\",\"systemUptime\":\"$system_uptime\",\"loadAverage\":$load_average}"
}

# Send package update to server
send_update() {
    load_credentials
    
    # Track execution start time
    local start_time=$(date +%s.%N)
    
    # Verify datetime before proceeding
    if ! verify_datetime; then
        warning "Datetime verification failed, but continuing with update..."
    fi
    
    info "Collecting system information..."
    local packages_json=$(get_package_info)
    local repositories_json=$(get_repository_info)
    local hardware_json=$(get_hardware_info)
    local network_json=$(get_network_info)
    local system_json=$(get_system_info)
    
    # Validate JSON before sending
    if ! echo "$packages_json" | jq empty 2>/dev/null; then
        error "Invalid packages JSON generated: $packages_json"
    fi
    
    if ! echo "$repositories_json" | jq empty 2>/dev/null; then
        error "Invalid repositories JSON generated: $repositories_json"
    fi
    
    info "Sending update to PatchMon server..."
    
    # Merge all JSON objects into one
    local merged_json=$(echo "$hardware_json $network_json $system_json" | jq -s '.[0] * .[1] * .[2]')
    # Get machine ID
    local machine_id=$(get_machine_id)
    
    # Calculate execution time (in seconds with decimals)
    local end_time=$(date +%s.%N)
    local execution_time=$(echo "$end_time - $start_time" | bc)
    
    # Create the base payload and merge with system info
    local base_payload=$(cat <<EOF
{
    "packages": $packages_json,
    "repositories": $repositories_json,
    "osType": "$OS_TYPE",
    "osVersion": "$OS_VERSION",
    "hostname": "$HOSTNAME",
    "ip": "$IP_ADDRESS",
    "architecture": "$ARCHITECTURE",
    "agentVersion": "$AGENT_VERSION",
    "machineId": "$machine_id",
    "executionTime": $execution_time
}
EOF
)
    
    # Merge the base payload with the system information
    local payload=$(echo "$base_payload $merged_json" | jq -s '.[0] * .[1]')
    
    # Write payload to temporary file to avoid "Argument list too long" error
    local temp_payload_file=$(mktemp)
    echo "$payload" > "$temp_payload_file"
    
    # Debug: Show payload size
    local payload_size=$(wc -c < "$temp_payload_file")
    echo -e "${BLUE}ℹ️  📊 Payload size: $payload_size bytes${NC}"
    
    local response=$(curl $CURL_FLAGS -X POST \
        -H "Content-Type: application/json" \
        -H "X-API-ID: $API_ID" \
        -H "X-API-KEY: $API_KEY" \
        -d @"$temp_payload_file" \
        "$PATCHMON_SERVER/api/$API_VERSION/hosts/update" 2>&1)
    
    local curl_exit_code=$?
    
    # Clean up temporary file
    rm -f "$temp_payload_file"
    
    if [[ $curl_exit_code -eq 0 ]]; then
        if echo "$response" | grep -q "success"; then
            local packages_count=$(echo "$response" | grep -o '"packagesProcessed":[0-9]*' | cut -d':' -f2)
            success "Update sent successfully (${packages_count} packages processed)"
            
            # Check if auto-update is enabled and check for agent updates locally
            if check_auto_update_enabled; then
                info "Checking for agent updates..."
                if check_agent_update_needed; then
                    info "Agent update available, updating..."
                    if "$0" update-agent; then
                        success "Agent updated successfully"
                    else
                        warning "Agent update failed, but data was sent successfully"
                    fi
                else
                    info "Agent is up to date"
                fi
            fi
            
            # Automatically check if crontab needs updating based on server settings
            info "Checking crontab configuration..."
            "$0" update-crontab
            local crontab_exit_code=$?
            if [[ $crontab_exit_code -eq 0 ]]; then
                success "Crontab updated successfully"
            elif [[ $crontab_exit_code -eq 2 ]]; then
                # Already up to date - no additional message needed
                true
            else
                warning "Crontab update failed, but data was sent successfully"
            fi
        else
            error "Update failed: $response"
        fi
    else
        error "Failed to send update (curl exit code: $curl_exit_code): $response"
    fi
}

# Ping server to check connectivity
ping_server() {
    load_credentials
    
    local response=$(curl $CURL_FLAGS -X POST \
        -H "Content-Type: application/json" \
        -H "X-API-ID: $API_ID" \
        -H "X-API-KEY: $API_KEY" \
        "$PATCHMON_SERVER/api/$API_VERSION/hosts/ping")
    
    if [[ $? -eq 0 ]] && echo "$response" | grep -q "success"; then
        success "Ping successful"
        local hostname=$(echo "$response" | grep -o '"hostname":"[^"]*' | cut -d'"' -f4)
        if [[ -n "$hostname" ]]; then
            info "Connected as host: $hostname"
        fi
        
        # Check for crontab update instructions
        local should_update_crontab=$(echo "$response" | grep -o '"shouldUpdate":true' | cut -d':' -f2)
        if [[ "$should_update_crontab" == "true" ]]; then
            local message=$(echo "$response" | grep -o '"message":"[^"]*' | cut -d'"' -f4)
            local command=$(echo "$response" | grep -o '"command":"[^"]*' | cut -d'"' -f4)
            
            if [[ -n "$message" ]]; then
                info "$message"
            fi
            
            if [[ "$command" == "update-crontab" ]]; then
                info "Updating crontab with new interval..."
                "$0" update-crontab
                local crontab_exit_code=$?
                if [[ $crontab_exit_code -eq 0 ]]; then
                    success "Crontab updated successfully"
                elif [[ $crontab_exit_code -eq 2 ]]; then
                    # Already up to date - no additional message needed
                    true
                else
                    warning "Crontab update failed, but data was sent successfully"
                fi
            fi
        fi
    else
        error "Ping failed: $response"
    fi
}

# Check for agent updates
check_version() {
    load_credentials
    
    info "Checking for agent updates..."
    
    local response=$(curl $CURL_FLAGS -H "X-API-ID: $API_ID" -H "X-API-KEY: $API_KEY" -X GET "$PATCHMON_SERVER/api/$API_VERSION/hosts/agent/version")
    
    if [[ $? -eq 0 ]]; then
        local current_version=$(echo "$response" | grep -o '"currentVersion":"[^"]*' | cut -d'"' -f4)
        local download_url=$(echo "$response" | grep -o '"downloadUrl":"[^"]*' | cut -d'"' -f4)
        local release_notes=$(echo "$response" | grep -o '"releaseNotes":"[^"]*' | cut -d'"' -f4)
        
        if [[ -n "$current_version" ]]; then
            if [[ "$current_version" != "$AGENT_VERSION" ]]; then
                warning "Agent update available!"
                echo "  Current version: $AGENT_VERSION"
                echo "  Latest version: $current_version"
                if [[ -n "$release_notes" ]]; then
                    echo "  Release notes: $release_notes"
                fi
                echo "  Download URL: $download_url"
                echo ""
                echo "To update, run: $0 update-agent"
            else
                success "Agent is up to date (version $AGENT_VERSION)"
            fi
        else
            warning "Could not determine current version from server"
        fi
    else
        error "Failed to check for updates"
    fi
}

# Check if auto-update is enabled (both globally and for this host)
check_auto_update_enabled() {
    # Get settings from server using API credentials
    local response=$(curl $CURL_FLAGS -H "X-API-ID: $API_ID" -H "X-API-KEY: $API_KEY" -X GET "$PATCHMON_SERVER/api/$API_VERSION/hosts/settings" 2>/dev/null)
    if [[ $? -ne 0 ]]; then
        return 1
    fi
    
    # Check if both global and host auto-update are enabled
    local global_auto_update=$(echo "$response" | grep -o '"auto_update":true' | cut -d':' -f2)
    local host_auto_update=$(echo "$response" | grep -o '"host_auto_update":true' | cut -d':' -f2)
    
    if [[ "$global_auto_update" == "true" && "$host_auto_update" == "true" ]]; then
        return 0
    else
        return 1
    fi
}

# Check if agent update is needed (internal function for auto-update)
check_agent_update_needed() {
    # Get current agent timestamp
    local current_timestamp=0
    if [[ -f "$0" ]]; then
        current_timestamp=$(stat -c %Y "$0" 2>/dev/null || stat -f %m "$0" 2>/dev/null || echo "0")
    fi
    
    # Get server agent info using API credentials
    local response=$(curl $CURL_FLAGS -H "X-API-ID: $API_ID" -H "X-API-KEY: $API_KEY" -X GET "$PATCHMON_SERVER/api/$API_VERSION/hosts/agent/timestamp" 2>/dev/null)
    
    if [[ $? -eq 0 ]]; then
        local server_version=$(echo "$response" | grep -o '"version":"[^"]*' | cut -d'"' -f4)
        local server_timestamp=$(echo "$response" | grep -o '"timestamp":[0-9]*' | cut -d':' -f2)
        local server_exists=$(echo "$response" | grep -o '"exists":true' | cut -d':' -f2)
        
        if [[ "$server_exists" != "true" ]]; then
            return 1
        fi
        
        # Check if update is needed
        if [[ "$server_version" != "$AGENT_VERSION" ]]; then
            return 0  # Update needed due to version mismatch
        elif [[ "$server_timestamp" -gt "$current_timestamp" ]]; then
            return 0  # Update needed due to newer timestamp
        else
            return 1  # No update needed
        fi
    else
        return 1  # Failed to check
    fi
}

# Check for agent updates based on version and timestamp (interactive command)
check_agent_update() {
    load_credentials
    
    info "Checking for agent updates..."
    
    # Get current agent timestamp
    local current_timestamp=0
    if [[ -f "$0" ]]; then
        current_timestamp=$(stat -c %Y "$0" 2>/dev/null || stat -f %m "$0" 2>/dev/null || echo "0")
    fi
    
    # Get server agent info using API credentials
    local response=$(curl $CURL_FLAGS -H "X-API-ID: $API_ID" -H "X-API-KEY: $API_KEY" -X GET "$PATCHMON_SERVER/api/$API_VERSION/hosts/agent/timestamp")
    
    if [[ $? -eq 0 ]]; then
        local server_version=$(echo "$response" | grep -o '"version":"[^"]*' | cut -d'"' -f4)
        local server_timestamp=$(echo "$response" | grep -o '"timestamp":[0-9]*' | cut -d':' -f2)
        local server_exists=$(echo "$response" | grep -o '"exists":true' | cut -d':' -f2)
        
        if [[ "$server_exists" != "true" ]]; then
            warning "No agent script found on server"
            return 1
        fi
        
        info "Current agent version: $AGENT_VERSION (timestamp: $current_timestamp)"
        info "Server agent version: $server_version (timestamp: $server_timestamp)"
        
        # Check if update is needed
        if [[ "$server_version" != "$AGENT_VERSION" ]]; then
            info "Version mismatch detected - update needed"
            return 0
        elif [[ "$server_timestamp" -gt "$current_timestamp" ]]; then
            info "Server script is newer - update needed"
            return 0
        else
            info "Agent is up to date"
            return 1
        fi
    else
        error "Failed to check agent timestamp from server"
        return 1
    fi
}

# Update agent script
update_agent() {
    load_credentials
    
    info "Updating agent script..."
    
    local download_url="$PATCHMON_SERVER/api/$API_VERSION/hosts/agent/download"
    
    info "Downloading latest agent from: $download_url"
    
    # Clean up old backups (keep only last 3)
    ls -t "$0.backup."* 2>/dev/null | tail -n +4 | xargs -r rm -f
    
    # Create backup of current script
    local backup_file="$0.backup.$(date +%Y%m%d_%H%M%S)"
    cp "$0" "$backup_file"
    
    # Download new version using API credentials
    if curl $CURL_FLAGS -H "X-API-ID: $API_ID" -H "X-API-KEY: $API_KEY" -o "/tmp/patchmon-agent-new.sh" "$download_url"; then
        # Verify the downloaded script is valid
        if bash -n "/tmp/patchmon-agent-new.sh" 2>/dev/null; then
            # Replace current script
            mv "/tmp/patchmon-agent-new.sh" "$0"
            chmod +x "$0"
            success "Agent updated successfully"
            info "Backup saved as: $backup_file"
            
            # Get the new version number
            local new_version=$(grep '^AGENT_VERSION=' "$0" | cut -d'"' -f2)
            info "Updated to version: $new_version"
            
            # Automatically run update to send new information to PatchMon
            info "Sending updated information to PatchMon..."
            if "$0" update; then
                success "Successfully sent updated information to PatchMon"
            else
                warning "Failed to send updated information to PatchMon (this is not critical)"
            fi
        else
            error "Downloaded script is invalid"
            rm -f "/tmp/patchmon-agent-new.sh"
        fi
    else
        error "Failed to download new agent script"
    fi
}

# Update crontab with current policy
update_crontab() {
    load_credentials
    info "Updating crontab with current policy..."
    local response=$(curl $CURL_FLAGS -H "X-API-ID: $API_ID" -H "X-API-KEY: $API_KEY" -X GET "$PATCHMON_SERVER/api/$API_VERSION/settings/update-interval")
    if [[ $? -eq 0 ]]; then
        local update_interval=$(echo "$response" | grep -o '"updateInterval":[0-9]*' | cut -d':' -f2)
        # Fallback if not found
        if [[ -z "$update_interval" ]]; then
            update_interval=60
        fi
        # Normalize interval: 5-59 valid, otherwise snap to hour presets
        if [[ $update_interval -lt 5 ]]; then
            update_interval=5
        elif [[ $update_interval -gt 1440 ]]; then
            update_interval=1440
        fi
        if [[ -n "$update_interval" ]]; then
            # Generate the expected crontab entry
            local expected_crontab=""
            if [[ $update_interval -lt 60 ]]; then
                # Every N minutes (5-59)
                expected_crontab="*/$update_interval * * * * /usr/local/bin/patchmon-agent.sh update >/dev/null 2>&1"
            else
                # Hour-based schedules
                if [[ $update_interval -eq 60 ]]; then
                    # Hourly updates starting at current minute to spread load
                    local current_minute=$(date +%M)
                    expected_crontab="$current_minute * * * * /usr/local/bin/patchmon-agent.sh update >/dev/null 2>&1"
                else
                    # For 120, 180, 360, 720, 1440 -> every H hours at minute 0
                    local hours=$((update_interval / 60))
                    expected_crontab="0 */$hours * * * /usr/local/bin/patchmon-agent.sh update >/dev/null 2>&1"
                fi
            fi
            
            # Get current crontab (without patchmon entries)
            local current_crontab_without_patchmon=$(crontab -l 2>/dev/null | grep -v "/usr/local/bin/patchmon-agent.sh update" || true)
            local current_patchmon_entry=$(crontab -l 2>/dev/null | grep "/usr/local/bin/patchmon-agent.sh update" | head -1)
            
            # Check if crontab needs updating
            if [[ "$current_patchmon_entry" == "$expected_crontab" ]]; then
                info "Crontab is already up to date (interval: $update_interval minutes)"
                return 2  # Special return code for "already up to date"
            fi
            
            info "Setting update interval to $update_interval minutes"
            
            # Combine existing cron (without patchmon entries) + new patchmon entry
            {
                if [[ -n "$current_crontab_without_patchmon" ]]; then
                    echo "$current_crontab_without_patchmon"
                fi
                echo "$expected_crontab"
            } | crontab -
            
            success "Crontab updated successfully (duplicates removed)"
        else
            error "Could not determine update interval from server"
        fi
    else
        error "Failed to get update interval policy"
    fi
}

# Show detailed system diagnostics
show_diagnostics() {
    info "PatchMon Agent Diagnostics v$AGENT_VERSION"
    echo ""
    
    # System information
    echo "=== System Information ==="
    echo "OS: $(uname -s)"
    echo "Architecture: $(uname -m)"
    echo "Kernel: $(uname -r)"
    echo "Hostname: $(hostname)"
    echo "Uptime: $(uptime -p 2>/dev/null || uptime)"
    echo ""
    
    # Agent information
    echo "=== Agent Information ==="
    echo "Version: $AGENT_VERSION"
    echo "Script Path: $0"
    echo "Config File: $CONFIG_FILE"
    echo "Credentials File: $CREDENTIALS_FILE"
    echo "Log File: $LOG_FILE"
    echo "Script Size: $(stat -c%s "$0" 2>/dev/null || echo "Unknown") bytes"
    echo "Last Modified: $(stat -c%y "$0" 2>/dev/null || echo "Unknown")"
    echo ""
    
    # Configuration
    if [[ -f "$CONFIG_FILE" ]]; then
        echo "=== Configuration ==="
        cat "$CONFIG_FILE"
        echo ""
    else
        echo "=== Configuration ==="
        echo "No configuration file found at $CONFIG_FILE"
        echo ""
    fi
    
    # Credentials status
    echo "=== Credentials Status ==="
    if [[ -f "$CREDENTIALS_FILE" ]]; then
        echo "Credentials file exists: Yes"
        echo "File size: $(stat -c%s "$CREDENTIALS_FILE" 2>/dev/null || echo "Unknown") bytes"
        echo "File permissions: $(stat -c%a "$CREDENTIALS_FILE" 2>/dev/null || echo "Unknown")"
    else
        echo "Credentials file exists: No"
    fi
    echo ""
    
    # Crontab status
    echo "=== Crontab Status ==="
    local crontab_entries=$(crontab -l 2>/dev/null | grep patchmon-agent || echo "None")
    if [[ "$crontab_entries" != "None" ]]; then
        echo "Crontab entries:"
        echo "$crontab_entries"
    else
        echo "No crontab entries found"
    fi
    echo ""
    
    # Network connectivity
    echo "=== Network Connectivity ==="
    if ping -c 1 -W 3 "$(echo "$PATCHMON_SERVER" | sed 's|http://||' | sed 's|https://||' | cut -d: -f1)" >/dev/null 2>&1; then
        echo "Server reachable: Yes"
    else
        echo "Server reachable: No"
    fi
    echo "Server URL: $PATCHMON_SERVER"
    echo ""
    
    # Recent logs
    echo "=== Recent Logs (last 10 lines) ==="
    if [[ -f "$LOG_FILE" ]]; then
        tail -10 "$LOG_FILE" 2>/dev/null || echo "Could not read log file"
    else
        echo "Log file does not exist"
    fi
}

# Show current configuration
show_config() {
    info "Current Configuration:"
    echo "  Server: ${PATCHMON_SERVER}"
    echo "  API Version: ${API_VERSION}"
    echo "  Agent Version: ${AGENT_VERSION}"
    echo "  Config File: ${CONFIG_FILE}"
    echo "  Credentials File: ${CREDENTIALS_FILE}"
    echo "  Log File: ${LOG_FILE}"
    
    if [[ -f "$CREDENTIALS_FILE" ]]; then
        source "$CREDENTIALS_FILE"
        echo "  API ID: ${API_ID}"
        echo "  API Key: ${API_KEY:0:8}..." # Show only first 8 characters
    else
        echo "  API Credentials: Not configured"
    fi
}

# Main function
main() {
    case "$1" in
        "configure")
            check_root
            setup_directories
            load_config
            configure_credentials "$2" "$3" "$4"
            ;;
        "test")
            check_root
            setup_directories
            load_config
            test_credentials
            ;;
        "update")
            check_root
            setup_directories
            load_config
            detect_os
            send_update
            ;;
        "ping")
            check_root
            setup_directories
            load_config
            ping_server
            ;;
        "config")
            load_config
            show_config
            ;;
        "check-version")
            check_root
            setup_directories
            load_config
            check_version
            ;;
        "check-agent-update")
            setup_directories
            load_config
            check_agent_update
            ;;
        "update-agent")
            check_root
            setup_directories
            load_config
            update_agent
            ;;
        "update-crontab")
            check_root
            setup_directories
            load_config
            update_crontab
            ;;
        "diagnostics")
            show_diagnostics
            ;;
        *)
            echo "PatchMon Agent v$AGENT_VERSION - API Credential Based"
            echo "Usage: $0 {configure|test|update|ping|config|check-version|check-agent-update|update-agent|update-crontab|diagnostics}"
            echo ""
            echo "Commands:"
            echo "  configure <API_ID> <API_KEY> [SERVER_URL] - Configure API credentials for this host"
            echo "  test                          - Test API credentials connectivity"
            echo "  update                        - Send package update information to server"
            echo "  ping                          - Test connectivity to server"
            echo "  config                        - Show current configuration"
            echo "  check-version                 - Check for agent updates"
            echo "  check-agent-update            - Check for agent updates using timestamp comparison"
            echo "  update-agent                  - Update agent to latest version"
            echo "  update-crontab                - Update crontab with current policy"
            echo "  diagnostics                   - Show detailed system diagnostics"
            echo ""
            echo "Setup Process:"
            echo "  1. Contact your PatchMon administrator to create a host entry"
            echo "  2. Run: $0 configure <API_ID> <API_KEY> [SERVER_URL] (provided by admin)"
            echo "  3. Run: $0 test (to verify connection)"
            echo "  4. Run: $0 update (to send initial package data)"
            echo ""
            echo "Configuration:"
            echo "  Edit $CONFIG_FILE to customize server settings"
            echo "  PATCHMON_SERVER=http://your-server:3001"
            exit 1
            ;;
    esac
}

# Run main function
main "$@" 
