#!/usr/bin/env bash
# system-inventory-scan.sh - Collect system services, projects, and API endpoints
# Usage: system-inventory-scan.sh [--dry-run] [--out FILE]
# POSIX bash + jq (if available)

set -euo pipefail

# Config
WORKSPACE="${WORKSPACE:-/root/.openclaw/workspace}"
PROJECTS_DIR="${PROJECTS_DIR:-/root/Projects}"
DRY_RUN=0
OUT_FILE=""

# Parse args
while [[ $# -gt 0 ]]; do
    case "$1" in
        --dry-run) DRY_RUN=1; shift ;;
        --out) OUT_FILE="$2"; shift 2 ;;
        -h|--help)
            echo "Usage: $0 [--dry-run] [--out FILE]"
            echo "  --dry-run   Show what would be collected without writing"
            echo "  --out FILE  Write JSON output to FILE"
            exit 0
            ;;
        *) echo "Unknown option: $1" >&2; exit 1 ;;
    esac
done

# Check jq
HAS_JQ=0
command -v jq >/dev/null 2>&1 && HAS_JQ=1

# Sensitive patterns to filter
SENSITIVE_PATTERNS=(
    "token"
    "key"
    "secret"
    "password"
    "credential"
    "api_key"
    "apikey"
    "auth"
    "private"
)

# Filter sensitive strings
filter_sensitive() {
    local input="$1"
    local result="$input"
    for pattern in "${SENSITIVE_PATTERNS[@]}"; do
        result=$(echo "$result" | grep -ivE "$pattern" || true)
    done
    echo "$result"
}

# Collect running services
collect_services() {
    local services="[]"
    
    # systemd services
    if command -v systemctl >/dev/null 2>&1; then
        while IFS= read -r line; do
            [[ -z "$line" ]] && continue
            local unit active sub desc
            unit=$(echo "$line" | awk '{print $1}')
            active=$(echo "$line" | awk '{print $3}')
            sub=$(echo "$line" | awk '{print $4}')
            desc=$(echo "$line" | cut -d'=' -f2- | sed 's/^[[:space:]]*//')
            
            # Skip system services, keep custom ones
            case "$unit" in
                cloudflared*|growth-center*|openclaw*|strava*|sajangnim*)
                    if [[ $HAS_JQ -eq 1 ]]; then
                        services=$(echo "$services" | jq --arg n "$unit" --arg s "$active" --arg d "$desc" \
                            '. + [{"name": $n, "status": $s, "description": $d}]')
                    else
                        [[ "$services" != "[]" ]] && services+=","
                        services="${services%]}{\"name\":\"$unit\",\"status\":\"$active\",\"description\":\"$desc\"}]"
                    fi
                    ;;
            esac
        done < <(systemctl list-units --type=service --state=running --no-pager 2>/dev/null | grep -v "^\s*UNIT")
    fi
    
    # Node processes from ps
    while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        local pid port cmd
        pid=$(echo "$line" | awk '{print $1}')
        cmd=$(echo "$line" | awk '{for(i=11;i<=NF;i++) printf $i " "; print ""}' | sed 's/ *$//')
        
        # Skip if already captured via systemd
        echo "$services" | grep -q "sajangnim-ai\|growth-center" && continue
        
        # Extract meaningful name
        local name=""
        case "$cmd" in
            *strava-webhook*) name="strava-webhook-server" ;;
            *sajangnim-ai*) name="sajangnim-ai-server" ;;
            *growth-center*) name="growth-center-server" ;;
            *) continue ;;
        esac
        
        if [[ -n "$name" ]] && [[ $HAS_JQ -eq 1 ]]; then
            # Check if already in services
            if ! echo "$services" | jq -e --arg n "$name" 'map(.name) | index($n)' >/dev/null 2>&1; then
                services=$(echo "$services" | jq --arg n "$name" --arg c "$cmd" \
                    '. + [{"name": $n, "status": "running", "command": $c}]')
            fi
        fi
    done < <(ps aux | grep -E "node.*server|node.*strava" | grep -v grep || true)
    
    echo "$services"
}

# Collect projects with tags
collect_projects() {
    local projects="[]"
    
    # Known project mappings (tag -> path)
    declare -A PROJECT_MAP=(
        ["growth-center"]="/root/Projects/growth-center"
        ["ceo-ai"]="/root/Projects/sajangnim-ai"
        ["blog"]="/root/.openclaw/workspace/content/blog"
        ["macd"]="/root/.openclaw/workspace/scripts/nq_macd_multi.py"
    )
    
    for tag in "${!PROJECT_MAP[@]}"; do
        local path="${PROJECT_MAP[$tag]}"
        local exists="false"
        local type="unknown"
        
        if [[ -e "$path" ]]; then
            exists="true"
            if [[ -d "$path" ]]; then
                type="directory"
            elif [[ -f "$path" ]]; then
                type="file"
            fi
            
            # Get git remote if available (strip tokens/credentials)
            local repo_url=""
            if [[ -d "$path/.git" ]]; then
                repo_url=$(cd "$path" && git remote get-url origin 2>/dev/null || echo "")
                # Strip any tokens/credentials from URL
                repo_url=$(echo "$repo_url" | sed -E 's|([^@:/]+://[^:]+:)[^@]+@|\1***@|g' | sed -E 's|([^@]+:)[^@]+@|\1***@|g')
            fi
            
            if [[ $HAS_JQ -eq 1 ]]; then
                projects=$(echo "$projects" | jq --arg t "$tag" --arg p "$path" --arg tp "$type" --arg r "$repo_url" \
                    '. + [{"tag": $t, "path": $p, "type": $tp, "repoUrl": $r}]')
            fi
        fi
    done
    
    # Sort by tag if jq available
    [[ $HAS_JQ -eq 1 ]] && projects=$(echo "$projects" | jq 'sort_by(.tag)')
    
    echo "$projects"
}

