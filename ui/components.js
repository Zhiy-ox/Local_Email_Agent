// components.jsx — all UI components, exported to window
const { useState, useEffect, useRef } = React;

// ── Hooks ──────────────────────────────────────────────────────────────────

function useSpinner(active) {
  const frames = '⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏';
  const [f, setF] = useState(0);
  useEffect(() => {
    if (!active) return;
    const id = setInterval(() => setF(n => (n+1) % frames.length), 90);
    return () => clearInterval(id);
  }, [active]);
  return active ? frames[f] : '';
}

function useTypewriter(text, speed, trigger) {
  const [out, setOut] = useState('');
  useEffect(() => {
    if (!trigger || !text) { setOut(text || ''); return; }
    setOut(''); let i = 0;
    const id = setInterval(() => { i++; setOut(text.slice(0,i)); if (i >= text.length) clearInterval(id); }, speed||12);
    return () => clearInterval(id);
  }, [text, trigger]);
  return out;
}

// ── AsciiBtn ───────────────────────────────────────────────────────────────

function AsciiBtn({ children, onClick, danger, accent, disabled, small, style }) {
  const [hov, setHov] = useState(false);
  const bc = disabled ? 'var(--fg-muted)'
    : danger  ? (hov ? 'var(--crit)' : 'var(--border)')
    : accent  ? (hov ? 'var(--accent)' : 'var(--accent-dim)')
    : hov     ? 'var(--accent)' : 'var(--border)';
  const col = disabled ? 'var(--fg-muted)'
    : danger  ? (hov ? 'var(--crit)' : 'var(--fg-muted)')
    : accent  ? 'var(--accent)'
    : hov     ? 'var(--accent)' : 'var(--fg-dim)';
  return (
    <button
      onClick={disabled ? undefined : onClick}
      onMouseEnter={() => !disabled && setHov(true)}
      onMouseLeave={() => setHov(false)}
      style={{
        background: accent && hov ? 'rgba(88,166,255,0.1)' : 'transparent',
        border: `1px solid ${bc}`, color: col,
        fontFamily: 'inherit', fontSize: small ? 10 : 11,
        letterSpacing: '0.07em', padding: small ? '2px 8px' : '4px 11px',
        cursor: disabled ? 'not-allowed' : 'pointer',
        transition: 'border-color 120ms, color 120ms, background 120ms',
        whiteSpace: 'nowrap', ...style,
      }}
    >
      [{children}]
    </button>
  );
}

// ── ZoneHeader ─────────────────────────────────────────────────────────────

function ZoneHeader({ title, count, accent, muted, right }) {
  return (
    <div style={{ padding: '7px 14px 6px', borderBottom: '1px dashed var(--border)', background: 'var(--bg2)', display: 'flex', justifyContent: 'space-between', alignItems: 'center' }}>
      <span style={{ fontSize: 10, letterSpacing: '0.14em', fontWeight: 600, color: accent ? 'var(--accent)' : muted ? 'var(--fg-muted)' : 'var(--fg-dim)' }}>
        <span style={{ color: 'var(--accent)', opacity: muted ? 0.4 : 1 }}>// </span>{title}
      </span>
      <div style={{ display: 'flex', gap: 8, alignItems: 'center' }}>
        {right}
        {count !== undefined && (
          <span style={{ fontSize: 10, color: 'var(--fg-muted)', border: '1px solid var(--border)', padding: '1px 7px', letterSpacing: '0.06em' }}>
            [{String(count).padStart(2,'0')}]
          </span>
        )}
      </div>
    </div>
  );
}

// ── ServerBadge ────────────────────────────────────────────────────────────

function ServerBadge({ online }) {
  return (
    <div style={{ display: 'flex', alignItems: 'center', gap: 5, fontSize: 9, color: 'var(--fg-muted)', letterSpacing: '0.08em' }}>
      <span style={{ width: 6, height: 6, borderRadius: '50%', background: online ? '#34C759' : '#FF3B30', display: 'inline-block', flexShrink: 0 }} />
      {online ? 'local llm · online' : 'offline · mock mode'}
    </div>
  );
}

// ── DraftPanel ─────────────────────────────────────────────────────────────

