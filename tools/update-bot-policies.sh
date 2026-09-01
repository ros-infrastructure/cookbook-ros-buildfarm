#!/bin/bash

# Update nginx bot policies from TecharoHQ/anubis upstream
# Source: https://github.com/TecharoHQ/anubis/tree/main/data/bots
#
# Usage:
#   ./update-bot-policies.sh              Update bot_ua_map.conf
#   ./update-bot-policies.sh check        Check for updates without applying
#   ./update-bot-policies.sh help         Show help

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NGINX_DIR="$(cd "$SCRIPT_DIR/../files/nginx/conf.d/bot-protection" && pwd)"
OUTPUT_FILE="$NGINX_DIR/10-bot-detection.conf"
TEMP_FILE=$(mktemp)
trap "rm -f $TEMP_FILE" EXIT

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m'

log() { echo -e "${BLUE}[INFO]${NC} $*"; }
success() { echo -e "${GREEN}[✓]${NC} $*"; }
warn() { echo -e "${YELLOW}[!]${NC} $*"; }
error() { echo -e "${RED}[✗]${NC} $*"; }

# Show help
show_help() {
    cat << 'EOF'
Update nginx bot policies from TecharoHQ/anubis

Usage: ./update-bot-policies.sh [COMMAND]

Commands:
  (none)   Update conf.d/10-bot-detection.conf from upstream
  check    Check for upstream updates without modifying files
  help     Show this help message

Examples:
  # Update to latest policies
  ./update-bot-policies.sh

  # Check what would change
  ./update-bot-policies.sh check

After updating, you should:
  1. Review changes: git diff conf.d/10-bot-detection.conf
  2. Test nginx config: nginx -t
  3. Reload nginx: systemctl reload nginx

Requirements:
  - gh (GitHub CLI)
  - jq (JSON processor)
  - base64 (base64 encoder/decoder)
EOF
}

# Check dependencies
check_deps() {
    for cmd in gh jq base64; do
        if ! command -v "$cmd" &>/dev/null; then
            error "Missing required tool: $cmd"
            return 1
        fi
    done
}

# Fetch policy file from GitHub
fetch_policy() {
    local file="$1"
    log "Fetching $file..." >&2
    gh api "repos/TecharoHQ/anubis/contents/data/bots/$file" \
        --jq '.content' 2>/dev/null | base64 -d
}

