// app.jsx — email_agent ~/desk
const { useState, useEffect, useRef, useMemo, useCallback } = React;

function EmptyRow({ label }) {
  return <div style={{ padding: '10px 14px', color: 'var(--fg-muted)', fontSize: 11 }}>╌╌ {label} ╌╌</div>;
}

function StatusBar({ items, refreshing, spinner, serverOnline }) {
  const respond  = items.filter(i => classifyEmail(i) === 'respond').length;
  const decide   = items.filter(i => classifyEmail(i) === 'decide').length;
  const schedule = items.filter(i => classifyEmail(i) === 'schedule').length;
  const crit     = items.filter(i => i.importance >= 3).length;
  return (
    <div style={{ padding: '5px 16px', borderTop: '1px solid var(--border)', background: 'var(--bg2)', display: 'flex', gap: 18, alignItems: 'center', fontSize: 10, color: 'var(--fg-muted)', letterSpacing: '0.06em' }}>
      <span>respond::<strong style={{ color: respond > 0 ? 'var(--fg)' : 'var(--fg-muted)' }}>{String(respond).padStart(2,'0')}</strong></span>
      <span>decide::<strong style={{ color: decide > 0 ? 'var(--fg)' : 'var(--fg-muted)' }}>{String(decide).padStart(2,'0')}</strong></span>
      <span>schedule::<strong style={{ color: schedule > 0 ? 'var(--accent)' : 'var(--fg-muted)' }}>{String(schedule).padStart(2,'0')}</strong></span>
      {crit > 0 && <span>critical::<strong style={{ color: 'var(--crit)' }}>{String(crit).padStart(2,'0')}</strong></span>}
      {refreshing && <span style={{ color: 'var(--accent)' }}>{spinner} syncing…</span>}
      <div style={{ marginLeft: 'auto', display: 'flex', alignItems: 'center', gap: 5 }}>
        <span style={{ width: 6, height: 6, borderRadius: '50%', background: serverOnline ? '#34C759' : '#FF9500', display: 'inline-block' }} />
        <span>{serverOnline ? 'server · http://127.0.0.1:8000' : 'mock mode · start api_server.py to go live'}</span>
      </div>
    </div>
  );
}

