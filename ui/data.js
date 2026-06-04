// data.js — mock data, themes, API client, utilities

// ── Mock data (fallback when server offline) ──────────────────────────────

const MOCK_DIGEST = {
  items: [
    { idx: 1, message_id: "m1", date: "2026-04-18 09:14", sender: "Priya Shah <priya@acme.co>",        subject: "Q2 roadmap sign-off needed by Friday",       summary: "Priya needs your ack on the v2 roadmap before the exec review. Decision required on Track C scope.",            importance: 3, action_items: ["Reply with sign-off", "Review Track C scope"], event: null },
    { idx: 2, message_id: "m2", date: "2026-04-18 08:02", sender: "GitHub <noreply@github.com>",        subject: "3 failing checks on PR #482",                summary: "CI lint + typecheck failing on the latest push to the ascii-glass branch.",                                    importance: 2, action_items: ["Inspect CI logs", "Fix lint errors"], event: null },
    { idx: 3, message_id: "m3", date: "2026-04-17 21:40", sender: "Linear <notifications@linear.app>", subject: "INGEST-214 moved to In Review",               summary: "Merged by dmitri. Awaiting your review comment before the release gate can be cleared.",                      importance: 2, action_items: ["Leave code review comment"], event: null },
    { idx: 4, message_id: "m4", date: "2026-04-17 17:22", sender: "Maya Chen <maya@studio.design>",    subject: "Design sync — Thursday 2pm?",                summary: "Want to walk through the liquid-glass tokens and confirm the typography ramp before handoff.",                importance: 1, action_items: ["Confirm time"], event: { start_datetime: "2026-04-23T14:00:00", end_datetime: "2026-04-23T15:00:00", title: "Design sync with Maya", location: "", notes: "Confirm typography tokens before handoff", confidence: 0.92, timezone: "Europe/London" }, event_preview: "Thu 2pm – Design sync" },
    { idx: 5, message_id: "m5", date: "2026-04-17 12:10", sender: "HR <people@acme.co>",               subject: "Benefits enrollment window closes 04-30",     summary: "Annual enrollment is open. Current elections will auto-renew if no action is taken by the deadline.",         importance: 1, action_items: [], event: null },
    { idx: 6, message_id: "m6", date: "2026-04-16 19:55", sender: "Stripe <receipts@stripe.com>",      subject: "Receipt for your subscription renewal",       summary: "Pro plan renewed for $20.00. Next billing cycle 2026-05-16.",                                                importance: 0, action_items: [], event: null },
    { idx: 7, message_id: "m7", date: "2026-04-16 15:30", sender: "Sam Ortiz <sam@vendor.io>",         subject: "Coffee next week?",                           summary: "Sam is in town 04-22 through 04-24 and wants to grab coffee to catch up on the new project.",               importance: 0, action_items: ["Propose a time"], event: null, event_preview: "Coffee 04-22 to 04-24" },
    { idx: 8, message_id: "m8", date: "2026-04-16 11:08", sender: "Security <security@acme.co>",       subject: "Rotate API keys — deadline 04-25",            summary: "Quarterly key rotation required. Old keys are revoked automatically after the deadline. Both prod and staging.", importance: 3, action_items: ["Rotate prod API key", "Rotate staging API key"], event: null },
  ],
};

const MOCK_CALENDAR = {
  today: '2026-04-21',
  events: [
    { id: 'c1', title: 'Team Standup',         date: '2026-04-21', time: '09:00', duration: 30,  cal: 'Work',     color: '#007AFF' },
    { id: 'c2', title: 'Product Review',        date: '2026-04-21', time: '11:30', duration: 60,  cal: 'Work',     color: '#007AFF' },
    { id: 'c3', title: '1:1 with Manager',      date: '2026-04-22', time: '10:00', duration: 30,  cal: 'Work',     color: '#007AFF' },
    { id: 'c4', title: 'Design sync with Maya', date: '2026-04-23', time: '14:00', duration: 60,  cal: 'Work',     color: '#34C759', fromEmail: 'm4', pending: true },
    { id: 'c5', title: 'Coffee with Sam',       date: '2026-04-24', time: '10:00', duration: 60,  cal: 'Personal', color: '#FF9500', fromEmail: 'm7', pending: true },
    { id: 'c6', title: 'Eng All-Hands',         date: '2026-04-25', time: '14:00', duration: 90,  cal: 'Work',     color: '#007AFF' },
  ],
};

