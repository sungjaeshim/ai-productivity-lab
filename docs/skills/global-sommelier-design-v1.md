# Global Sommelier Skill — Pre-Design v1 (Top 0.1% Style)

## 0) Scope Decision
- Build **core sommelier skill first** (image-first analysis + pairing/service guidance).
- Keep external price/rating providers as optional adapters (non-blocking).
- Do **not** depend on Vivino for core path.

---

## 1) RFE Gate (Before Engineering)

1. Problem now
   - User sends wine photos and wants fast, practical guidance (ID, price range, score range, serving/pairing) without app switching.
2. Metrics
   - North Star: useful answer rate per request (user says “usable now”).
   - Guardrail: hallucination rate on bottle identification.
   - Kill Metric: wrong high-confidence ID (>80%) above threshold.
3. Edge cases
   - Blurry/partial labels, duplicate vintages, non-wine bottles in frame, mixed language labels.
4. Legal/privacy
   - Avoid scraping restricted/private content; label external-source uncertainty.
5. Rollback/observability
   - Start with advice-only mode; log confidence + whether fallback search was used.

Decision: PASS with “confidence-gated response policy.”

---

## 2) Product Contract (What user always gets)

For every wine-image request, return:
1) Bottle identification
   - name, producer, vintage (if visible), region/style
   - confidence: High / Medium / Low + %
2) Commercial guidance
   - estimated price range (KRW)
   - estimated score range (5-point and/or 100-point normalized)
3) Service guidance
   - serving temp, decant time, glass, drink window
4) Food pairing
   - 2–3 strong pairings + 1 avoid pairing
5) Evidence block
   - “why” signals from image + source tags `[Brave] [DDG] [RSS]` only if external lookup used

Output format fixed:
- 요약
- 핵심 3줄
- 선택지 A/B
- 다음 액션 1줄

---

## 3) Trigger/Non-Trigger Set

### Trigger examples
- "이 와인 뭐야?"
- "사진 속 와인 가격/점수 알려줘"
- "이거 음식 뭐랑 먹어?"
- "디캔팅 얼마나 해?"
- "지금 마셔도 돼?"

### Non-trigger examples
- 일반 주식/코딩 질문
- 단순 번역/문법 요청
- 술과 무관한 음식 사진

---

## 4) Accuracy Policy (Confidence-Gated)

- High (>=80%)
  - Give direct recommendation + narrower price/score range.
- Medium (55–79%)
  - Mark as “추정”, provide 2 candidate labels.
- Low (<55%)
  - Ask for close-up shots (front label / neck / capsule / back label) before hard claims.

Hard rule:
- Never output single definitive ID at Low confidence.

---

## 5) Data Strategy

### Tier 1 (Always)
- Vision/OCR extraction from uploaded image.
- Internal wine knowledge map (region/grape/style/service heuristics).

### Tier 2 (Conditional fallback)
- If confidence low OR price/score freshness required:
  - Search provider policy: Brave primary -> DDG fallback -> RSS corroboration.
- External lookups must be source-tagged.

### Tier 3 (Optional adapters)
- `vivino-adapter` optional, non-critical.
- Failure of adapter must not fail core response.

---

## 6) Failure / Blocker Codes

- AUTH: provider login/token required
- 2FA: OTP/captcha gate
- LEGAL: terms/reuse restrictions
- UI_LOCK: non-automatable page flow
- PHYSICAL: requires new photo angle from user

If blocked:
- return max 3 manual steps + exact resume message.

---

## 7) Skill Package Structure (Planned)

`~/.openclaw/skills/global-sommelier/`
- `SKILL.md`
- `references/`
  - `grape-profiles.md`
  - `regions-and-appellations.md`
  - `service-temps-and-decant.md`
  - `pairing-rules.md`
  - `scoring-normalization.md`
- `scripts/`
  - `pairing_score.py`
  - `price_score_band.py`
  - `confidence_policy.py`
- `assets/`
  - `tasting-note-template.md`

---

## 8) Eval Plan (Before rollout)

### Test set
- 30 images minimum
  - 10 clear labels
  - 10 partial/angled labels
  - 5 mixed bottle scenes
  - 5 tricky cases (look-alikes)

### Pass criteria
- ID top-1 accuracy (clear set): >=85%
- High-confidence wrong-ID rate: <=3%
- Price-band usability (user-judged useful): >=80%
- Median response latency: <=12s (without external fallback)

### Red flags
- Repeated false certainty on famous labels
- Overly narrow prices without source evidence

---

## 9) Rollout Plan (RFT)

A) Feature flag: `sommelier_mode=shadow|active`
B) Canary:
- Week 1 shadow mode (no hard claims on low confidence)
- Week 2 active for direct chats only
C) Rollback:
- one-switch to advice-only mode (no price/score bands)

---

## 10) Open Questions for Review (Resolved 2026-03-04)

User decisions frozen:
1. **Score standard**: dual output (5-point + 100-point normalized) ✅
2. **Price granularity**: KRW min/max + percentile-style band + confidence ✅
3. **Medium confidence policy**: always provide 2–3 candidate labels ✅
4. **Pairing default**: Korean cuisine priority + global alternatives ✅
5. **Cellar/investment mode in v1**: exclude (drinking-focused MVP) ✅

---

## 11) Immediate Next Step
- Contract frozen. Generate `global-sommelier/SKILL.md` skeleton + reference files for v1 (no provider adapter yet).
- Additional defaults frozen (2026-03-04):
  - Output length: Standard (1B)
  - Price rounding: 1,000 KRW (2B)
  - Score presentation: split explanation for 5-point and 100-point (3B)