function App() {
  const [themeId,       setThemeId]       = useState(() => localStorage.getItem('ea-theme') || TWEAK_DEFAULTS.theme || 'dark');
  const [digestItems,   setDigestItems]   = useState(MOCK_DIGEST.items);
  const [serverOnline,  setServerOnline]  = useState(false);
  const [selectedItem,  setSelectedItem]  = useState(null);
  const [composeItem,   setComposeItem]   = useState(null);
  const [pendingCalIds, setPendingCalIds] = useState(new Set(['m4', 'm7']));
  const [archivedIds,   setArchivedIds]   = useState(new Set());
  const [chatMessages,  setChatMessages]  = useState([
    { role: 'assistant', content: 'I am Pix, running locally. Hit [compose reply ↗] on any email to draft a reply, or [→ Apple Calendar] to schedule an event. Ask me anything below.' }
  ]);
  const [chatInput,     setChatInput]     = useState('');
  const [chatBusy,      setChatBusy]      = useState(false);
  const [lastAnimIdx,   setLastAnimIdx]   = useState(0);
  const [refreshing,    setRefreshing]    = useState(false);
  const [tweaksVisible, setTweaksVisible] = useState(false);
  const chatEndRef = useRef(null);
  const spinner = useSpinner(refreshing || chatBusy);

  // Apply CSS theme vars
  useEffect(() => {
    const theme = THEMES[themeId] || THEMES.dark;
    Object.entries(theme).forEach(([k, v]) => {
      if (k.startsWith('--')) document.documentElement.style.setProperty(k, v);
    });
    localStorage.setItem('ea-theme', themeId);
    window.parent.postMessage({ type: '__edit_mode_set_keys', edits: { theme: themeId } }, '*');
  }, [themeId]);

  // Tweaks host bridge
  useEffect(() => {
    const h = e => {
      if (e.data?.type === '__activate_edit_mode')  setTweaksVisible(true);
      if (e.data?.type === '__deactivate_edit_mode') setTweaksVisible(false);
    };
    window.addEventListener('message', h);
    window.parent.postMessage({ type: '__edit_mode_available' }, '*');
    return () => window.removeEventListener('message', h);
  }, []);

  // Probe server + load live digest on mount
  useEffect(() => {
    (async () => {
      const online = await api.probe();
      setServerOnline(online);
      if (online) {
        const data = await api.get('/api/digest');
        if (data?.items?.length) setDigestItems(data.items);
      }
    })();
  }, []);

  // Scroll chat
  useEffect(() => {
    if (chatEndRef.current) {
      const el = chatEndRef.current.parentElement;
      el.scrollTop = el.scrollHeight;
    }
  }, [chatMessages, chatBusy]);

  const handleRefresh = async () => {
    setRefreshing(true);
    const online = await api.probe();
    setServerOnline(online);
    if (online) {
      const data = await api.get('/api/digest');
      if (data?.items?.length) setDigestItems(data.items);
    }
    await new Promise(r => setTimeout(r, 600));
    setRefreshing(false);
  };

  const handleArchive = useCallback(item => {
    setArchivedIds(prev => new Set([...prev, item.message_id]));
  }, []);

  const handleAddToCalendar = useCallback(item => {
    setPendingCalIds(prev => new Set([...prev, item.message_id]));
  }, []);

  const sendToChat = useCallback(async (text) => {
    const content = (text || chatInput).trim();
    if (!content || chatBusy) return;
    setChatInput('');
    const userMsg = { role: 'user', content };
    const history = [...chatMessages, userMsg];
    setChatMessages(history);
    setChatBusy(true);
    try {
      const reply = await pixChat(history.slice(-8));
      setChatMessages(prev => { setLastAnimIdx(prev.length); return [...prev, { role: 'assistant', content: reply }]; });
    } catch(e) {
      setChatMessages(prev => { setLastAnimIdx(prev.length); return [...prev, { role: 'assistant', content: `[error] ${e.message}` }]; });
    } finally { setChatBusy(false); }
  }, [chatInput, chatBusy, chatMessages]);

  const handleAskPix = useCallback(item => {
    sendToChat(`Summarize and suggest the best next action:\nSubject: ${item.subject}\nFrom: ${item.sender}\nContext: ${item.summary}\nAction items: ${(item.action_items||[]).join(', ')}`);
  }, [sendToChat]);

  // Classify + filter
  const items    = useMemo(() => digestItems.filter(i => !archivedIds.has(i.message_id)), [digestItems, archivedIds]);
  const respond  = useMemo(() => items.filter(i => classifyEmail(i) === 'respond'),  [items]);
  const decide   = useMemo(() => items.filter(i => classifyEmail(i) === 'decide'),   [items]);
  const schedule = useMemo(() => items.filter(i => classifyEmail(i) === 'schedule'), [items]);
  const inbox    = useMemo(() => items.filter(i => classifyEmail(i) === 'inbox'),    [items]);

  return (
    <div style={{ minHeight: '100vh', background: 'var(--bg)', color: 'var(--fg)', display: 'flex', alignItems: 'flex-start', justifyContent: 'center', padding: '24px 20px' }}>
      <div style={{ width: '100%', maxWidth: 1200, border: '1px solid var(--border-bright)', background: 'var(--bg)' }}>

        {/* Top bar */}
        <div style={{ padding: '9px 16px', borderBottom: '1px solid var(--border)', background: 'var(--bg2)', display: 'flex', justifyContent: 'space-between', alignItems: 'center' }}>
          <div style={{ display: 'flex', gap: 10, alignItems: 'baseline' }}>
            <span style={{ color: 'var(--accent)', fontWeight: 700, fontSize: 15 }}>▌</span>
            <span style={{ fontWeight: 600, letterSpacing: '0.02em' }}>email_agent</span>
            <span style={{ color: 'var(--fg-muted)' }}>~/desk</span>
            <span style={{ color: 'var(--fg-muted)', fontSize: 11 }}>// action triage</span>
            <span style={{ animation: 'blink 1.1s steps(2,end) infinite' }}>█</span>
          </div>
          <div style={{ display: 'flex', gap: 12, alignItems: 'center', fontSize: 11 }}>
            <span style={{ color: 'var(--fg-muted)' }}>{new Date().toLocaleDateString('en-US', { month: 'short', day: 'numeric', year: 'numeric' }).toUpperCase()}</span>
            <AsciiBtn onClick={handleRefresh} accent>
              {refreshing ? `${spinner} refreshing` : '▶ refresh digest'}
            </AsciiBtn>
          </div>
        </div>

        {/* Main body: zones + calendar */}
        <div style={{ display: 'grid', gridTemplateColumns: '1fr 300px', borderBottom: '1px solid var(--border)' }}>

          {/* Left: action zones */}
          <div style={{ borderRight: '1px solid var(--border)' }}>

            {/* RESPOND */}
            <div style={{ borderBottom: '1px solid var(--border)' }}>
              <ZoneHeader title="RESPOND" count={respond.length} accent />
              <div style={{ padding: '4px 0' }}>
                {respond.length === 0
                  ? <EmptyRow label="no replies needed" />
                  : respond.map(item => (
                      <ActionEmailRow key={item.message_id} item={item} zone="respond"
                        onOpen={setSelectedItem} onDone={handleArchive}
                        onAskPix={handleAskPix} onCompose={setComposeItem} />
                    ))
                }
              </div>
            </div>

            {/* DECIDE */}
            <div style={{ borderBottom: '1px solid var(--border)' }}>
              <ZoneHeader title="DECIDE" count={decide.length}
                right={<span style={{ fontSize: 9, color: 'var(--fg-muted)', letterSpacing: '0.08em' }}>tasks · technical</span>}
              />
              <div style={{ padding: '4px 0' }}>
                {decide.length === 0
                  ? <EmptyRow label="no decisions pending" />
                  : decide.map(item => (
                      <ActionEmailRow key={item.message_id} item={item} zone="decide"
                        onOpen={setSelectedItem} onDone={handleArchive}
                        onAskPix={handleAskPix} onCompose={setComposeItem} />
                    ))
                }
              </div>
            </div>

            {/* SCHEDULE */}
            <div style={{ borderBottom: inbox.length > 0 ? '1px solid var(--border)' : 'none' }}>
              <ZoneHeader title="SCHEDULE" count={schedule.length}
                right={<span style={{ fontSize: 9, color: 'var(--fg-muted)', letterSpacing: '0.08em' }}>events detected</span>}
              />
              <div style={{ padding: '4px 0' }}>
                {schedule.length === 0
                  ? <EmptyRow label="no events detected" />
                  : schedule.map(item => (
                      <ScheduleRow key={item.message_id} item={item}
                        onOpen={setSelectedItem} onAskPix={handleAskPix}
                        added={pendingCalIds.has(item.message_id)}
                        onAdd={handleAddToCalendar} />
                    ))
                }
              </div>
            </div>

            {/* INBOX */}
            {inbox.length > 0 && (
              <div>
                <ZoneHeader title="INBOX" count={inbox.length} muted
                  right={<span style={{ fontSize: 9, color: 'var(--fg-muted)', letterSpacing: '0.08em' }}>read-only · fyi</span>}
                />
                <div style={{ padding: '4px 0' }}>
                  {inbox.map(item => <InboxRow key={item.message_id} item={item} onOpen={setSelectedItem} />)}
                </div>
              </div>
            )}
          </div>

          {/* Right: calendar */}
          <CalendarPanel pendingIds={pendingCalIds} />
        </div>

        {/* Pix chat */}
        <div>
          <ZoneHeader title="PIX / LOCAL.LLM" accent />
          <div style={{ padding: '8px 14px 0' }}>
            <div style={{ maxHeight: 170, overflowY: 'auto', paddingBottom: 8 }}>
              {chatMessages.map((msg, i) => (
                <ChatMessage key={i} msg={msg} animate={i === lastAnimIdx && msg.role === 'assistant'} />
              ))}
              {chatBusy && <div style={{ color: 'var(--accent)', fontSize: 12, marginBottom: 8 }}>pix&gt; {spinner} thinking…</div>}
              <div ref={chatEndRef} />
            </div>
            <div style={{ borderTop: '1px dashed var(--border)', paddingTop: 8, paddingBottom: 10, display: 'flex', gap: 8, alignItems: 'center' }}>
              <span style={{ color: 'var(--accent)', fontWeight: 700, fontSize: 13 }}>›</span>
              <input value={chatInput} onChange={e => setChatInput(e.target.value)} onKeyDown={e => { if (e.key === 'Enter') sendToChat(); }}
                placeholder="ask pix to prioritize, summarize, or plan…"
                style={{ flex: 1, background: 'transparent', border: 'none', outline: 'none', color: 'var(--fg)', fontFamily: 'inherit', fontSize: 12, padding: '3px 0' }}
              />
              <AsciiBtn onClick={() => sendToChat()} disabled={!chatInput.trim() || chatBusy} accent={!!chatInput.trim() && !chatBusy}>send</AsciiBtn>
            </div>
          </div>
        </div>

        <StatusBar items={digestItems} refreshing={refreshing} spinner={spinner} serverOnline={serverOnline} />
      </div>

      {/* Modals */}
      <DetailModal item={selectedItem} onClose={() => setSelectedItem(null)}
        onAskPix={item => { handleAskPix(item); setSelectedItem(null); }}
        onCompose={item => { setComposeItem(item); setSelectedItem(null); }} />

      {composeItem && <ComposeModal item={composeItem} onClose={() => setComposeItem(null)} />}

      <TweaksPanel visible={tweaksVisible} theme={themeId} onTheme={setThemeId} serverOnline={serverOnline} />
    </div>
  );
}

ReactDOM.createRoot(document.getElementById('root')).render(<App />);
