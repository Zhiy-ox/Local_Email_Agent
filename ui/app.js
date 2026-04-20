const { useEffect, useMemo, useRef, useState } = React;

const MOCK_DIGEST = {
  items: [
    { idx: 1, message_id: "m1", date: "2026-04-18 09:14", sender: "Priya Shah <priya@acme.co>", subject: "Q2 roadmap sign-off needed by Friday", summary: "Priya needs your ack on the v2 roadmap before the exec review. Decision required on Track C scope.", importance: 3, action_items: ["Review Track C scope", "Reply with sign-off"], event: null },
    { idx: 2, message_id: "m2", date: "2026-04-18 08:02", sender: "GitHub <noreply@github.com>", subject: "3 failing checks on PR #482", summary: "CI lint + typecheck failing on the latest push to the ascii-glass branch.", importance: 2, action_items: ["Inspect CI logs"], event: null },
    { idx: 3, message_id: "m3", date: "2026-04-17 21:40", sender: "Linear <notifications@linear.app>", subject: "INGEST-214 moved to In Review", summary: "Merged by dmitri. Awaiting your review comment before release gate.", importance: 2, action_items: ["Leave review"], event: null },
    { idx: 4, message_id: "m4", date: "2026-04-17 17:22", sender: "Maya Chen <maya@studio.design>", subject: "Design sync — Thursday 2pm?", summary: "Want to walk through the liquid-glass tokens and confirm the typography ramp before handoff.", importance: 1, action_items: ["Confirm time"], event: { start_datetime: "2026-04-23T14:00:00", end_datetime: "2026-04-23T15:00:00", title: "Design sync with Maya" }, event_preview: "Thu 2pm – Design sync" },
    { idx: 5, message_id: "m5", date: "2026-04-17 12:10", sender: "HR <people@acme.co>", subject: "Benefits enrollment window closes 04-30", summary: "Annual enrollment is open. Current elections will auto-renew if no action taken.", importance: 1, action_items: [], event: null },
    { idx: 6, message_id: "m6", date: "2026-04-16 19:55", sender: "Stripe <receipts@stripe.com>", subject: "Receipt for your subscription renewal", summary: "Pro plan renewed for $20.00. Next billing cycle 2026-05-16.", importance: 0, action_items: [], event: null },
    { idx: 7, message_id: "m7", date: "2026-04-16 15:30", sender: "Sam Ortiz <sam@vendor.io>", subject: "Coffee next week?", summary: "Sam is in town 04-22 through 04-24 and wants to grab coffee.", importance: 0, action_items: ["Propose time"], event: null, event_preview: "Coffee 04-22 to 04-24" },
    { idx: 8, message_id: "m8", date: "2026-04-16 11:08", sender: "Security <security@acme.co>", subject: "Rotate API keys — deadline 04-25", summary: "Quarterly rotation. Old keys are revoked automatically after the deadline.", importance: 3, action_items: ["Rotate prod key", "Rotate staging key"], event: null },
  ],
};

const FORCE_MOCK = new URLSearchParams(location.search).has("mock");

function mockFor(path, payload) {
  if (path === "/api/digest") return MOCK_DIGEST;
  if (path === "/api/chat") {
    const last = (payload?.messages || []).slice(-1)[0]?.content || "";
    return { reply: `[mock] Pix heard: "${last.slice(0, 80)}${last.length > 80 ? "…" : ""}"` };
  }
  return { ok: true };
}

const api = {
  async get(path) {
    if (FORCE_MOCK) return mockFor(path);
    try {
      const res = await fetch(path, { cache: "no-store" });
      if (!res.ok) throw new Error(`${path} -> HTTP ${res.status}`);
      return await res.json();
    } catch (_e) {
      return mockFor(path);
    }
  },
  async post(path, payload) {
    if (FORCE_MOCK) return mockFor(path, payload);
    try {
      const res = await fetch(path, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify(payload || {}),
      });
      const data = await res.json().catch(() => ({}));
      if (!res.ok) throw new Error(data.reason || data.error || `${path} -> HTTP ${res.status}`);
      return data;
    } catch (_e) {
      return mockFor(path, payload);
    }
  },
};

function hashString(input) {
  let h = 2166136261;
  const s = String(input || "");
  for (let i = 0; i < s.length; i += 1) {
    h ^= s.charCodeAt(i);
    h += (h << 1) + (h << 4) + (h << 7) + (h << 8) + (h << 24);
  }
  return Math.abs(h >>> 0);
}

function seeded(min, max, seed) {
  const x = Math.sin(seed) * 10000;
  const n = x - Math.floor(x);
  return min + n * (max - min);
}

