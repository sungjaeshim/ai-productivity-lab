#!/bin/bash
# incident-db.sh - SQLite 기반 인시던트 저장 (jsonl 폴백)
# Usage: incident-db.sh insert '<JSON>' | --list [N] | --get <ID>

set -euo pipefail

# 경로 설정
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKSPACE_DIR="$(dirname "$SCRIPT_DIR")"
DATA_DIR="${WORKSPACE_DIR}/data"
DB_FILE="${DATA_DIR}/incidents.db"
JSONL_FILE="${DATA_DIR}/incidents.jsonl"

# 색상 코드
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# 민감정보 패턴 (마스킹용)
SENSITIVE_PATTERNS=(
    "password=[^,}*]*"
    "token=[^,}*]*"
    "api_key=[^,}*]*"
    "secret=[^,}*]*"
    "credential=[^,}*]*"
    "[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}"  # 이메일
    "[0-9]{3}-[0-9]{3,4}-[0-9]{4}"  # 전화번호
)

# SQLite 사용 가능 여부 체크
HAS_SQLITE=0
if command -v sqlite3 &>/dev/null; then
    HAS_SQLITE=1
fi

# 데이터 디렉토리 생성
ensure_data_dir() {
    mkdir -p "$DATA_DIR"
}

# 민감정보 마스킹
mask_sensitive() {
    local text="$1"
    local result="$text"
    
    for pattern in "${SENSITIVE_PATTERNS[@]}"; do
        result=$(echo "$result" | sed -E "s/$pattern/***MASKED***/g" 2>/dev/null || echo "$result")
    done
    
    echo "$result"
}

# JSON 필드 파싱
parse_field() {
    local json="$1"
    local field="$2"
    
    if command -v jq &>/dev/null; then
        echo "$json" | jq -r ".$field // empty" 2>/dev/null || echo ""
    else
        echo "$json" | grep -o "\"$field\"[[:space:]]*:[[:space:]]*\"[^\"]*\"" 2>/dev/null | sed 's/.*: *"\([^"]*\)".*/\1/' || echo ""
    fi
}

# SQLite DB 초기화
init_sqlite_db() {
    if [[ $HAS_SQLITE -eq 0 ]]; then
        return 1
    fi
    
    ensure_data_dir
    
    if [[ ! -f "$DB_FILE" ]]; then
        sqlite3 "$DB_FILE" <<'SQL'
CREATE TABLE IF NOT EXISTS incidents (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    occurred_at TEXT NOT NULL,
    project TEXT NOT NULL,
    severity TEXT NOT NULL,
    level TEXT,
    title TEXT NOT NULL,
    cause TEXT,
    action TEXT,
    verify TEXT,
    prevent TEXT,
    status TEXT DEFAULT 'open',
    created_at TEXT NOT NULL DEFAULT (datetime('now', '+9 hours'))
);
CREATE INDEX IF NOT EXISTS idx_occurred_at ON incidents(occurred_at);
CREATE INDEX IF NOT EXISTS idx_severity ON incidents(severity);
CREATE INDEX IF NOT EXISTS idx_status ON incidents(status);
SQL
        echo -e "${GREEN}✓ SQLite DB 초기화 완료${NC}: $DB_FILE" >&2
    fi
}

# JSONL 폴백 초기화
init_jsonl() {
    ensure_data_dir
    if [[ ! -f "$JSONL_FILE" ]]; then
        touch "$JSONL_FILE"
        echo -e "${YELLOW}⚠ SQLite 없음, JSONL 폴백 사용${NC}: $JSONL_FILE" >&2
    fi
}

