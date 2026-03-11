# Local Rescue Owner Request

Date: 2026-03-08

## Short Version To Send

현재 문제는 두 덩어리로 나뉩니다.

### 1. 모델 쪽에서 수정이 필요한 것

- `qwen3.5:9b-q4_K_M` 기반으로 rescue 전용 태그를 하나 따로 만들어 주세요.
- 가능하면 이 태그는 기본적으로 `think:false` 성격을 가진 별도 태그여야 합니다.
- hidden reasoning이나 `thinking` 전용 출력 없이, 최종 답이 반드시 `response` 또는 `message.content`에 들어가게 해 주세요.
- 아래 3개 프롬프트를 `temperature=0`에서 안정적으로 통과하게 맞춰 주세요.
  - `Reply with exactly LOCAL_RESCUE_OK.`
  - `다음 형식으로만 답하라.\n1) 상태: 정상\n2) 안내: 잠시 후 다시 시도`
  - `모르면 모른다고만 짧게 답하라: 오늘 미국 CPI 수치 알려줘.`
- trivial prompt 기준으로 first token 10초 이내, cold-ish worst case도 20초 안쪽으로 줄여 주세요.
- 가능하면 태그 이름은 일반용이 아니라 `rescue` 또는 `nothink` 계열로 명확히 구분해 주세요.

### 2. 우리 OpenClaw 쪽에서 따로 잡고 있는 것

- direct `local-rescue` agent는 세션 재사용 때문에 timeout/error 메타가 오염될 수 있습니다.
- 그래서 지금은 `openclaw agent --agent local-rescue` 결과만 보고 모델을 판단하면 안 됩니다.
- 우리는 isolated cron lane으로 테스트를 분리했고, 이 경로에서는 실제 모델 라우팅이 `ollama/qwen3.5:9b-q4_K_M`로 고정되는 것까지 확인했습니다.
- `think:false` 전달 누락과 stale skill snapshot 재사용은 우리 쪽에서 이미 패치했습니다.
- direct lane 기준으로 bundled skills prompt는 `29684 chars -> 0`, 전체 system prompt는 `37042 chars -> 6780`까지 줄였습니다.
- 다만 그 상태에서도 OpenClaw embedded 경로에서 `45s`와 `90s` timeout이 남아 있어서, 남은 병목은 우리 쪽 OpenClaw runtime 경로로 더 좁혀졌습니다.
- 참고로 raw Ollama에서는 `think:false`를 줄 때 `LOCAL_RESCUE_OK`가 약 `33~38s` 안에 나옵니다. 그래서 모델 자체가 완전히 불가능한 건 아니고, hidden reasoning off 경로가 핵심입니다.
- 추가로 오늘 늦은 재확인 시점에는 raw Ollama 최소 body(`/api/chat`, `/api/generate`)도 다시 timeout이 나고 있습니다. 그래서 현재 Ollama 서버 상태 자체가 재평가를 오염시키고 있을 가능성이 큽니다.

## What We Confirmed On Our Side

- stale `qwen3:14b` direct lane은 active config에서 제거했습니다
- `local-rescue` live target is now `qwen3.5:9b-q4_K_M`
- isolated cron lane can now stay on:
  - `provider=ollama`
  - `model=qwen3.5:9b-q4_K_M`
- but that clean lane still timed out at about `45s`

## What We Need From You First

Priority order:

1. `qwen3.5:9b-q4_K_M` rescue tag with no `thinking`-only output
2. exact-marker obedience
3. fixed two-line format obedience
4. lower latency for trivial prompts

## Server Health Check To Run First

지금은 모델 품질 문제와 별개로 Ollama 서버 상태가 재평가를 오염시키고 있을 수 있습니다.

아래 3개를 먼저 실행해서 결과를 보내 주세요.

```bash
curl -sS --max-time 10 http://100.116.158.17:11434/api/version
curl -sS --max-time 10 http://100.116.158.17:11434/api/ps | jq '.'
TIMEFORMAT='real=%3R'
time curl -sS -m 60 \
  -H 'Content-Type: application/json' \
  -d '{"model":"qwen3.5:9b-q4_K_M","prompt":"Reply with exactly LOCAL_RESCUE_OK.","stream":false,"think":false,"options":{"temperature":0,"num_predict":8}}' \
  http://100.116.158.17:11434/api/generate | jq '{done,response,eval_count,prompt_eval_count,load_duration,total_duration}'
```

만약 여기서도 timeout이 나면, OpenClaw 문제가 아니라 Ollama 서버나 모델 런타임 상태를 먼저 봐야 합니다.

추가로 timeout이면 아래도 같이 보내 달라고 요청해 주세요.

```bash
ollama ps
journalctl -u ollama -n 200 --no-pager
free -h
uptime
```

GPU 서버면 이것도 같이:

```bash
nvidia-smi
```

## What We Will Re-Test After Handoff

- raw Ollama `/api/generate`
- raw Ollama `/api/chat`
- OpenClaw isolated cron lane
- exact marker / fixed format / fail-soft prompts

## Internal Note

If the next handoff still emits content only in `thinking`, do not promote it.