function DraftPanel({ item, onClose }) {
  const [draft, setDraft]   = useState('');
  const [busy,  setBusy]    = useState(true);
  const [copied, setCopied] = useState(false);
  const spin = useSpinner(busy);

  useEffect(() => {
    let cancelled = false;
    setBusy(true); setDraft('');
    pixChat([{ role: 'user', content:
      `Draft a concise professional reply (2–4 sentences, no subject line, no greeting, no sign-off) to:\nSubject: ${item.subject}\nFrom: ${item.sender}\nContext: ${item.summary}\nAction needed: ${(item.action_items||[]).join(', ')}`
    }]).then(reply => {
      if (!cancelled) { setDraft(reply); setBusy(false); }
    }).catch(e => {
      if (!cancelled) { setDraft(`[draft error: ${e.message}]`); setBusy(false); }
    });
    return () => { cancelled = true; };
  }, [item.message_id]);

  const copy = () => {
    navigator.clipboard.writeText(draft).catch(()=>{});
    setCopied(true); setTimeout(() => setCopied(false), 1800);
  };

  return (
    <div style={{ margin: '0 14px 10px', border: '1px solid var(--accent-dim)', background: 'var(--bg2)', animation: 'rowIn 150ms ease' }}>
      <div style={{ padding: '6px 10px', borderBottom: '1px dashed var(--border)', display: 'flex', justifyContent: 'space-between', alignItems: 'center' }}>
        <span style={{ fontSize: 10, color: 'var(--accent)', letterSpacing: '0.1em' }}>
          pix{'>'} {busy ? `${spin} drafting reply…` : 'draft ready — edit before sending'}
        </span>
        <AsciiBtn onClick={onClose} danger small>close</AsciiBtn>
      </div>
      {busy
        ? <div style={{ padding: '10px 12px', color: 'var(--fg-muted)', fontSize: 11 }}>{spin} generating…</div>
        : <>
            <textarea value={draft} onChange={e => setDraft(e.target.value)} style={{ display: 'block', width: '100%', background: 'transparent', border: 'none', outline: 'none', color: 'var(--fg)', fontFamily: 'inherit', fontSize: 12, lineHeight: 1.6, padding: '10px 12px', resize: 'vertical', minHeight: 80 }} />
            <div style={{ padding: '6px 10px', borderTop: '1px dashed var(--border)', display: 'flex', gap: 6 }}>
              <AsciiBtn onClick={copy} accent small>{copied ? '✓ copied' : 'copy draft'}</AsciiBtn>
              <AsciiBtn onClick={() => { setBusy(true); setDraft(''); }} small>regenerate</AsciiBtn>
            </div>
          </>
      }
    </div>
  );
}

// ── ComposeModal ───────────────────────────────────────────────────────────

