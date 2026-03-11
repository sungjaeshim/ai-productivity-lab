#!/usr/bin/env node
/**
 * Call-Me v1 Event Router
 * - L1 (일반): Discord/Telegram 요약 알림
 * - L2 (중요): Telegram 텍스트 + TTS 재알림
 * 
 * 입력 JSON 형식:
 * {
 *   eventType: string,      // 이벤트 유형
 *   project: string,        // 프로젝트명
 *   severity: string,       // "low" | "medium" | "high" | "critical"
 *   summary: string,        // 요약 (1줄)
 *   details: string,        // 상세 내용
 *   retryCount: number,     // 재시도 횟수
 *   needApprovalMinutes: number, // 승인 필요까지 남은 시간(분)
 *   occurredAt: string      // ISO timestamp
 * }
 */

// L2 판정 규칙
const isL2 = (event) => {
  const { retryCount = 0, severity = 'low', needApprovalMinutes = 0 } = event;
  
  // L2 조건: retryCount>=3 OR severity in ["high","critical"] OR needApprovalMinutes>=30
  return (
    retryCount >= 3 ||
    ['high', 'critical'].includes(severity) ||
    needApprovalMinutes >= 30
  );
};

// 레벨 판정 (L1 또는 L2만 반환, L3 제외)
const getLevel = (event) => {
  return isL2(event) ? 'L2' : 'L1';
};

// KST 포맷팅
const formatKST = (isoString) => {
  const date = new Date(isoString);
  return date.toLocaleString('ko-KR', {
    timeZone: 'Asia/Seoul',
    year: 'numeric',
    month: '2-digit',
    day: '2-digit',
    hour: '2-digit',
    minute: '2-digit',
    hour12: false
  });
};

// L1 메시지 포맷 (Discord/Telegram 요약)
const formatL1Message = (event) => {
  const { eventType, project, severity, summary, occurredAt } = event;
  const emoji = getSeverityEmoji(severity);
  const kst = formatKST(occurredAt);
  
  return `${emoji} **[${project}] ${eventType}**
> ${summary}
📅 ${kst} | 심각도: ${severity.toUpperCase()}`;
};

// L2 메시지 포맷 (Telegram + TTS용 짧은 메시지)
const formatL2Message = (event) => {
  const { eventType, project, severity, summary, details, retryCount, needApprovalMinutes, occurredAt } = event;
  const emoji = getSeverityEmoji(severity);
  const kst = formatKST(occurredAt);
  
  let urgentFlags = [];
  if (retryCount >= 3) urgentFlags.push(`🔄 재시도 ${retryCount}회`);
  if (needApprovalMinutes >= 30) urgentFlags.push(`⏰ 승인까지 ${needApprovalMinutes}분`);
  
  const flags = urgentFlags.length > 0 ? `\n🚨 ${urgentFlags.join(' | ')}` : '';
  
  return `🚨 **[${project}] ${eventType}** 🚨
> ${summary}

📋 상세:
${details}
${flags}
📅 ${kst} | 심각도: **${severity.toUpperCase()}**`;
};

// TTS용 짧은 메시지 (음성으로 읽어줄 문구)
const formatTTSMessage = (event) => {
  const { eventType, project, summary, severity } = event;
  const urgency = severity === 'critical' ? '긴급' : '중요';
  
  return `${urgency} 알림입니다. ${project} 프로젝트에서 ${eventType} 발생. ${summary}`;
};

// 심각도 이모지
const getSeverityEmoji = (severity) => {
  const emojis = {
    low: '🟢',
    medium: '🟡',
    high: '🟠',
    critical: '🔴'
  };
  return emojis[severity] || '⚪';
};

// 라우팅 정보 반환
const route = (event) => {
  const level = getLevel(event);
  
  return {
    level,
    message: level === 'L2' ? formatL2Message(event) : formatL1Message(event),
    ttsMessage: level === 'L2' ? formatTTSMessage(event) : null,
    channels: level === 'L2' ? ['telegram'] : ['telegram', 'discord'],
    needsTTS: level === 'L2'
  };
};

// CLI 실행
if (require.main === module) {
  const args = process.argv.slice(2);
  
  if (args.length === 0 || args.includes('--help')) {
    console.log(`
Call-Me v1 Event Router

Usage:
  node callme-v1-router.js <event.json>
  node callme-v1-router.js --stdin

Options:
  --stdin    Read JSON from stdin
  --help     Show this help

Example:
  node callme-v1-router.js '{"eventType":"build-failed","project":"api","severity":"high","summary":"빌드 실패","details":"컴파일 에러","retryCount":2,"needApprovalMinutes":45,"occurredAt":"2026-03-01T08:00:00Z"}'
`);
    process.exit(0);
  }
  
  let eventJson;
  
  if (args.includes('--stdin')) {
    let data = '';
    process.stdin.on('data', chunk => data += chunk);
    process.stdin.on('end', () => {
      try {
        const event = JSON.parse(data);
        console.log(JSON.stringify(route(event), null, 2));
      } catch (e) {
        console.error('Error parsing JSON:', e.message);
        process.exit(1);
      }
    });
  } else {
    try {
      eventJson = args[0];
      const event = JSON.parse(eventJson);
      console.log(JSON.stringify(route(event), null, 2));
    } catch (e) {
      console.error('Error parsing JSON:', e.message);
      process.exit(1);
    }
  }
}

module.exports = {
  isL2,
  getLevel,
  formatL1Message,
  formatL2Message,
  formatTTSMessage,
  route
};