function itemKey(item, idx) {
  return String(item.message_id || item.idx || `${item.subject || "s"}-${item.sender || "n"}-${idx}`);
}

function cardPose(seedBase, index, total) {
  const seed = seedBase + index * 17.17;
  const center = (total - 1) / 2;
  const spreadIndex = index - center;
  return {
    collapsedX: spreadIndex * -10 + seeded(-4, 4, seed * 0.71),
    collapsedY: spreadIndex * 1.5 + seeded(-3, 3, seed * 1.09),
    collapsedRot: spreadIndex * 2.2 + seeded(-5, 5, seed * 1.57),
    expandedX: spreadIndex * 58 + seeded(-10, 10, seed * 2.21),
    expandedY: Math.abs(spreadIndex) * 5 + seeded(-6, 6, seed * 2.53),
    expandedRot: spreadIndex * 7 + seeded(-3.5, 3.5, seed * 2.99),
    drift: seeded(4, 11, seed * 3.37),
    delay: seeded(0, 2.2, seed * 3.89),
  };
}

function importanceTone(level) {
  if (level >= 3) return "CRIT";
  if (level === 2) return "HIGH";
  if (level === 1) return "MED";
  return "LOW";
}

function importanceLabel(level) {
  if (level >= 3) return "imp::3 critical";
  if (level === 2) return "imp::2 high";
  if (level === 1) return "imp::1 medium";
  return "imp::0 low";
}

