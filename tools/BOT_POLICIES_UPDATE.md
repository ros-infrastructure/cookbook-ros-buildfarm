# Bot Policies Update Guide

This guide explains how to update the nginx bot detection policies from the upstream [TecharoHQ/anubis](https://github.com/TecharoHQ/anubis) repository.

## Overview

The bot detection policies are automatically fetched and converted from the Anubis project, which maintains a comprehensive list of AI crawler user agents and IP ranges.

## Quick Start

### Update to Latest Policies

```bash
cd cookbooks/ros_buildfarm/tools/
./update-bot-policies.sh
```

This will:
1. Fetch the latest policies from Anubis GitHub
2. Convert them to nginx map blocks
3. Save to `templates/nginx/snippets/bot_ua_map.conf`
4. Display a summary of what changed

### Check for Updates (Dry Run)

```bash
./update-bot-policies.sh check
```

Shows the latest upstream version without modifying any files.

### Get Help

```bash
./update-bot-policies.sh help
```

## Full Workflow

### 1. Check for Updates

```bash
cd cookbooks/ros_buildfarm/tools/
./update-bot-policies.sh check
```

Note the upstream commit SHA.

### 2. Update Policies

```bash
./update-bot-policies.sh
```

The script will:
- Fetch policies from Anubis
- Generate new `bot_ua_map.conf`
- Show statistics about changes

### 3. Review Changes

```bash
cd ../templates/nginx/snippets/
git diff bot_ua_map.conf
```

Look for:
- New bot additions
- Policy structure changes
- IP range updates

### 4. Validate Nginx Configuration

```bash
nginx -t
```

Or with a specific config file:

```bash
sudo nginx -t -c /etc/nginx/nginx.conf
```

### 5. Reload Nginx

**Development/Testing:**
```bash
systemctl reload nginx
```

**Production:**
```bash
sudo systemctl reload nginx
```

### 6. Commit Changes

```bash
git add templates/nginx/snippets/bot_ua_map.conf
git commit -m "Update bot policies from Anubis upstream

- Updated from TecharoHQ/anubis
- Added X new bot patterns
- Updated Y IP ranges
- No breaking changes"

git push
```

## What Gets Updated

The `update-bot-policies.sh` script fetches and converts these policies:

| Policy | Source | Contains |
|--------|--------|----------|
| `ai-catchall.yaml` | ai-robots-txt list | 50+ AI training crawlers |
| `ai-robots-txt.yaml` | robots.txt standards | 150+ comprehensive bots |
| `headless-browsers.yaml` | Browser automation | HeadlessChrome, Puppeteer, Playwright, etc. |
| `aggressive-brazilian-scrapers.yaml` | Spoofing detection | Deprecated OS patterns |
| `lyrenth.yaml` | Specific crawler | Lyrenth AI Web Index IP ranges |

## Policies Excluded

The following policies are NOT included by default:

- **Lyrenth UA pattern** - Intentionally removed (IP blocking retained)
  - This was done per project request to focus on IP-based blocking
  - If needed, re-enable by editing the script

- **Cloudflare policies** - Headers-only (no blocking by default)
  - `cloudflare-kitesurf.yaml`
  - `cloudflare-workers.yaml`

## Customization

### To Include Additional Policies

Edit `update-bot-policies.sh` and add to the `generate_config()` function:

```bash
local policy_name=$(fetch_policy "policy-file.yaml")
echo "$policy_name" | grep -A1 "user_agent_regex:" | tail -1 | tr '|' '\n' | \
    sed 's/^[[:space:]]*//;s/[[:space:]]*$//' | \
    while read agent; do
        [ -n "$agent" ] && echo "    \"~*$agent\" 1;"
    done
```

### To Exclude Policies

Comment out or remove the corresponding fetch and processing section in `generate_config()`.

## Troubleshooting

### Script Fails: "Missing required tool"

Install missing dependencies:
```bash
# Ubuntu/Debian
sudo apt-get install gh jq coreutils

# macOS
brew install gh jq
```

### Script Fails: GitHub API Error

Ensure you have GitHub CLI authenticated:
```bash
gh auth login
```

### Nginx Won't Reload After Update

Check for syntax errors:
```bash
nginx -t
```

Look for specific error messages about:
- Duplicate map definitions
- Syntax errors in regex patterns
- Conflicting variable names

### Want to Revert Changes

```bash
git checkout -- templates/nginx/snippets/bot_ua_map.conf
sudo systemctl reload nginx
```

## Monitoring Updates

### Schedule Regular Checks

Add to crontab for periodic updates (example: weekly):

```bash
# Edit crontab
crontab -e

# Add this line to check weekly (Sunday 2 AM)
0 2 * * 0 cd /path/to/chef-osrf/cookbooks/ros_buildfarm/tools && ./update-bot-policies.sh check >> /var/log/bot-policies-check.log 2>&1
```

### Check Upstream Manually

Visit: https://github.com/TecharoHQ/anubis/commits/main/data/bots

## Configuration Tracking

The script creates a `.bot-policies-config.json` file that tracks:
- Last update timestamp
- Upstream commit SHA
- Policies included
- Excluded policies

This helps track which version is deployed.

## Performance Considerations

- **Map lookup**: O(1) for static strings, O(n) for regex patterns
- **Regex patterns**: ~1-10 microseconds per request per map
- **Total impact**: < 1% CPU overhead for typical traffic

## References

- **Anubis Project**: https://github.com/TecharoHQ/anubis
- **AI Robots.txt**: https://github.com/ai-robots-txt/ai.robots.txt
- **Lyrenth**: https://lyrenth.com/bot
- **Nginx Map Module**: http://nginx.org/en/docs/http/ngx_http_map_module.html

## Support

For issues with:
- **Bot detection policies**: Report to [Anubis](https://github.com/TecharoHQ/anubis/issues)
- **Nginx configuration**: Consult [nginx documentation](http://nginx.org/)
- **This script**: Check the inline comments or edit as needed

---

**Last Updated**: 2026-09-01
**Script Version**: 1.0
**Upstream Support**: TecharoHQ/anubis main branch