function ComposeModal({ item, onClose }) {
  const [to,      setTo]      = useState(extractEmail(item?.sender || ''));
  const [subject, setSubject] = useState(`Re: ${item?.subject || ''}`);
  const [body,    setBody]    = useState('');
  const [drafting, setDrafting] = useState(true);
  const [copied,   setCopied]   = useState(false);
  const [sent,     setSent]     = useState(false);
  const spin = useSpinner(drafting);

  useEffect(() => {
    const h = e => { if (e.key === 'Escape') onClose(); };
    window.addEventListener('keydown', h);
    return () => window.removeEventListener('keydown', h);
  }, [onClose]);

  useEffect(() => {
    if (!item) return;
    setDrafting(true);
    pixChat([{ role: 'user', content:
      `Draft a concise professional email reply (3–5 sentences). No subject line. No greeting. No sign-off.\n\nOriginal email:\nSubject: ${item.subject}\nFrom: ${item.sender}\nContext: ${item.summary}\nAction items: ${(item.action_items||[]).join(', ')}`
    }]).then(reply => { setBody(reply); setDrafting(false); })
       .catch(e  => { setBody(`[error: ${e.message}]`); setDrafting(false); });
  }, [item?.message_id]);

  const handleSend = () => {
    const mailto = `mailto:${encodeURIComponent(to)}?subject=${encodeURIComponent(subject)}&body=${encodeURIComponent(body)}`;
    window.open(mailto);
    setSent(true);
    setTimeout(onClose, 900);
  };

  const copy = () => {
    navigator.clipboard.writeText(body).catch(()=>{});
    setCopied(true); setTimeout(() => setCopied(false), 1800);
  };

  if (!item) return null;
  const level = Math.max(0, Math.min(3, Number(item.importance||0)));

  return (
    <div onClick={onClose} style={{ position: 'fixed', inset: 0, zIndex: 1100, background: 'rgba(0,0,0,0.75)', display: 'flex', alignItems: 'center', justifyContent: 'center', padding: 24, animation: 'fadeIn 100ms ease' }}>
      <div onClick={e => e.stopPropagation()} style={{ width: '100%', maxWidth: 680, background: 'var(--bg)', border: '1px solid var(--border-bright)', fontFamily: 'inherit', animation: 'modalIn 150ms ease' }}>

        {/* Header */}
        <div style={{ padding: '9px 14px', borderBottom: '1px solid var(--border)', background: 'var(--bg2)', display: 'flex', justifyContent: 'space-between', alignItems: 'center' }}>
          <span style={{ color: 'var(--accent)', fontSize: 11, letterSpacing: '0.1em', fontWeight: 600 }}>
            ╔═ COMPOSE.REPLY :: {item.message_id}
          </span>
          <AsciiBtn onClick={onClose} danger>× close</AsciiBtn>
        </div>

        {/* Original context bar */}
        <div style={{ padding: '8px 14px', background: 'var(--bg2)', borderBottom: '1px dashed var(--border)', fontSize: 11, color: 'var(--fg-muted)' }}>
          <span style={{ color: impColor(level), marginRight: 8 }}>{impTag(level)}</span>
          <span style={{ color: 'var(--fg-dim)' }}>{item.subject}</span>
          <span style={{ marginLeft: 8 }}>· from {shortSender(item.sender)}</span>
        </div>

        {/* Fields */}
        <div style={{ padding: '10px 14px', borderBottom: '1px dashed var(--border)', display: 'grid', gap: 6 }}>
          {[['to', to, setTo], ['subject', subject, setSubject]].map(([label, val, setVal]) => (
            <div key={label} style={{ display: 'flex', gap: 10, alignItems: 'center' }}>
              <span style={{ fontSize: 11, color: 'var(--fg-muted)', minWidth: 44 }}>{label}:</span>
              <input value={val} onChange={e => setVal(e.target.value)} style={{ flex: 1, background: 'transparent', border: 'none', borderBottom: '1px solid var(--border)', outline: 'none', color: 'var(--fg)', fontFamily: 'inherit', fontSize: 12, padding: '2px 0', transition: 'border-color 150ms' }}
                onFocus={e => e.target.style.borderBottomColor = 'var(--accent)'}
                onBlur={e  => e.target.style.borderBottomColor = 'var(--border)'}
              />
            </div>
          ))}
        </div>

        {/* Body */}
        <div style={{ padding: '8px 14px', borderBottom: '1px dashed var(--border)' }}>
          <div style={{ fontSize: 10, color: 'var(--accent)', letterSpacing: '0.1em', marginBottom: 6 }}>
            pix{'>'} {drafting ? `${spin} drafting…` : 'draft ready — edit freely'}
          </div>
          {drafting
            ? <div style={{ color: 'var(--fg-muted)', fontSize: 11, padding: '8px 0' }}>{spin} generating draft…</div>
            : <textarea value={body} onChange={e => setBody(e.target.value)} style={{ display: 'block', width: '100%', background: 'var(--bg2)', border: '1px solid var(--border)', outline: 'none', color: 'var(--fg)', fontFamily: 'inherit', fontSize: 12, lineHeight: 1.65, padding: '10px 12px', resize: 'vertical', minHeight: 120,
                transition: 'border-color 150ms' }}
                onFocus={e => e.target.style.borderColor = 'var(--accent)'}
                onBlur={e  => e.target.style.borderColor = 'var(--border)'}
              />
          }
        </div>

        {/* Actions */}
        <div style={{ padding: '10px 14px', background: 'var(--bg2)', display: 'flex', gap: 8, alignItems: 'center' }}>
          <AsciiBtn onClick={handleSend} accent disabled={drafting || sent}>
            {sent ? '✓ opening mail…' : 'send via mail ↗'}
          </AsciiBtn>
          <AsciiBtn onClick={copy} disabled={drafting}>{copied ? '✓ copied' : 'copy body'}</AsciiBtn>
          <span style={{ marginLeft: 'auto', fontSize: 10, color: 'var(--fg-muted)' }}>opens your default mail client</span>
        </div>
      </div>
    </div>
  );
}

