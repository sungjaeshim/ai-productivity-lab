# Audio Routing Policy (10MB Split)

## Goal
Keep main chat clean and stable while processing large audio files.

## Routing Rule
- **Route A (inline / speed-first):** file size `<= 10MB`
  - Whisper model: `small` (or `turbo` when available)
- **Route B (worker / quality-first):** file size `> 10MB`
  - Whisper model: `medium` (optionally `large` for critical accuracy)

## Visibility Contract (main chat)
Main chat should only show:
1. `received`
2. `processing (A|B)`
3. `done` or `failed:<code>`

## Failure Codes
- `FETCH_DENIED` - source URL cannot be downloaded
- `DEL_MISSING` - downloaded file missing/unreadable
- `TIMEOUT` - processing exceeded timeout
- `TRANSCRIBE_FAIL` - Whisper failed
- `SUMMARIZE_FAIL` - summarization stage failed

## Timeouts (baseline)
- download timeout: `120~900s` (size-based)
- whisper timeout: `max(1800s, duration*2 + 600s)`

## Helper Script
Use `scripts/audio_route.py`:

```bash
python3 scripts/audio_route.py "<url-or-file>"
python3 scripts/audio_route.py "<url-or-file>" --run
```

The script returns JSON containing:
- selected route (`A` or `B`)
- selected model
- recommended timeouts
- transcript path (when `--run`)