# Generate bot_ua_map.conf
generate_config() {
    {
        cat << HEADER
# Bot Detection Maps - 10-bot-detection.conf
# Generated from TecharoHQ/anubis upstream policies
# https://github.com/TecharoHQ/anubis/tree/main/data/bots
#
# AUTO-GENERATED - Do not edit manually
# Update using: ./tools/update-bot-policies.sh
# Last updated: $(date -u +"%Y-%m-%d %H:%M:%S UTC")
# Upstream source: https://github.com/TecharoHQ/anubis
#
# Part of: conf.d/bot-protection.conf inclusion chain

HEADER

        # Primary Bot Detection - AI & Training Crawlers
        cat << 'SECTION1'

# ============================================================================
# Primary Bot Detection - Comprehensive AI & Training Crawlers
# ============================================================================
map $http_user_agent $is_bot {
    default 0;

    # Headless Browsers
    "~*(?i:lightpanda)" 1;
    "~*HeadlessChrome" 1;
    "~*HeadlessChromium" 1;
    "~*(?i:hyperbrowser)" 1;
    "~*Puppeteer" 1;
    "~*Playwright" 1;
    "~*Selenium" 1;

SECTION1

        # Fetch and process policies
        log "Fetching policies from Anubis..." >&2

        local ai_catchall ai_robots
        ai_catchall=$(fetch_policy "ai-catchall.yaml")
        ai_robots=$(fetch_policy "ai-robots-txt.yaml")

        # Merge both sources and de-duplicate case-insensitively (also against
        # the hardcoded headless-browser entries above). nginx's map directive
        # rejects a re-declared key outright, and ai-catchall/ai-robots-txt
        # overlap heavily (e.g. AI2Bot, anthropic-ai, Bytespider appear in
        # both), so this is not just cosmetic.
        {
            echo "$ai_catchall" | grep -A1 "user_agent_regex:" | tail -1 | tr '|' '\n'
            # Limit to the first 50 entries from this source, as before.
            echo "$ai_robots" | grep -A1 "user_agent_regex:" | tail -1 | tr '|' '\n' | head -50
        } | sed 's/^[[:space:]]*//;s/[[:space:]]*$//' | \
            awk 'BEGIN {
                n = split("lightpanda HeadlessChrome HeadlessChromium hyperbrowser Puppeteer Playwright Selenium", seeded, " ")
                for (i = 1; i <= n; i++) seen[tolower(seeded[i])] = 1
            }
            NF && !seen[tolower($0)]++' | \
            while read -r agent; do
                echo "    \"~*$agent\" 1;"
            done

        cat << 'SECTION2'
}

# ============================================================================
# Deprecated/Suspicious Browser Detection
# Likely indicates spoofing or malicious activity
# ============================================================================
map $http_user_agent $is_suspicious_browser {
    default 0;
    "~*MSIE" 1;             # Internet Explorer
    "~*Trident" 1;          # IE engine
    "~*Presto" 1;           # Opera
    "~*Windows CE" 1;       # Discontinued OS
    "~*Windows 95" 1;       # Discontinued OS
    "~*Windows 98" 1;       # Discontinued OS
    "~*Win 9x" 1;           # Discontinued OS
    "~*Alexa Toolbar" 1;    # Spoofing
    "~*Windows NT 11.0" 1;  # Fake Windows 11
    "~*iPod" 1;             # Not in common use
}

SECTION2

        cat << 'FOOTER'

# ============================================================================
# Cloudflare Infrastructure Detection
# These headers indicate requests routed through Cloudflare
# ============================================================================
map $http_cf_ray $has_cf_ray {
    default 0;
    ~.+ 1;
}

map $http_cf_worker $has_cf_worker {
    default 0;
    ~.+ 1;
}

# ============================================================================
# Usage Example in nginx server/location blocks:
# ============================================================================
#
# # Deny common bots
# if ($is_bot = 1) {
#     return 403 "Access Denied";
# }
#
# # Deny headless browsers (more permissive subset)
# if ($is_headless_bot = 1) {
#     return 403 "Access Denied";
# }
#
# # Log suspicious browsers for investigation
# if ($is_suspicious_browser = 1) {
#     access_log /var/log/nginx/suspicious.log;
# }
FOOTER
    } > "$TEMP_FILE"
}

# Check for updates
check_updates() {
    log "Checking upstream version..."
    local upstream_commit
    upstream_commit=$(gh api "repos/TecharoHQ/anubis/commits?path=data/bots&per_page=1" \
        --jq '.[0].sha[0:7]' 2>/dev/null || echo "unknown")

    log "Latest upstream commit: $upstream_commit"
    log "Output would be saved to: $OUTPUT_FILE"
}

# Main execution
main() {
    local cmd="${1:-update}"

    case "$cmd" in
        help)
            show_help
            exit 0
            ;;
        check)
            check_deps || exit 1
            check_updates
            exit 0
            ;;
        update|"")
            check_deps || exit 1
            log "Generating new bot_ua_map.conf..."
            generate_config

            if [ -f "$OUTPUT_FILE" ]; then
                log "Comparing with existing config..."
                if diff -q "$OUTPUT_FILE" "$TEMP_FILE" > /dev/null 2>&1; then
                    warn "No changes detected"
                    exit 0
                else
                    warn "Changes detected ($(wc -l < "$TEMP_FILE") lines)"
                fi
            fi

            log "Saving to: $OUTPUT_FILE"
            cp "$TEMP_FILE" "$OUTPUT_FILE"
            success "Config updated successfully"

            echo ""
            echo "Next steps:"
            echo "  1. Review changes:"
            echo "     git diff conf.d/10-bot-detection.conf"
            echo ""
            echo "  2. Verify bot protection is included:"
            echo "     grep 'include conf.d/bot-protection.conf' /etc/nginx/nginx.conf"
            echo ""
            echo "  3. Validate nginx config:"
            echo "     nginx -t"
            echo ""
            echo "  4. Reload nginx:"
            echo "     sudo systemctl reload nginx"
            ;;
        *)
            error "Unknown command: $cmd"
            show_help
            exit 1
            ;;
    esac
}

main "$@"