function App() {
  const [digest, setDigest] = useState({ items: [] });
  const [error, setError] = useState("");
  const [seenMap, setSeenMap] = useState({});
  const [dragMap, setDragMap] = useState({});
  const [activeDrag, setActiveDrag] = useState(null);
  const [eventOverrides, setEventOverrides] = useState({});
  const [eventStatus, setEventStatus] = useState({});
  const [chatMessages, setChatMessages] = useState([
    { role: "assistant", content: "I am Pix running on your local model. Ask me about any card." },
  ]);
  const [chatInput, setChatInput] = useState("");
  const [chatBusy, setChatBusy] = useState(false);
  const chatEndRef = useRef(null);

  const loadSeen = () => {
    try {
      const s = localStorage.getItem("email-seen-map-v2");
      return s ? JSON.parse(s) : {};
    } catch (_e) {
      return {};
    }
  };

  const saveSeen = (next) => {
    localStorage.setItem("email-seen-map-v2", JSON.stringify(next));
  };

  const load = async () => {
    setError("");
    try {
      const data = await api.get("/api/digest");
      setDigest(data || { items: [] });
    } catch (e) {
      setError(String(e.message || e));
    }
  };

  useEffect(() => {
    setSeenMap(loadSeen());
    load();
  }, []);

  useEffect(() => {
    chatEndRef.current?.scrollIntoView({ behavior: "smooth", block: "end" });
  }, [chatMessages, chatBusy]);

  const markSeen = (key, seen) => {
    setSeenMap((prev) => {
      const next = { ...prev, [key]: !!seen };
      saveSeen(next);
      return next;
    });
  };

  const sendToPix = async (text) => {
    const content = String(text || "").trim();
    if (!content || chatBusy) return;
    const userMessage = { role: "user", content };
    const nextForRequest = [...chatMessages, userMessage].slice(-12);
    setChatMessages((prev) => [...prev, userMessage]);
    setChatInput("");
    setChatBusy(true);
    try {
      const data = await api.post("/api/chat", { messages: nextForRequest });
      setChatMessages((prev) => [...prev, { role: "assistant", content: data.reply || "No reply." }]);
    } catch (e) {
      setChatMessages((prev) => [...prev, { role: "assistant", content: `Model error: ${String(e.message || e)}` }]);
    } finally {
      setChatBusy(false);
    }
  };

  const items = useMemo(() => digest.items || [], [digest.items]);

  const zones = useMemo(() => {
    const unseen = [];
    const seen = [];
    const needsAction = [];
    const eventCandidates = [];
    items.forEach((item, idx) => {
      const k = itemKey(item, idx);
      const isSeen = !!seenMap[k];
      if (isSeen) seen.push({ item, idx, key: k });
      else unseen.push({ item, idx, key: k });
      if (Array.isArray(item.action_items) && item.action_items.length > 0) needsAction.push({ item, idx, key: k });
      if (item.event || item.event_preview) eventCandidates.push({ item, idx, key: k });
    });
    return { unseen, seen, needsAction, eventCandidates };
  }, [items, seenMap]);

  const groupByImportance = (rows) => {
    const groups = { 3: [], 2: [], 1: [], 0: [] };
    rows.forEach((row) => {
      const level = Math.max(0, Math.min(3, Number(row.item.importance || 0)));
      groups[level].push(row);
    });
    return groups;
  };

  const resolveEvent = (row) => eventOverrides[row.key] || row.item.event || null;

  const onCreateEvent = async (row) => {
    const event = resolveEvent(row);
    if (!event) {
      setEventStatus((prev) => ({ ...prev, [row.key]: "No structured event detected." }));
      return;
    }
    setEventStatus((prev) => ({ ...prev, [row.key]: "Creating calendar event..." }));
    try {
      await api.post("/api/calendar-events", { idx: row.item.idx, subject: row.item.subject || "", event });
      setEventStatus((prev) => ({ ...prev, [row.key]: "Event created." }));
    } catch (e) {
      setEventStatus((prev) => ({ ...prev, [row.key]: `Create failed: ${String(e.message || e)}` }));
    }
  };

  const onRefineEvent = async (row) => {
    setEventStatus((prev) => ({ ...prev, [row.key]: "Asking Pix to refine time..." }));
    try {
      const data = await api.post("/api/refine-event-time", {
        subject: row.item.subject || "",
        summary: row.item.summary || "",
        sender: row.item.sender || "",
        event_preview: row.item.event_preview || "",
        event: resolveEvent(row) || {},
      });
      if (data && data.start_datetime && data.end_datetime) {
        setEventOverrides((prev) => ({ ...prev, [row.key]: data }));
        setEventStatus((prev) => ({ ...prev, [row.key]: "Refined. Review then create." }));
      } else {
        setEventStatus((prev) => ({ ...prev, [row.key]: "Refine returned incomplete time." }));
      }
    } catch (e) {
      setEventStatus((prev) => ({ ...prev, [row.key]: `Refine failed: ${String(e.message || e)}` }));
    }
  };

  const onCardPointerDown = (dragId, stackId, e) => {
    if (e.button !== 0 && e.pointerType !== "touch") return;
    const base = dragMap[dragId] || { x: 0, y: 0 };
    setActiveDrag({
      id: dragId,
      stackId,
      pointerId: e.pointerId,
      startX: e.clientX,
      startY: e.clientY,
      baseX: base.x,
      baseY: base.y,
    });
    e.currentTarget.setPointerCapture?.(e.pointerId);
  };

  const onCardPointerMove = (dragId, e) => {
    if (!activeDrag || activeDrag.id !== dragId || activeDrag.pointerId !== e.pointerId) return;
    const dx = e.clientX - activeDrag.startX;
    const dy = e.clientY - activeDrag.startY;
    setDragMap((prev) => ({ ...prev, [dragId]: { x: activeDrag.baseX + dx, y: activeDrag.baseY + dy } }));
  };

  const onCardPointerUp = (dragId, e) => {
    if (!activeDrag || activeDrag.id !== dragId) return;
    e.currentTarget.releasePointerCapture?.(e.pointerId);
    setActiveDrag(null);
  };

  const renderCard = (row, stackId, stackIndex, stackCount) => {
    const seedBase = hashString(`${stackId}-${row.key}`);
    const pose = cardPose(seedBase, stackIndex, stackCount);
    const level = Math.max(0, Math.min(3, Number(row.item.importance || 0)));
    const isSeen = !!seenMap[row.key];
    const dragId = `${stackId}-${row.key}`;
    const drag = dragMap[dragId] || { x: 0, y: 0 };
    const isDragging = !!activeDrag && activeDrag.id === dragId;
    const hasEvent = !!resolveEvent(row);
    const status = eventStatus[row.key] || "";
    return (
      <article
        key={dragId}
        className={`mail-card imp-${level} ${isSeen ? "is-seen" : "is-unseen"} ${isDragging ? "dragging" : ""}`}
        style={{
          "--cx": `${pose.collapsedX}px`,
          "--cy": `${pose.collapsedY}px`,
          "--cr": `${pose.collapsedRot}deg`,
          "--ex": `${pose.expandedX}px`,
          "--ey": `${pose.expandedY}px`,
          "--er": `${pose.expandedRot}deg`,
          "--drift": `${pose.drift}px`,
          "--delay": `${pose.delay}s`,
          "--drag-x": `${drag.x}px`,
          "--drag-y": `${drag.y}px`,
          "--z": 20 + stackIndex,
        }}
        onPointerDown={(e) => onCardPointerDown(dragId, stackId, e)}
        onPointerMove={(e) => onCardPointerMove(dragId, e)}
        onPointerUp={(e) => onCardPointerUp(dragId, e)}
        onPointerCancel={(e) => onCardPointerUp(dragId, e)}
      >
        <div className="card-edge" />
        <div className="card-grain" />
        <div className="card-head">
          <span className="stamp">{row.item.date || "No date"}</span>
          <span className="pin">
            <span className="pin-dot" />
            {importanceTone(level)}
          </span>
        </div>
        <h3>{row.item.subject || "Untitled email"}</h3>
        <p className="sender">{row.item.sender || "Unknown sender"}</p>
        <p className="summary">{row.item.summary || "No summary available."}</p>
        <div className="card-actions">
          <button onPointerDown={(e) => e.stopPropagation()} onClick={() => markSeen(row.key, !isSeen)}>
            {isSeen ? "Mark Unseen" : "Mark Seen"}
          </button>
          <button
            onPointerDown={(e) => e.stopPropagation()}
            onClick={() => sendToPix(`Summarize and suggest next action:\nSubject: ${row.item.subject || ""}\nSummary: ${row.item.summary || ""}`)}
          >
            Ask Pix
          </button>
          {hasEvent ? (
            <button onPointerDown={(e) => e.stopPropagation()} onClick={() => onCreateEvent(row)}>
              Add Event
            </button>
          ) : null}
          {row.item.event_preview ? (
            <button onPointerDown={(e) => e.stopPropagation()} onClick={() => onRefineEvent(row)}>
              Refine Time
            </button>
          ) : null}
        </div>
        {status ? <p className="card-status">{status}</p> : null}
      </article>
    );
  };

  const renderZone = (id, title, rows) => {
    const groups = groupByImportance(rows);
    const order = [3, 2, 1, 0];
    return (
      <section className="zone glass" key={id}>
        <header className="zone-head">
          <h2>{title}</h2>
          <span className="count">{String(rows.length).padStart(2, "0")}</span>
        </header>
        <div className="zone-body">
          {order.map((level) => {
            const list = groups[level];
            if (!list.length) return null;
            const stackId = `${id}-${level}`;
            const forceOpen = !!activeDrag && activeDrag.stackId === stackId;
            return (
              <div className={`importance-stack lvl-${level}`} key={stackId}>
                <div className="stack-head">
                  <strong>{importanceLabel(level)}</strong>
                  <small>{String(list.length).padStart(2, "0")} cards</small>
                </div>
                <div className={`stack-area ${forceOpen ? "force-open" : ""}`}>
                  {list.map((row, i) => renderCard(row, stackId, i, list.length))}
                </div>
              </div>
            );
          })}
          {!rows.length ? <p className="zone-empty">No emails here yet.</p> : null}
        </div>
      </section>
    );
  };

  const onChatSubmit = async (e) => {
    e.preventDefault();
    await sendToPix(chatInput);
  };

  return (
    <main className="page">
      <div className="bg-float bg-a" />
      <div className="bg-float bg-b" />
      <div className="bg-float bg-c" />
      <header className="topbar glass">
        <div className="brand">
          <span className="prompt">~/</span>
          <h1>email_agent.desk</h1>
          <span className="tilde">// inbox triage</span>
          <span className="cursor" aria-hidden="true" />
        </div>
        <div className="meta">
          <span className="msg-count">msgs::{String((digest.items || []).length).padStart(3, "0")}</span>
          <button onClick={load}>refresh digest</button>
        </div>
      </header>
      {error ? <p className="error">{error}</p> : null}
      <div className="workspace">
        <section className="zones-grid">
          {renderZone("unseen", "Unseen", zones.unseen)}
          {renderZone("seen", "Seen", zones.seen)}
          {renderZone("action", "Needs Action", zones.needsAction)}
          {renderZone("events", "Event Candidates", zones.eventCandidates)}
        </section>
        <aside className="assistant-panel glass">
          <header className="assistant-head">
            <div className="robot-shell">
              <img src="./pixel-robot.svg" alt="Pixel robot assistant" />
              <span className="robot-shadow" />
            </div>
            <div>
              <h2>pix / local.llm</h2>
              <p>talk to your local model</p>
            </div>
          </header>
          <div className="chat-log">
            {chatMessages.map((m, i) => (
              <div className={`chat-msg ${m.role}`} key={`${m.role}-${i}`}>
                {m.content}
              </div>
            ))}
            {chatBusy ? <div className="chat-msg assistant">Thinking...</div> : null}
            <div ref={chatEndRef} />
          </div>
          <form className="chat-form" onSubmit={onChatSubmit}>
            <input
              value={chatInput}
              onChange={(e) => setChatInput(e.target.value)}
              placeholder="ask pix to summarize, plan, or refine…"
            />
            <button type="submit" disabled={!chatInput.trim() || chatBusy}>
              send
            </button>
          </form>
        </aside>
      </div>
    </main>
  );
}

ReactDOM.createRoot(document.getElementById("root")).render(<App />);