# Collect API endpoints from nginx and listening ports
collect_endpoints() {
    local endpoints="[]"
    
    # From nginx config
    if [[ -d /etc/nginx/sites-enabled ]]; then
        for conf in /etc/nginx/sites-enabled/*; do
            [[ -f "$conf" ]] || continue
            
            local server_names proxy_targets
            # Get all server_names (skip default _)
            server_names=$(grep -E "^\s*server_name" "$conf" 2>/dev/null | grep -v "_;" | sed 's/.*server_name\s*//;s/;.*//' | tr -d ' ' | head -5)
            
            # Get proxy_pass backends
            proxy_targets=$(grep -E "proxy_pass" "$conf" 2>/dev/null | sed 's/.*proxy_pass\s*//;s/;.*//' | tr -d ' ' | head -10)
            
            for sname in $server_names; do
                [[ -z "$sname" || "$sname" == "_" ]] && continue
                for proxy in $proxy_targets; do
                    # Skip internal/localhost proxies for external endpoints
                    if [[ -n "$proxy" && ! "$proxy" =~ "token" && ! "$proxy" =~ "key" ]]; then
                        local url="http://${sname}/"
                        if [[ $HAS_JQ -eq 1 ]]; then
                            # Avoid duplicates
                            if ! echo "$endpoints" | jq -e --arg h "$sname" 'map(.host) | index($h)' >/dev/null 2>&1; then
                                endpoints=$(echo "$endpoints" | jq --arg u "$url" --arg p "$proxy" --arg h "$sname" \
                                    '. + [{"url": $u, "backend": $p, "source": "nginx", "host": $h}]')
                            fi
                        fi
                    fi
                done
            done
        done
    fi
    
    # From listening ports (localhost services)
    while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        local port addr proc name
        # Parse: LISTEN 0 511 127.0.0.1:18800 0.0.0.0:* users:(("node",pid=...))
        if [[ "$line" =~ 127\.0\.0\.1:([0-9]+) ]]; then
            port="${BASH_REMATCH[1]}"
        else
            continue
        fi
        
        # Only service ports
        case "$port" in
            18800) name="growth-center-api" ;;
            18790) name="strava-webhook" ;;
            3100) name="sajangnim-ai-api" ;;
            18789|18791|18792) name="openclaw-gateway" ;;
            *) continue ;;
        esac
        
        if [[ $HAS_JQ -eq 1 ]]; then
            # Check if already captured via backend
            if ! echo "$endpoints" | jq -e --arg b "127.0.0.1:$port" 'map(.backend) | index($b)' >/dev/null 2>&1; then
                local url="http://localhost:$port"
                endpoints=$(echo "$endpoints" | jq --arg n "$name" --arg b "127.0.0.1:$port" --arg u "$url" \
                    '. + [{"url": $u, "backend": $b, "source": "port", "name": $n}]')
            fi
        fi
    done < <(ss -tlnp 2>/dev/null | grep "127.0.0.1" || true)
    
    # Sort if jq available
    [[ $HAS_JQ -eq 1 ]] && endpoints=$(echo "$endpoints" | jq 'sort_by(.host // .name)')
    
    echo "$endpoints"
}

# Main
main() {
    local generated_at
    generated_at=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    
    echo "Scanning system inventory..." >&2
    
    local services projects endpoints
    
    if [[ $DRY_RUN -eq 1 ]]; then
        echo "=== DRY RUN ===" >&2
        echo "Services to collect:" >&2
        systemctl list-units --type=service --state=running --no-pager 2>/dev/null | grep -E "cloudflared|growth-center|strava|sajangnim" || echo "  (none)" >&2
        echo "" >&2
        echo "Projects to scan:" >&2
        echo "  growth-center: /root/Projects/growth-center" >&2
        echo "  ceo-ai: /root/Projects/sajangnim-ai" >&2
        echo "  blog: /root/.openclaw/workspace/content/blog" >&2
        echo "  macd: /root/.openclaw/workspace/scripts/nq_macd_multi.py" >&2
        echo "" >&2
        echo "Endpoints from nginx:" >&2
        grep -h "server_name\|proxy_pass" /etc/nginx/sites-enabled/* 2>/dev/null | head -10 >&2 || echo "  (none)" >&2
        exit 0
    fi
    
    services=$(collect_services)
    projects=$(collect_projects)
    endpoints=$(collect_endpoints)
    
    if [[ $HAS_JQ -eq 1 ]]; then
        local result
        result=$(jq -n \
            --argjson sv "$services" \
            --argjson pj "$projects" \
            --argjson ep "$endpoints" \
            --arg ga "$generated_at" \
            '{services: $sv, projects: $pj, endpoints: $ep, generatedAt: $ga}')
        
        if [[ -n "$OUT_FILE" ]]; then
            echo "$result" > "$OUT_FILE"
            echo "Inventory written to: $OUT_FILE" >&2
        else
            echo "$result"
        fi
    else
        # Fallback without jq - output simple JSON
        echo "{\"services\": $services, \"projects\": $projects, \"endpoints\": $endpoints, \"generatedAt\": \"$generated_at\"}"
    fi
}

main "$@"