// ── Themes ────────────────────────────────────────────────────────────────

const THEMES = {
  dark: {
    id: 'dark', name: 'DARK.TERM',
    '--bg': '#0d1117', '--bg2': '#161b22',
    '--fg': '#e6edf3', '--fg-dim': '#8b949e', '--fg-muted': '#484f58',
    '--accent': '#58a6ff', '--accent-dim': '#1f6feb',
    '--crit': '#f85149', '--high': '#d29922', '--med': '#58a6ff', '--low': '#484f58',
    '--border': '#30363d', '--border-bright': '#58a6ff', '--row-hover': '#161b22',
  },
  paper: {
    id: 'paper', name: 'PAPER.TERM',
    '--bg': '#f5f0e9', '--bg2': '#ede8df',
    '--fg': '#1a1a1a', '--fg-dim': '#555555', '--fg-muted': '#999999',
    '--accent': '#0a74ff', '--accent-dim': '#0a4ca8',
    '--crit': '#e14b4b', '--high': '#c47a1e', '--med': '#0a74ff', '--low': '#aaaaaa',
    '--border': '#c8bfb0', '--border-bright': '#0a74ff', '--row-hover': '#ede8df',
  },
  amber: {
    id: 'amber', name: 'AMBER.TERM',
    '--bg': '#120d06', '--bg2': '#1c1508',
    '--fg': '#ffb347', '--fg-dim': '#c47a1e', '--fg-muted': '#7a5520',
    '--accent': '#ffcc66', '--accent-dim': '#c47a1e',
    '--crit': '#ff5533', '--high': '#ffcc66', '--med': '#ffb347', '--low': '#7a5520',
    '--border': '#3d2a0e', '--border-bright': '#ffcc66', '--row-hover': '#1c1508',
  },
};

// ── API client — tries local server, falls back to mock ───────────────────

// Same-origin when served by api_server (works in Docker and native alike);
// falls back to the default local port when opened directly as a file://.
const API_BASE =
  (typeof window !== 'undefined' && window.location && window.location.protocol.startsWith('http'))
    ? window.location.origin
    : 'http://127.0.0.1:8000';
let _serverOnline = null; // null = unknown, true/false = cached

const api = {
  async probe() {
    if (_serverOnline !== null) return _serverOnline;
    try {
      const res = await fetch(API_BASE + '/api/digest', {
        cache: 'no-store',
        signal: AbortSignal.timeout(2000),
      });
      _serverOnline = res.ok;
    } catch { _serverOnline = false; }
    return _serverOnline;
  },

  async get(path) {
    try {
      const res = await fetch(API_BASE + path, {
        cache: 'no-store',
        signal: AbortSignal.timeout(5000),
      });
      if (!res.ok) throw new Error(`HTTP ${res.status}`);
      _serverOnline = true;
      return await res.json();
    } catch(e) {
      console.warn(`[api] GET ${path} failed (${e.message}) — using mock`);
      _serverOnline = false;
      return null;
    }
  },

  async post(path, body) {
    try {
      const res = await fetch(API_BASE + path, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(body || {}),
        signal: AbortSignal.timeout(60000),
      });
      const data = await res.json().catch(() => ({}));
      if (!res.ok) throw new Error(data.reason || data.error || `HTTP ${res.status}`);
      _serverOnline = true;
      return data;
    } catch(e) {
      console.warn(`[api] POST ${path} failed (${e.message})`);
      _serverOnline = false;
      return null;
    }
  },

  isOnline() { return _serverOnline === true; },
};

// ── Pix chat — tries local LLM first, falls back to window.claude ─────────

async function pixChat(messages) {
  // Try local server LLM
  const data = await api.post('/api/chat', { messages });
  if (data?.reply) return data.reply;
  // Fall back to window.claude (Haiku via sandbox)
  try {
    return await window.claude.complete({ messages });
  } catch(e) {
    return `[pix offline — ${e.message}]`;
  }
}

