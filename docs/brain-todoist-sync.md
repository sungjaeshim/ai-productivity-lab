# Brain ↔ Todoist Sync

Sync Discord brain-ops status to Todoist tasks.

## Overview

```
Discord brain-ops (status) → brain-todoist-sync.sh → Todoist task
```

This script bridges the brain pipeline with Todoist, allowing Discord-based task management to sync with your Todoist projects.

## Status Mapping

| Brain Status | Todoist Action | Priority | Project | Due Date |
|-------------|----------------|----------|---------|----------|
| **TODO**    | Create/Update  | p2       | queue   | -        |
| **DOING**   | Create/Update  | p1       | active  | today    |
| **DONE**    | Close task     | -        | -       | -        |
| **BLOCKED** | Create/Update + comment | p2 | waiting | tomorrow |

## Prerequisites

1. Todoist API token stored at: `~/.openclaw/credentials/todoist`
2. Projects config at: `~/.openclaw/credentials/todoist-projects.json`

## Usage

### Basic Syntax

```bash
./scripts/brain-todoist-sync.sh \
  --item-id <UNIQUE_ID> \
  --status <STATUS> \
  --title "Task title" \
  [--project <PROJECT>] \
  [--reason "Block reason"] \
  [--dry-run]
```

### Required Arguments

| Argument | Description |
|----------|-------------|
| `--item-id` | Unique identifier (URL hash, message ID, etc.) |
| `--status` | One of: `TODO`, `DOING`, `DONE`, `BLOCKED` |
| `--title` | Task content/title |

### Optional Arguments

| Argument | Default | Description |
|----------|---------|-------------|
| `--project` | Status-dependent | Target project: `queue`, `active`, `waiting`, `inbox` |
| `--reason` | - | Reason for BLOCKED status (becomes comment) |
| `--dry-run` | - | Simulate without making API calls |

## Examples

### Create TODO Task

```bash
# New item from brain-ops
./scripts/brain-todoist-sync.sh \
  --item-id "link-a1b2c3d4" \
  --status TODO \
  --title "Research AI agents for marketing automation"

# Output: Created TODO task: <task_id>
```

### Start Working (DOING)

```bash
# Mark as in-progress
./scripts/brain-todoist-sync.sh \
  --item-id "link-a1b2c3d4" \
  --status DOING \
  --title "Research AI agents for marketing automation"

# Output: Updated task to DOING state: <task_id>
# - Moved to 'active' project
# - Priority set to p1
# - Due date set to today
```

### Complete Task (DONE)

```bash
# Mark as done
./scripts/brain-todoist-sync.sh \
  --item-id "link-a1b2c3d4" \
  --status DONE \
  --title "Research AI agents for marketing automation"

# Output: Closed task: <task_id>
```

### Block Task

```bash
# Mark as blocked with reason
./scripts/brain-todoist-sync.sh \
  --item-id "link-a1b2c3d4" \
  --status BLOCKED \
  --title "Research AI agents" \
  --reason "Waiting for API access from vendor"

# Output: Created BLOCKED task: <task_id>
# - Moved to 'waiting' project
# - Due date set to tomorrow
# - Comment added with reason
```

### Dry Run

```bash
# Test without making changes
./scripts/brain-todoist-sync.sh \
  --item-id "test-123" \
  --status TODO \
  --title "Test task" \
  --dry-run

# Output:
# [DRY-RUN] Would create new task: 'Test task' (p2, project: queue)
```

## Integration with Brain Pipeline

### From brain-thread-manage.sh

```bash
# In brain-thread-manage.sh, after updating local status:
sync_to_todoist() {
    local url="$1"
    local status="$2"
    local title="$3"
    
    # Generate item-id from URL hash
    local item_id="brain-$(echo -n "$url" | sha256sum | cut -c1-16)"
    
    ./scripts/brain-todoist-sync.sh \
        --item-id "$item_id" \
        --status "$status" \
        --title "$title"
}
```

### From brain-link-ingest.sh

```bash
# Auto-create TODO task for new links
./scripts/brain-todoist-sync.sh \
    --item-id "link-$URL_HASH" \
    --status TODO \
    --title "$TITLE"
```

## Duplicate Prevention

The script maintains a local registry at:
```
memory/second-brain/.brain-todoist-registry.jsonl
```

Registry format:
```json
{"item_id":"link-a1b2c3d4","todoist_id":"6ABC123","status":"TODO","title":"Task","synced_at":"2026-03-01T10:00:00+09:00"}
```

When `--item-id` already exists:
- **TODO/DOING/BLOCKED**: Updates existing task instead of creating new
- **DONE**: Closes the existing task

## Exit Codes

| Code | Meaning |
|------|---------|
| 0 | Success |
| 1 | Missing required argument |
| 2 | Invalid status |
| 3 | Todoist token not found |
| 4 | Todoist API error |
| 5 | Duplicate (already synced) |
| 6 | Task not found (for DONE/update) |

## Workflow Examples

### Typical Day Workflow

```bash
# Morning: Review brain-inbox links
# See interesting link, add to TODO
./scripts/brain-todoist-sync.sh --item-id "br-001" --status TODO --title "Read article"

# Start working on it
./scripts/brain-todoist-sync.sh --item-id "br-001" --status DOING --title "Read article"

# Finish
./scripts/brain-todoist-sync.sh --item-id "br-001" --status DONE --title "Read article"
```

### Blocked → Unblocked Flow

```bash
# Hit a blocker
./scripts/brain-todoist-sync.sh \
  --item-id "br-002" \
  --status BLOCKED \
  --title "Implement feature" \
  --reason "Need design review"

# Blocker resolved, resume work
./scripts/brain-todoist-sync.sh \
  --item-id "br-002" \
  --status DOING \
  --title "Implement feature"
```

## Troubleshooting

### "Todoist token not found"

```bash
# Verify token file exists
cat ~/.openclaw/credentials/todoist

# Should output your API token
```

### "Projects file not found"

```bash
# Verify projects config
cat ~/.openclaw/credentials/todoist-projects.json

# Required format:
{
  "queue": "project-id-here",
  "active": "project-id-here",
  "waiting": "project-id-here",
  "inbox": "project-id-here"
}
```

### "Task not found" for DONE

The `--item-id` must match a previously synced task. Check the registry:

```bash
grep "your-item-id" memory/second-brain/.brain-todoist-registry.jsonl
```

### API Errors

- HTTP 401: Invalid/expired token
- HTTP 403: No permission to project
- HTTP 404: Task or project not found

## Security Notes

- **Never log or output the Todoist token**
- Dry-run mode makes no API calls
- No destructive operations (tasks are closed, not deleted)

## File Locations

| File | Purpose |
|------|---------|
| `scripts/brain-todoist-sync.sh` | Main sync script |
| `memory/second-brain/.brain-todoist-registry.jsonl` | Sync registry |
| `credentials/todoist` | API token |
| `credentials/todoist-projects.json` | Project IDs |
| `docs/brain-todoist-sync.md` | This documentation |

## Future Enhancements

- [ ] Bi-directional sync (Todoist → Discord)
- [ ] Auto-cleanup of old registry entries
- [ ] Bulk sync from links.md
- [ ] Webhook for real-time sync