// ── ActionEmailRow ─────────────────────────────────────────────────────────

function ActionEmailRow({ item, zone, onOpen, onDone, onAskPix, onCompose }) {
  const [hov, setHov]             = useState(false);
  const [draftOpen, setDraftOpen] = useState(false);
  const [done, setDone]           = useState(false);
  const level = Math.max(0, Math.min(3, Number(item.importance||0)));
  const color = impColor(level);
  if (done) return null;

  return (
    <div style={{ borderBottom: '1px solid var(--border)', animation: 'rowIn 140ms ease both' }}>
      <div
        onMouseEnter={() => setHov(true)}
        onMouseLeave={() => setHov(false)}
        onClick={() => onOpen(item)}
        style={{ display: 'grid', gridTemplateColumns: '46px 1fr 80px', gap: 10, alignItems: 'start', padding: '8px 14px 6px', background: hov ? 'var(--row-hover)' : 'transparent', borderLeft: `2px solid ${hov ? color : 'transparent'}`, transition: 'background 110ms, border-color 110ms', cursor: 'pointer' }}
      >
        <span style={{ color, fontWeight: 600, fontSize: 11, paddingTop: 1 }}>{impTag(level)}</span>
        <div>
          <div style={{ fontSize: 12, color: 'var(--fg)', marginBottom: 2, lineHeight: 1.35 }}>
            <span style={{ color: 'var(--accent)', opacity: hov ? 1 : 0, transition: 'opacity 100ms' }}>▶ </span>
            {item.subject}
          </div>
          <div style={{ fontSize: 11, color: 'var(--fg-muted)', lineHeight: 1.4, overflow: 'hidden', display: '-webkit-box', WebkitLineClamp: 2, WebkitBoxOrient: 'vertical' }}>
            {item.summary}
          </div>
        </div>
        <div style={{ textAlign: 'right' }}>
          <div style={{ fontSize: 10, color: 'var(--fg-muted)' }}>{shortDate(item.date)}</div>
          <div style={{ fontSize: 10, color: 'var(--fg-muted)', marginTop: 1, overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap', maxWidth: 78 }}>{shortSender(item.sender)}</div>
        </div>
      </div>
      <div style={{ padding: '0 14px 8px', display: 'flex', gap: 6, flexWrap: 'wrap' }} onClick={e => e.stopPropagation()}>
        {zone === 'respond' && <>
          <AsciiBtn onClick={() => onCompose(item)} accent small>compose reply ↗</AsciiBtn>
          <AsciiBtn onClick={() => setDraftOpen(v => !v)} small>{draftOpen ? 'hide draft' : 'draft reply'}</AsciiBtn>
        </>}
        {zone === 'decide' && (
          <AsciiBtn onClick={() => { setDone(true); onDone && onDone(item); }} accent small>✓ mark done</AsciiBtn>
        )}
        <AsciiBtn onClick={() => onAskPix(item)} small>ask pix</AsciiBtn>
        <AsciiBtn onClick={() => { setDone(true); onDone && onDone(item); }} danger small>archive</AsciiBtn>
      </div>
      {draftOpen && <DraftPanel item={item} onClose={() => setDraftOpen(false)} />}
    </div>
  );
}

// ── ScheduleRow ────────────────────────────────────────────────────────────

function ScheduleRow({ item, onOpen, onAskPix, added, onAdd }) {
  const [hov,    setHov]    = useState(false);
  const [status, setStatus] = useState('');
  const [busy,   setBusy]   = useState(false);
  const spin = useSpinner(busy);
  const ev = item.event;
  const datetime = ev?.start_datetime?.replace('T',' ').slice(0,16) || item.event_preview || '';
  const duration = ev ? fmtDuration(Math.round((new Date(ev.end_datetime) - new Date(ev.start_datetime)) / 60000)) : '';

  const handleAdd = async (e) => {
    e.stopPropagation();
    setBusy(true); setStatus('');
    const result = await addToAppleCalendar(item);
    setBusy(false);
    if (result.ok) {
      setStatus(result.method === 'applescript' ? '✓ added via Calendar' : '✓ .ics downloaded — open to add');
      onAdd && onAdd(item);
    } else {
      setStatus(`! ${result.reason}`);
    }
  };

  return (
    <div style={{ borderBottom: '1px solid var(--border)', animation: 'rowIn 140ms ease both' }}>
      <div onMouseEnter={() => setHov(true)} onMouseLeave={() => setHov(false)} onClick={() => onOpen(item)}
        style={{ display: 'grid', gridTemplateColumns: '20px 150px 1fr', gap: 10, alignItems: 'start', padding: '8px 14px 6px', background: hov ? 'var(--row-hover)' : 'transparent', borderLeft: `2px solid ${hov ? 'var(--accent)' : 'transparent'}`, transition: 'background 110ms, border-color 110ms', cursor: 'pointer' }}>
        <span style={{ color: 'var(--accent)', fontSize: 13 }}>◈</span>
        <div>
          <div style={{ fontSize: 11, color: 'var(--accent)', fontWeight: 600 }}>{datetime}</div>
          {duration && <div style={{ fontSize: 10, color: 'var(--fg-muted)' }}>{duration}</div>}
        </div>
        <div>
          <div style={{ fontSize: 12, color: 'var(--fg)' }}>
            <span style={{ color: 'var(--accent)', opacity: hov ? 1 : 0, transition: 'opacity 100ms' }}>▶ </span>
            {item.subject}
          </div>
          <div style={{ fontSize: 11, color: 'var(--fg-muted)', marginTop: 2, overflow: 'hidden', display: '-webkit-box', WebkitLineClamp: 1, WebkitBoxOrient: 'vertical' }}>{item.summary}</div>
        </div>
      </div>
      <div style={{ padding: '0 14px 8px', display: 'flex', gap: 6, flexWrap: 'wrap', alignItems: 'center' }} onClick={e => e.stopPropagation()}>
        <AsciiBtn onClick={handleAdd} accent={!added} disabled={busy} small>
          {busy ? `${spin} adding…` : added ? '✓ added to calendar' : '→ Apple Calendar'}
        </AsciiBtn>
        <AsciiBtn onClick={() => onAskPix(item)} small>refine time</AsciiBtn>
        <AsciiBtn onClick={() => onAskPix(item)} small>ask pix</AsciiBtn>
        {status && <span style={{ fontSize: 10, color: status.startsWith('!') ? 'var(--crit)' : 'var(--accent)', letterSpacing: '0.06em' }}>{status}</span>}
      </div>
    </div>
  );
}

// ── InboxRow ───────────────────────────────────────────────────────────────

function InboxRow({ item, onOpen }) {
  const [hov, setHov] = useState(false);
  const level = Math.max(0, Math.min(3, Number(item.importance||0)));
  return (
    <div onClick={() => onOpen(item)} onMouseEnter={() => setHov(true)} onMouseLeave={() => setHov(false)}
      style={{ display: 'grid', gridTemplateColumns: '46px 1fr 70px', gap: 10, alignItems: 'center', padding: '5px 14px', background: hov ? 'var(--row-hover)' : 'transparent', borderLeft: `2px solid ${hov ? impColor(level) : 'transparent'}`, transition: 'background 110ms, border-color 110ms', cursor: 'pointer', opacity: 0.65, borderBottom: '1px solid var(--border)', animation: 'rowIn 140ms ease both' }}>
      <span style={{ color: impColor(level), fontSize: 11, fontWeight: 600 }}>{impTag(level)}</span>
      <span style={{ fontSize: 12, color: 'var(--fg-dim)', overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap' }}>
        <span style={{ color: 'var(--accent)', opacity: hov ? 1 : 0, transition: 'opacity 100ms' }}>▶ </span>
        {item.subject}
      </span>
      <span style={{ fontSize: 10, color: 'var(--fg-muted)', textAlign: 'right' }}>{shortDate(item.date)}</span>
    </div>
  );
}

// ── CalendarPanel ──────────────────────────────────────────────────────────

function CalendarPanel({ pendingIds }) {
  const today    = MOCK_CALENDAR.today;
  const todayEv  = MOCK_CALENDAR.events.filter(e => e.date === today);
  const upcoming = MOCK_CALENDAR.events.filter(e => e.date > today);
  const byDate   = {};
  upcoming.forEach(e => { (byDate[e.date] = byDate[e.date]||[]).push(e); });

  return (
    <div style={{ height: '100%', display: 'flex', flexDirection: 'column' }}>
      <ZoneHeader title="CALENDAR" right={
        <div style={{ display: 'flex', alignItems: 'center', gap: 5 }}>
          <span style={{ width: 8, height: 8, borderRadius: '50%', background: '#FF3B30', display: 'inline-block' }} />
          <span style={{ fontSize: 9, color: 'var(--fg-muted)', letterSpacing: '0.08em' }}>Apple Calendar</span>
        </div>
      } />
      <div style={{ flex: 1, overflowY: 'auto', padding: '8px 0' }}>
        <div style={{ padding: '2px 12px 4px', fontSize: 9, color: 'var(--accent)', letterSpacing: '0.14em', fontWeight: 600 }}>
          TODAY · APR 21
        </div>
        {todayEv.length === 0
          ? <div style={{ padding: '4px 12px', fontSize: 11, color: 'var(--fg-muted)' }}>╌╌ no events ╌╌</div>
          : todayEv.map(e => <CalEvent key={e.id} ev={e} isPending={pendingIds.has(e.fromEmail)} />)
        }
        <div style={{ padding: '10px 12px 4px', fontSize: 9, color: 'var(--fg-muted)', letterSpacing: '0.14em', fontWeight: 600 }}>UPCOMING</div>
        {Object.entries(byDate).sort(([a],[b]) => a>b?1:-1).map(([date, evs]) => (
          <div key={date}>
            <div style={{ padding: '4px 12px 2px', fontSize: 9, color: 'var(--fg-muted)', letterSpacing: '0.08em' }}>{dayLabel(date)}</div>
            {evs.map(e => <CalEvent key={e.id} ev={e} isPending={pendingIds.has(e.fromEmail)} />)}
          </div>
        ))}
        <div style={{ padding: '12px 12px 4px', fontSize: 9, color: 'var(--fg-muted)', letterSpacing: '0.06em', borderTop: '1px dashed var(--border)', marginTop: 8 }}>
          <span style={{ width: 6, height: 6, borderRadius: '50%', background: '#34C759', display: 'inline-block', marginRight: 5, verticalAlign: 'middle' }} />
          synced · 2 min ago
        </div>
      </div>
    </div>
  );
}

function CalEvent({ ev, isPending }) {
  const [hov, setHov] = useState(false);
  return (
    <div onMouseEnter={() => setHov(true)} onMouseLeave={() => setHov(false)}
      style={{ display: 'flex', gap: 8, alignItems: 'flex-start', padding: '4px 12px', background: hov ? 'var(--row-hover)' : 'transparent', transition: 'background 110ms' }}>
      <div style={{ width: 3, alignSelf: 'stretch', background: ev.color, borderRadius: 2, flexShrink: 0, marginTop: 2 }} />
      <div style={{ flex: 1, minWidth: 0 }}>
        <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', gap: 4 }}>
          <span style={{ fontSize: 11, color: isPending ? 'var(--accent)' : 'var(--fg)', fontWeight: isPending ? 600 : 400, overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap' }}>
            {isPending && <span style={{ color: 'var(--accent)', marginRight: 4 }}>◈</span>}
            {ev.title}
          </span>
          {isPending && <span style={{ fontSize: 9, color: 'var(--accent)', border: '1px solid var(--accent-dim)', padding: '1px 4px', flexShrink: 0 }}>pending</span>}
        </div>
        <div style={{ fontSize: 10, color: 'var(--fg-muted)' }}>{ev.time} · {fmtDuration(ev.duration)}</div>
      </div>
    </div>
  );
}

// ── DetailModal ────────────────────────────────────────────────────────────

function DetailModal({ item, onClose, onAskPix, onCompose }) {
  const [ready, setReady] = useState(false);
  const level = item ? Math.max(0, Math.min(3, Number(item.importance||0))) : 0;
  const color = impColor(level);
  const titleTyped = useTypewriter(item?.subject||'', 14, ready);
  const summTyped  = useTypewriter(item?.summary||'',  7,  ready);

  useEffect(() => {
    if (!item) return;
    setReady(false);
    const t = setTimeout(() => setReady(true), 40);
    return () => clearTimeout(t);
  }, [item?.message_id]);

  useEffect(() => {
    const h = e => { if (e.key === 'Escape') onClose(); };
    window.addEventListener('keydown', h);
    return () => window.removeEventListener('keydown', h);
  }, [onClose]);

  if (!item) return null;

  return (
    <div onClick={onClose} style={{ position: 'fixed', inset: 0, zIndex: 1000, background: 'rgba(0,0,0,0.72)', display: 'flex', alignItems: 'center', justifyContent: 'center', padding: 24, animation: 'fadeIn 100ms ease' }}>
      <div onClick={e => e.stopPropagation()} style={{ width: '100%', maxWidth: 640, background: 'var(--bg)', border: '1px solid var(--border-bright)', fontFamily: 'inherit', animation: 'modalIn 150ms ease' }}>
        <div style={{ padding: '9px 14px', borderBottom: '1px solid var(--border)', background: 'var(--bg2)', display: 'flex', justifyContent: 'space-between', alignItems: 'center' }}>
          <span style={{ color: 'var(--accent)', fontSize: 11, letterSpacing: '0.1em', fontWeight: 600 }}>╔═ EMAIL.DETAIL :: {item.message_id}</span>
          <AsciiBtn onClick={onClose} danger>× close</AsciiBtn>
        </div>
        <div style={{ padding: '12px 16px', borderBottom: '1px dashed var(--border)' }}>
          {[['from', item.sender], ['date', item.date], ['imp ', <span style={{ color }}>{impTag(level)} {level>=3?'CRITICAL':level===2?'HIGH':level===1?'MEDIUM':'LOW'}</span>]].map(([k,v]) => (
            <div key={k} style={{ display: 'flex', gap: 12, marginBottom: 4, fontSize: 12 }}>
              <span style={{ color: 'var(--fg-muted)', minWidth: 36 }}>{k}:</span>
              <span style={{ color: 'var(--fg-dim)' }}>{v}</span>
            </div>
          ))}
          <div style={{ display: 'flex', gap: 12, marginTop: 10, fontSize: 13, fontWeight: 600 }}>
            <span style={{ color: 'var(--fg-muted)', minWidth: 36 }}>subj:</span>
            <span>{titleTyped}{titleTyped.length < (item.subject||'').length && <span style={{ animation: 'blink 0.6s steps(2,end) infinite' }}>█</span>}</span>
          </div>
        </div>
        <div style={{ padding: '12px 16px', borderBottom: '1px dashed var(--border)' }}>
          <div style={{ color: 'var(--fg-muted)', fontSize: 10, letterSpacing: '0.13em', marginBottom: 7 }}>// SUMMARY</div>
          <div style={{ color: 'var(--fg-dim)', lineHeight: 1.65, fontSize: 12 }}>
            {summTyped}{summTyped.length < (item.summary||'').length && <span style={{ animation: 'blink 0.6s steps(2,end) infinite' }}>█</span>}
          </div>
        </div>
        {(item.action_items||[]).length > 0 && (
          <div style={{ padding: '12px 16px', borderBottom: '1px dashed var(--border)' }}>
            <div style={{ color: 'var(--fg-muted)', fontSize: 10, letterSpacing: '0.13em', marginBottom: 8 }}>// ACTION_ITEMS</div>
            {item.action_items.map((a,i) => (
              <div key={i} style={{ display: 'flex', gap: 10, marginBottom: 5, fontSize: 12 }}>
                <span style={{ color: 'var(--accent)' }}>○</span><span>{a}</span>
              </div>
            ))}
          </div>
        )}
        {item.event && (
          <div style={{ padding: '10px 16px', borderBottom: '1px dashed var(--border)' }}>
            <div style={{ color: 'var(--fg-muted)', fontSize: 10, letterSpacing: '0.13em', marginBottom: 6 }}>// EVENT_DETECTED</div>
            <div style={{ fontSize: 12, color: 'var(--fg-dim)' }}>◈ {item.event.title} · {item.event.start_datetime?.replace('T',' ').slice(0,16)}</div>
          </div>
        )}
        <div style={{ padding: '10px 16px', display: 'flex', gap: 8, flexWrap: 'wrap', background: 'var(--bg2)' }}>
          {(classifyEmail(item) === 'respond') && <AsciiBtn onClick={() => { onCompose(item); onClose(); }} accent>compose reply ↗</AsciiBtn>}
          <AsciiBtn onClick={() => { onAskPix(item); onClose(); }}>ask pix</AsciiBtn>
          <AsciiBtn onClick={onClose}>close</AsciiBtn>
        </div>
      </div>
    </div>
  );
}

// ── ChatMessage ────────────────────────────────────────────────────────────

function ChatMessage({ msg, animate }) {
  const text = useTypewriter(msg.content, 9, animate && msg.role==='assistant');
  const displayed = (animate && msg.role==='assistant') ? text : msg.content;
  const typing = animate && msg.role==='assistant' && displayed.length < msg.content.length;
  return (
    <div style={{ marginBottom: 8, animation: 'rowIn 120ms ease both' }}>
      <span style={{ color: msg.role==='assistant' ? 'var(--accent)' : 'var(--fg-muted)', fontSize: 10, letterSpacing: '0.08em' }}>
        {msg.role==='assistant' ? 'pix>' : 'you>'}
      </span>{' '}
      <span style={{ color: msg.role==='assistant' ? 'var(--fg)' : 'var(--fg-dim)', fontSize: 12, whiteSpace: 'pre-wrap' }}>
        {displayed}{typing && <span style={{ animation: 'blink 0.6s steps(2,end) infinite' }}>█</span>}
      </span>
    </div>
  );
}

// ── TweaksPanel ────────────────────────────────────────────────────────────

function TweaksPanel({ visible, theme, onTheme, serverOnline }) {
  if (!visible) return null;
  return (
    <div style={{ position: 'fixed', bottom: 20, right: 20, zIndex: 2000, background: 'var(--bg2)', border: '1px solid var(--border-bright)', padding: '14px 16px', minWidth: 210, animation: 'fadeIn 150ms ease', fontFamily: 'inherit' }}>
      <div style={{ color: 'var(--accent)', fontSize: 10, letterSpacing: '0.14em', marginBottom: 12, fontWeight: 600 }}>// TWEAKS</div>
      <div style={{ marginBottom: 12 }}><ServerBadge online={serverOnline} /></div>
      <div style={{ color: 'var(--fg-muted)', fontSize: 10, letterSpacing: '0.1em', marginBottom: 8 }}>THEME</div>
      {Object.values(THEMES).map(t => (
        <button key={t.id} onClick={() => onTheme(t.id)} style={{ display: 'block', width: '100%', background: 'transparent', border: `1px solid ${theme===t.id ? 'var(--accent)' : 'var(--border)'}`, color: theme===t.id ? 'var(--accent)' : 'var(--fg-dim)', padding: '5px 10px', fontSize: 11, letterSpacing: '0.08em', marginBottom: 5, textAlign: 'left', fontFamily: 'inherit', cursor: 'pointer', transition: 'border-color 130ms, color 130ms' }}>
          {theme===t.id ? '▶ ' : '  '}{t.name}
        </button>
      ))}
    </div>
  );
}

// ── Exports ────────────────────────────────────────────────────────────────

Object.assign(window, {
  useSpinner, useTypewriter,
  AsciiBtn, ZoneHeader, ServerBadge,
  DraftPanel, ComposeModal,
  ActionEmailRow, ScheduleRow, InboxRow,
  CalendarPanel, CalEvent,
  DetailModal, ChatMessage, TweaksPanel,
});