# SQLite INSERT
insert_sqlite() {
    local occurred_at="$1" project="$2" severity="$3" level="$4"
    local title="$5" cause="$6" action="$7" verify="$8" prevent="$9" status="${10}"
    
    init_sqlite_db || return 1
    
    # 마스킹
    title=$(mask_sensitive "$title")
    cause=$(mask_sensitive "$cause")
    action=$(mask_sensitive "$action")
    verify=$(mask_sensitive "$verify")
    prevent=$(mask_sensitive "$prevent")
    
    local result
    result=$(sqlite3 "$DB_FILE" \
        "INSERT INTO incidents (occurred_at, project, severity, level, title, cause, action, verify, prevent, status)
         VALUES ('$occurred_at', '$project', '$severity', '$level', '$title', '$cause', '$action', '$verify', '$prevent', '$status');
         SELECT last_insert_rowid();")
    
    echo "$result"
}

# JSONL INSERT
insert_jsonl() {
    local occurred_at="$1" project="$2" severity="$3" level="$4"
    local title="$5" cause="$6" action="$7" verify="$8" prevent="$9" status="${10}"
    
    init_jsonl
    
    # 마스킹
    title=$(mask_sensitive "$title")
    cause=$(mask_sensitive "$cause")
    action=$(mask_sensitive "$action")
    verify=$(mask_sensitive "$verify")
    prevent=$(mask_sensitive "$prevent")
    
    # ID 생성 (타임스탬프 기반)
    local id
    id=$(date +%s)
    
    # JSON 라인 생성
    cat <<EOF >> "$JSONL_FILE"
{"id":$id,"occurred_at":"$occurred_at","project":"$project","severity":"$severity","level":"$level","title":"$title","cause":"$cause","action":"$action","verify":"$verify","prevent":"$prevent","status":"$status","created_at":"$(date -Iseconds)"}
EOF
    
    echo "$id"
}

# 통합 INSERT
insert_incident() {
    local json="$1"
    
    # 필드 파싱
    local project severity level title cause action verify prevent status occurred_at
    
    project=$(parse_field "$json" "project")
    severity=$(parse_field "$json" "severity")
    level=$(parse_field "$json" "level")
    title=$(parse_field "$json" "title")
    cause=$(parse_field "$json" "cause")
    action=$(parse_field "$json" "action")
    verify=$(parse_field "$json" "verify")
    prevent=$(parse_field "$json" "prevent")
    status=$(parse_field "$json" "status")
    occurred_at=$(parse_field "$json" "occurred_at")
    
    # 기본값
    project=${project:-"unknown"}
    severity=${severity:-"L1"}
    level=${level:-""}
    title=${title:-"Untitled incident"}
    cause=${cause:-"원인 분석 중"}
    action=${action:-"조치 대기 중"}
    verify=${verify:-"검증 필요"}
    prevent=${prevent:-"재발방지 대책 수립 중"}
    status=${status:-"open"}
    occurred_at=${occurred_at:-$(date -Iseconds)}
    
    local id
    if [[ $HAS_SQLITE -eq 1 ]]; then
        id=$(insert_sqlite "$occurred_at" "$project" "$severity" "$level" "$title" "$cause" "$action" "$verify" "$prevent" "$status")
        echo -e "${GREEN}✓ SQLite 저장${NC} (id: $id)" >&2
    else
        id=$(insert_jsonl "$occurred_at" "$project" "$severity" "$level" "$title" "$cause" "$action" "$verify" "$prevent" "$status")
        echo -e "${YELLOW}✓ JSONL 저장${NC} (id: $id)" >&2
    fi
    
    echo "$id"
}

# SQLite 목록 조회
list_sqlite() {
    local limit="${1:-20}"
    
    init_sqlite_db || return 1
    
    echo -e "${BLUE}최근 $limit 건 인시던트:${NC}" >&2
    echo "" >&2
    
    sqlite3 -header -column "$DB_FILE" \
        "SELECT id, occurred_at, project, severity, title, status
         FROM incidents
         ORDER BY occurred_at DESC
         LIMIT $limit;"
}

# JSONL 목록 조회
list_jsonl() {
    local limit="${1:-20}"
    
    if [[ ! -f "$JSONL_FILE" || ! -s "$JSONL_FILE" ]]; then
        echo -e "${YELLOW}저장된 인시던트 없음${NC}" >&2
        return 0
    fi
    
    echo -e "${BLUE}최근 $limit 건 인시던트:${NC}" >&2
    echo "" >&2
    
    # tail로 최근 N건 가져오기
    local lines
    lines=$(tail -n "$limit" "$JSONL_FILE")
    
    if command -v jq &>/dev/null; then
        echo "$lines" | tac | jq -r '[.id, .occurred_at, .project, .severity, .title, .status] | @tsv' | \
        awk 'BEGIN {printf "%-6s %-22s %-12s %-8s %-30s %-10s\n", "ID", "OCCURRED_AT", "PROJECT", "SEVERITY", "TITLE", "STATUS"}
              {printf "%-6s %-22s %-12s %-8s %-30s %-10s\n", $1, $2, $3, $4, substr($5,1,30), $6}'
    else
        # jq 없으면 raw 출력
        echo "$lines" | tac | while read -r line; do
            echo "$line"
        done
    fi
}

# 통합 목록 조회
list_incidents() {
    local limit="${1:-20}"
    
    if [[ $HAS_SQLITE -eq 1 ]]; then
        list_sqlite "$limit"
    else
        list_jsonl "$limit"
    fi
}

# 단건 조회
get_incident() {
    local id="$1"
    
    if [[ $HAS_SQLITE -eq 1 ]]; then
        init_sqlite_db || return 1
        sqlite3 "$DB_FILE" "SELECT * FROM incidents WHERE id = $id;" 2>/dev/null || \
            echo -e "${RED}ID $id 찾을 수 없음${NC}" >&2
    else
        if [[ -f "$JSONL_FILE" ]]; then
            grep "\"id\":$id" "$JSONL_FILE" || echo -e "${RED}ID $id 찾을 수 없음${NC}" >&2
        else
            echo -e "${RED}저장된 인시던트 없음${NC}" >&2
        fi
    fi
}

# 상태 업데이트
update_status() {
    local id="$1"
    local new_status="$2"
    
    if [[ $HAS_SQLITE -eq 1 ]]; then
        init_sqlite_db || return 1
        sqlite3 "$DB_FILE" "UPDATE incidents SET status = '$new_status' WHERE id = $id;"
        echo -e "${GREEN}✓ 상태 업데이트${NC}: $id → $new_status" >&2
    else
        if [[ -f "$JSONL_FILE" ]]; then
            # JSONL은 append-only라 새 파일로 대체
            local temp_file="${JSONL_FILE}.tmp"
            grep -v "\"id\":$id" "$JSONL_FILE" > "$temp_file"
            grep "\"id\":$id" "$JSONL_FILE" | sed "s/\"status\":\"[^\"]*\"/\"status\":\"$new_status\"/" >> "$temp_file"
            mv "$temp_file" "$JSONL_FILE"
            echo -e "${YELLOW}✓ JSONL 상태 업데이트${NC}: $id → $new_status" >&2
        fi
    fi
}

# 도움말
usage() {
    cat <<EOF
Usage: $0 <COMMAND> [ARGS]

Commands:
  insert '<JSON>'    인시던트 저장
  --list [N]         최근 N건 조회 (기본: 20)
  --get <ID>         단건 조회
  --status <ID> <S>  상태 업데이트 (open/resolved/closed)

JSON 필드:
  project, severity, level, title, cause, action, verify, prevent, status, occurred_at

환경:
  SQLite: $([[ $HAS_SQLITE -eq 1 ]] && echo "사용 가능" || echo "없음 (JSONL 폴백)")
  DB 파일: $([[ $HAS_SQLITE -eq 1 ]] && echo "$DB_FILE" || echo "$JSONL_FILE")

예시:
  $0 insert '{"project":"jarvis","severity":"L2","title":"API 지연","cause":"DB 풀 고갈","action":"증설","verify":"<200ms","prevent":"모니터링"}'
  $0 --list 10
  $0 --get 1
  $0 --status 1 resolved
EOF
    exit 0
}

# 메인
main() {
    if [[ $# -lt 1 ]]; then
        usage
    fi
    
    local cmd="$1"
    shift
    
    case "$cmd" in
        insert)
            if [[ $# -lt 1 ]]; then
                echo -e "${RED}ERROR${NC}: JSON 인자 필요" >&2
                exit 1
            fi
            insert_incident "$1"
            ;;
        --list)
            list_incidents "${1:-20}"
            ;;
        --get)
            if [[ $# -lt 1 ]]; then
                echo -e "${RED}ERROR${NC}: ID 인자 필요" >&2
                exit 1
            fi
            get_incident "$1"
            ;;
        --status)
            if [[ $# -lt 2 ]]; then
                echo -e "${RED}ERROR${NC}: ID와 상태 인자 필요" >&2
                exit 1
            fi
            update_status "$1" "$2"
            ;;
        -h|--help|help)
            usage
            ;;
        *)
            echo -e "${RED}ERROR${NC}: 알 수 없는 명령: $cmd" >&2
            usage
            ;;
    esac
}

main "$@"