// ── Calendar helpers ──────────────────────────────────────────────────────

function generateICS(event) {
  const fmt = dt => (dt || '').replace(/[-:T ]/g, '').slice(0, 15);
  const esc = s => (s || '').replace(/[,;\\]/g, c => '\\' + c);
  const lines = [
    'BEGIN:VCALENDAR',
    'VERSION:2.0',
    'PRODID:-//email_agent//local//EN',
    'CALSCALE:GREGORIAN',
    'BEGIN:VEVENT',
    `DTSTART:${fmt(event.start_datetime)}`,
    `DTEND:${fmt(event.end_datetime)}`,
    `SUMMARY:${esc(event.title)}`,
    `DESCRIPTION:${esc(event.notes || '')}`,
    `LOCATION:${esc(event.location || '')}`,
    `UID:email-agent-${Date.now()}@local`,
    'END:VEVENT',
    'END:VCALENDAR',
  ];
  return lines.join('\r\n');
}

function downloadICS(event) {
  const ics = generateICS(event);
  const blob = new Blob([ics], { type: 'text/calendar;charset=utf-8' });
  const url = URL.createObjectURL(blob);
  const a = document.createElement('a');
  a.href = url;
  a.download = `${(event.title||'event').replace(/\s+/g,'-')}.ics`;
  document.body.appendChild(a);
  a.click();
  document.body.removeChild(a);
  URL.revokeObjectURL(url);
}

async function addToAppleCalendar(item) {
  const event = item.event || buildEventFromPreview(item);
  if (!event) return { ok: false, reason: 'no event data' };
  // Try backend first (uses AppleScript)
  const data = await api.post('/api/calendar-events', {
    idx: item.idx,
    subject: item.subject,
    event,
  });
  if (data?.ok) return { ok: true, method: 'applescript' };
  // Fall back: download ICS (user opens in Calendar)
  downloadICS(event);
  return { ok: true, method: 'ics' };
}

function buildEventFromPreview(item) {
  if (item.event) return item.event;
  if (!item.event_preview) return null;
  const today = new Date('2026-04-21');
  return {
    title: item.subject,
    start_datetime: '2026-04-23T10:00:00',
    end_datetime:   '2026-04-23T11:00:00',
    timezone: 'Europe/London',
    location: '',
    notes: item.summary || '',
    confidence: 0.7,
  };
}

// ── Classification & formatting ───────────────────────────────────────────

function classifyEmail(item) {
  if (item.event || item.event_preview) return 'schedule';
  const actions = (item.action_items || []).join(' ').toLowerCase();
  if (/reply|sign.off|confirm|respond|propose/.test(actions)) return 'respond';
  if (item.importance >= 2 && (item.action_items || []).length > 0) return 'decide';
  return 'inbox';
}

function impTag(level) {
  if (level >= 3) return '[!!!]';
  if (level === 2) return '[!! ]';
  if (level === 1) return '[!  ]';
  return '[···]';
}
function impColor(level) {
  if (level >= 3) return 'var(--crit)';
  if (level === 2) return 'var(--high)';
  if (level === 1) return 'var(--med)';
  return 'var(--low)';
}
function shortDate(d) {
  if (!d) return '--/--';
  const p = (d.split(' ')[0]||'').split('-');
  return p.length >= 3 ? `${p[1]}-${p[2]}` : d.slice(5,10);
}
function shortSender(s) {
  if (!s) return 'unknown';
  const m = s.match(/^([^<]+)</);
  return m ? m[1].trim() : s.split('@')[0];
}
function extractEmail(s) {
  const m = (s||'').match(/<([^>]+)>/);
  return m ? m[1] : s;
}
function fmtDuration(min) {
  return min >= 60 ? `${min/60}h` : `${min}m`;
}
function dayLabel(dateStr) {
  const d = new Date(dateStr + 'T12:00:00');
  const today = new Date('2026-04-21T12:00:00');
  const diff = Math.round((d - today) / 86400000);
  if (diff === 0) return 'TODAY';
  if (diff === 1) return 'TOMORROW';
  return d.toLocaleDateString('en-US', { weekday:'short', month:'short', day:'numeric' }).toUpperCase();
}
