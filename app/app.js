/* UNIQ Inbox dashboard: a review UI for the output of the /uniq-inbox Claude Code skill.
   Data comes from results/results.js (window.UNIQ_RESULTS), or from a results.csv the user loads.
   Plain JavaScript, no build step, works from file://. */
(function () {
  "use strict";

  const PRIORITIES = ["P1", "P2", "P3", "P4"];
  const PRIORITY_LABEL = { P1: "Owner today", P2: "Reply today", P3: "Within 1 day", P4: "No reply" };
  const STORE_PREFIX = "uniq-inbox:";

  const state = {
    data: { emails: [], orders: [], today: "", generated_at: "" },
    selectedKey: null,
    filters: { q: "", prio: new Set(), cat: "", humanOnly: false, hideSent: false, sort: "priority" },
  };

  // ---------- storage (per-viewer conveniences only; safe if blocked) ----------
  function load(key, fallback) {
    try { const v = localStorage.getItem(STORE_PREFIX + key); return v === null ? fallback : JSON.parse(v); } catch (e) { return fallback; }
  }
  function save(key, value) {
    try { localStorage.setItem(STORE_PREFIX + key, JSON.stringify(value)); } catch (e) { /* ignore */ }
  }
  function remove(key) { try { localStorage.removeItem(STORE_PREFIX + key); } catch (e) { /* ignore */ } }

  // ---------- helpers ----------
  const $ = (sel) => document.querySelector(sel);
  function el(tag, attrs, children) {
    const node = document.createElement(tag);
    if (attrs) for (const [k, v] of Object.entries(attrs)) {
      if (v === null || v === undefined || v === false) continue;
      if (k === "class") node.className = v;
      else if (k === "text") node.textContent = v;
      else if (k.startsWith("on")) node.addEventListener(k.slice(2), v);
      else node.setAttribute(k, v === true ? "" : v);
    }
    (children || []).forEach((c) => { if (c !== null && c !== undefined && c !== false) node.append(c.nodeType ? c : document.createTextNode(String(c))); });
    return node;
  }
  function keyOf(e) { return e.email_id + "|" + (e.from_email || ""); }
  function isYes(e) { return /^yes/i.test(e.needs_human || ""); }
  function firstName(e) { return (e.from_name || e.from_email || "").split(/\s+/)[0]; }
  function quoteTotal(e) {
    const m = /TOTAL:\s*\$([\d,]+\.\d{2})/.exec(e.quote || "");
    return m ? parseFloat(m[1].replace(/,/g, "")) : 0;
  }
  function money(n) { return "$" + n.toLocaleString("en-US", { maximumFractionDigits: 0 }); }
  function toast(msg) {
    const t = $("#toast"); t.textContent = msg; t.classList.add("show");
    clearTimeout(toast._t); toast._t = setTimeout(() => t.classList.remove("show"), 1800);
  }
  async function copyText(text) {
    try { await navigator.clipboard.writeText(text); toast("Copied to clipboard"); }
    catch (e) {
      const ta = el("textarea", { style: "position:fixed;left:-9999px" }); ta.value = text; document.body.append(ta); ta.select();
      try { document.execCommand("copy"); toast("Copied to clipboard"); } catch (e2) { toast("Copy failed - select and copy manually"); }
      ta.remove();
    }
  }
  function draftOf(e) { const d = load("draft:" + keyOf(e), null); return d === null ? (e.draft_reply || "") : d; }
  function statusOf(e) { return load("status:" + keyOf(e), { reviewed: false, sent: false }); }
  function isNoReply(e) { return /^no reply/i.test((e.draft_reply || "").trim()); }

  // ---------- CSV parsing (RFC 4180, multiline quoted fields) ----------
  function parseCSV(text) {
    text = text.replace(/^﻿/, "");
    const rows = []; let row = []; let field = ""; let inQ = false;
    for (let i = 0; i < text.length; i++) {
      const c = text[i];
      if (inQ) {
        if (c === '"') { if (text[i + 1] === '"') { field += '"'; i++; } else inQ = false; }
        else field += c;
      } else if (c === '"') inQ = true;
      else if (c === ",") { row.push(field); field = ""; }
      else if (c === "\n" || c === "\r") {
        if (c === "\r" && text[i + 1] === "\n") i++;
        row.push(field); rows.push(row); row = []; field = "";
      } else field += c;
    }
    if (field !== "" || row.length) { row.push(field); rows.push(row); }
    const header = rows.shift().map((h) => h.trim());
    return rows.filter((r) => r.length > 1).map((r) => Object.fromEntries(header.map((h, i) => [h, r[i] || ""])));
  }
  function csvEscape(v) { v = String(v === undefined || v === null ? "" : v); return /[",\n\r]/.test(v) ? '"' + v.replace(/"/g, '""') + '"' : v; }

  function fromCsvRow(r) {
    const nh = r.needs_human || "";
    const m = /^(Yes|No)\s*[-:]\s*(.*)$/is.exec(nh);
    return {
      email_id: r.email_id, category: r.category, priority: r.priority,
      needs_human: m ? m[1] : nh, needs_human_reason: m ? m[2] : "",
      quote: r.quote, draft_reply: r.draft_reply,
      from_name: r.from_name || "", from_email: r.from_email || "", subject: r.subject || "", body: r.body || "",
      summary: "", order_refs: [], flags: [], assumptions: [], owner_note: "",
    };
  }

  // ---------- rendering ----------
  function render() { renderMeta(); renderTiles(); renderOwner(); renderList(); renderDetail(); }

  function renderMeta() {
    const d = state.data;
    $("#meta").textContent = d.emails.length
      ? `${d.emails.length} emails · scenario date ${d.today || "n/a"} · results built ${d.generated_at || "n/a"}`
      : "No results loaded. Run /uniq-inbox in Claude Code, or load a results.csv.";
  }

  function renderTiles() {
    const E = state.data.emails;
    const tiles = $("#tiles"); tiles.replaceChildren();
    PRIORITIES.forEach((p) => {
      const n = E.filter((e) => e.priority === p).length;
      tiles.append(el("button", { class: "tile " + p.toLowerCase(), type: "button", onclick: () => togglePrio(p, true) }, [
        el("div", { class: "label", text: p }), el("div", { class: "value", text: n }), el("div", { class: "hint", text: PRIORITY_LABEL[p] }),
      ]));
    });
    const human = E.filter(isYes).length;
    tiles.append(el("button", { class: "tile human", type: "button", onclick: () => { $("#humanOnly").checked = true; state.filters.humanOnly = true; renderList(); } }, [
      el("div", { class: "label", text: "Needs human" }), el("div", { class: "value", text: human }), el("div", { class: "hint", text: "Owner reviews first" }),
    ]));
    const quoted = E.reduce((s, e) => s + quoteTotal(e), 0);
    const nQuotes = E.filter((e) => quoteTotal(e) > 0).length;
    tiles.append(el("div", { class: "tile" }, [
      el("div", { class: "label", text: "Quoted" }), el("div", { class: "value", text: money(quoted) }), el("div", { class: "hint", text: `${nQuotes} quotes (recommended option)` }),
    ]));
    const sent = E.filter((e) => statusOf(e).sent).length;
    tiles.append(el("div", { class: "tile" }, [
      el("div", { class: "label", text: "Sent" }), el("div", { class: "value", text: `${sent}/${E.filter((e) => !isNoReply(e)).length}` }), el("div", { class: "hint", text: "replies marked sent" }),
    ]));
  }

  function prioRank(e) { const i = PRIORITIES.indexOf(e.priority); return i < 0 ? 9 : i; }

  function renderOwner() {
    const list = $("#ownerList"); list.replaceChildren();
    const items = state.data.emails.filter(isYes).sort((a, b) => prioRank(a) - prioRank(b) || quoteTotal(b) - quoteTotal(a));
    $("#ownerCount").textContent = items.length ? `${items.length} flagged for the owner, most urgent first` : "Nothing flagged";
    items.forEach((e) => {
      list.append(el("li", { class: "owner-item", tabindex: "0", onclick: () => select(e), onkeydown: (ev) => { if (ev.key === "Enter") select(e); } }, [
        el("div", { class: "top" }, [
          el("span", { class: "badge " + e.priority, text: e.priority }),
          el("span", { class: "who", text: `${e.email_id} · ${e.from_name || e.from_email}` }),
          el("span", { class: "badge cat", text: e.category }),
        ]),
        el("div", { class: "note", text: e.owner_note || e.needs_human_reason }),
      ]));
    });
    $("#ownerPanel").hidden = items.length === 0;
  }

  function filtered() {
    const f = state.filters; const q = f.q.trim().toLowerCase();
    let E = state.data.emails.filter((e) => {
      if (f.prio.size && !f.prio.has(e.priority)) return false;
      if (f.cat && e.category !== f.cat) return false;
      if (f.humanOnly && !isYes(e)) return false;
      if (f.hideSent && statusOf(e).sent) return false;
      if (q) {
        const hay = [e.email_id, e.from_name, e.from_email, e.subject, e.body, e.category, e.summary].join(" ").toLowerCase();
        if (!hay.includes(q)) return false;
      }
      return true;
    });
    const byId = (a, b) => a.email_id.localeCompare(b.email_id, undefined, { numeric: true });
    if (f.sort === "priority") E.sort((a, b) => prioRank(a) - prioRank(b) || (isYes(b) - isYes(a)) || byId(a, b));
    else if (f.sort === "received") E.sort((a, b) => (a.received_at || "").localeCompare(b.received_at || "") || byId(a, b));
    else E.sort(byId);
    return E;
  }

  function renderList() {
    const ul = $("#emailList"); ul.replaceChildren();
    const E = filtered();
    if (!E.length) { ul.append(el("li", { class: "none", text: "No emails match these filters." })); return; }
    E.forEach((e) => {
      const st = statusOf(e);
      ul.append(el("li", {
        class: "email-item" + (keyOf(e) === state.selectedKey ? " active" : "") + (st.sent ? " sent" : ""),
        tabindex: "0", onclick: () => select(e), onkeydown: (ev) => { if (ev.key === "Enter") select(e); },
      }, [
        el("div", { class: "row1" }, [
          el("span", { class: "badge " + e.priority, text: e.priority }),
          el("span", { class: "from", text: e.from_name || e.from_email || "(unknown sender)" }),
          el("span", { class: "id", text: e.email_id }),
        ]),
        el("div", { class: "subj", text: e.subject || e.summary || "" }),
        el("div", { class: "row3" }, [
          el("span", { class: "badge cat", text: e.category }),
          el("span", { class: "badge " + (isYes(e) ? "yes" : "no"), text: isYes(e) ? "Needs human" : "OK to send" }),
          st.sent ? el("span", { class: "badge status", text: "Sent" }) : st.reviewed ? el("span", { class: "badge status", text: "Reviewed" }) : null,
        ]),
      ]));
    });
  }

  function matchingOrders(e) {
    const refs = new Set(e.order_refs || []);
    const email = (e.from_email || "").toLowerCase();
    return (state.data.orders || []).filter((o) => refs.has(o.order_id) || (email && (o.customer_email || "").toLowerCase() === email));
  }

  function renderDetail() {
    const box = $("#detail");
    const e = state.data.emails.find((x) => keyOf(x) === state.selectedKey);
    if (!e) { box.replaceChildren(el("div", { class: "empty", text: "Select an email to review its triage, quote, and draft reply." })); return; }
    const yes = isYes(e);
    const nodes = [];

    nodes.push(el("div", { class: "detail-head" }, [
      el("div", { class: "badges" }, [
        el("span", { class: "badge " + e.priority, text: `${e.priority} · ${PRIORITY_LABEL[e.priority] || ""}` }),
        el("span", { class: "badge cat", text: e.category }),
        el("span", { class: "badge " + (yes ? "yes" : "no"), text: yes ? "Needs human" : "OK to send after review" }),
        e.language && e.language !== "English" ? el("span", { class: "badge cat", text: e.language }) : null,
      ]),
      el("h2", { text: e.subject || "(no subject)" }),
      el("div", { class: "meta", text: `${e.email_id} · ${e.from_name || ""} <${e.from_email || "?"}>${e.received_at ? " · " + e.received_at : ""}` }),
    ]));

    if (e.summary) nodes.push(el("p", { class: "summary", text: e.summary }));
    nodes.push(el("div", { class: "callout " + (yes ? "yes" : "no") }, [
      el("strong", { text: yes ? "Needs human: Yes" : "Needs human: No" }), e.needs_human_reason || "",
    ]));
    if (e.owner_note) nodes.push(el("div", { class: "callout note" }, [el("strong", { text: "Note for the owner" }), e.owner_note]));

    // Draft reply
    const draft = draftOf(e);
    const edited = draft !== (e.draft_reply || "");
    const ta = el("textarea", { id: "draft", "aria-label": "Draft reply" }); ta.value = draft;
    const editedTag = el("span", { class: "edited", text: edited ? "Edited (saved in this browser)" : "" });
    ta.addEventListener("input", () => { save("draft:" + keyOf(e), ta.value); editedTag.textContent = "Edited (saved in this browser)"; });
    const st = statusOf(e);
    const reviewed = el("input", { type: "checkbox" }); reviewed.checked = st.reviewed;
    const sent = el("input", { type: "checkbox" }); sent.checked = st.sent;
    const saveStatus = () => { save("status:" + keyOf(e), { reviewed: reviewed.checked, sent: sent.checked }); renderList(); renderTiles(); };
    reviewed.addEventListener("change", saveStatus); sent.addEventListener("change", saveStatus);
    const noReply = isNoReply(e);
    const subjectRe = /^re:/i.test(e.subject || "") ? e.subject : "Re: " + (e.subject || "");
    nodes.push(el("div", { class: "block" }, [
      el("h3", {}, [noReply ? "Recommendation" : `Draft reply to ${firstName(e)}`, editedTag]),
      ta,
      el("div", { class: "reply-actions" }, [
        el("button", { class: "btn", type: "button", onclick: () => copyText(ta.value) }, ["Copy reply"]),
        noReply ? null : el("a", { class: "btn ghost", href: `mailto:${encodeURIComponent(e.from_email || "")}?subject=${encodeURIComponent(subjectRe)}&body=${encodeURIComponent(ta.value)}`, onclick: (ev) => { ev.currentTarget.href = `mailto:${encodeURIComponent(e.from_email || "")}?subject=${encodeURIComponent(subjectRe)}&body=${encodeURIComponent(ta.value)}`; } }, ["Open in email"]),
        el("button", { class: "btn ghost", type: "button", onclick: () => { remove("draft:" + keyOf(e)); renderDetail(); toast("Draft reset to AI version"); } }, ["Reset draft"]),
      ]),
      el("div", { class: "status-row" }, [
        el("label", { class: "check" }, [reviewed, " Reviewed"]),
        el("label", { class: "check" }, [sent, " Sent / handled"]),
      ]),
    ]));

    if (e.quote) {
      nodes.push(el("div", { class: "block" }, [
        el("h3", {}, ["Quote (from the pricing engine)", el("button", { class: "btn small ghost", type: "button", onclick: () => copyText(e.quote) }, ["Copy"])]),
        el("pre", { text: e.quote }),
      ]));
    }

    const orders = matchingOrders(e);
    const refs = new Set(e.order_refs || []);
    nodes.push(el("div", { class: "block" }, [
      el("h3", { text: `Order history (${orders.length})` }),
      orders.length ? el("div", { class: "table-wrap" }, [el("table", { class: "orders" }, [
        el("thead", {}, [el("tr", {}, ["Order", "Date", "Items", "Total", "Status", "Delivered", "Tracking / notes"].map((h) => el("th", { text: h })))]),
        el("tbody", {}, orders.map((o) => el("tr", { class: refs.has(o.order_id) ? "ref" : "" }, [
          o.order_id, o.order_date, o.items, o.order_total, o.status, o.delivered_date || "-", [o.carrier, o.tracking, o.notes].filter(Boolean).join(" · "),
        ].map((v) => el("td", { text: v || "" }))))),
      ])]) : el("p", { class: "muted small", text: "No orders on file for this sender (new customer or prospect)." }),
    ]));

    nodes.push(el("div", { class: "block" }, [
      el("details", { open: true }, [el("summary", { text: "Original email" }), el("pre", { class: "body-text", text: e.body || "(body not included - load results.js for full detail)" })]),
    ]));

    if ((e.assumptions || []).length) nodes.push(el("div", { class: "block" }, [el("h3", { text: "Assumptions" }), el("ul", { class: "plain" }, e.assumptions.map((a) => el("li", { text: a })))]));
    if ((e.flags || []).length) nodes.push(el("div", { class: "block" }, [el("h3", { text: "Flags" }), el("div", { class: "tags" }, e.flags.map((f) => el("span", { class: "tag", text: f })))]));

    box.replaceChildren(...nodes);
  }

  // ---------- actions ----------
  function select(e) {
    state.selectedKey = keyOf(e);
    renderList(); renderDetail();
    if (window.matchMedia("(max-width: 900px)").matches) $("#detail").scrollIntoView({ behavior: "smooth", block: "start" });
  }
  function togglePrio(p, only) {
    const s = state.filters.prio;
    if (only) { const wasOnly = s.size === 1 && s.has(p); s.clear(); if (!wasOnly) s.add(p); }
    else if (s.has(p)) s.delete(p); else s.add(p);
    renderChips(); renderList();
  }
  function renderChips() {
    const box = $("#prioChips"); box.replaceChildren();
    PRIORITIES.forEach((p) => box.append(el("button", { class: "chip", type: "button", "aria-pressed": String(state.filters.prio.has(p)), onclick: () => togglePrio(p, false), text: p })));
  }
  function renderCategories() {
    const sel = $("#catFilter"); const current = sel.value;
    const cats = [...new Set(state.data.emails.map((e) => e.category))].sort();
    sel.replaceChildren(el("option", { value: "", text: "All categories" }), ...cats.map((c) => el("option", { value: c, text: c })));
    sel.value = cats.includes(current) ? current : "";
  }

  function exportCsv() {
    const cols = ["email_id", "category", "priority", "needs_human", "quote", "draft_reply"];
    const lines = [cols.join(",")];
    [...state.data.emails].sort((a, b) => a.email_id.localeCompare(b.email_id, undefined, { numeric: true })).forEach((e) => {
      lines.push([e.email_id, e.category, e.priority, `${e.needs_human} - ${e.needs_human_reason || ""}`, e.quote || "", draftOf(e)].map(csvEscape).join(","));
    });
    const blob = new Blob(["﻿" + lines.join("\r\n")], { type: "text/csv;charset=utf-8" });
    const a = el("a", { href: URL.createObjectURL(blob), download: "uniq-results.csv" });
    document.body.append(a); a.click(); a.remove();
    toast("CSV downloaded (includes your edits)");
  }

  function setData(d) {
    state.data = { emails: d.emails || [], orders: d.orders || [], today: d.today || "", generated_at: d.generated_at || "" };
    renderCategories();
    const first = filtered()[0];
    state.selectedKey = first ? keyOf(first) : null;
    render();
  }

  function applyTheme(t) {
    if (t) document.documentElement.setAttribute("data-theme", t); else document.documentElement.removeAttribute("data-theme");
  }

  // ---------- wire up ----------
  function init() {
    applyTheme(load("theme", null));
    $("#themeBtn").addEventListener("click", () => {
      const cur = document.documentElement.getAttribute("data-theme") || (window.matchMedia("(prefers-color-scheme: dark)").matches ? "dark" : "light");
      const next = cur === "dark" ? "light" : "dark"; applyTheme(next); save("theme", next);
    });
    $("#search").addEventListener("input", (ev) => { state.filters.q = ev.target.value; renderList(); });
    $("#catFilter").addEventListener("change", (ev) => { state.filters.cat = ev.target.value; renderList(); });
    $("#humanOnly").addEventListener("change", (ev) => { state.filters.humanOnly = ev.target.checked; renderList(); });
    $("#hideSent").addEventListener("change", (ev) => { state.filters.hideSent = ev.target.checked; renderList(); });
    $("#sortBy").addEventListener("change", (ev) => { state.filters.sort = ev.target.value; renderList(); });
    $("#exportBtn").addEventListener("click", exportCsv);
    $("#helpBtn").addEventListener("click", () => $("#helpDialog").showModal());
    document.querySelectorAll("[data-copy]").forEach((b) => b.addEventListener("click", () => copyText(b.getAttribute("data-copy"))));
    $("#csvInput").addEventListener("change", async (ev) => {
      const file = ev.target.files[0]; if (!file) return;
      try {
        const rows = parseCSV(await file.text());
        if (!rows.length || !("email_id" in rows[0])) throw new Error("missing email_id column");
        setData({ emails: rows.map(fromCsvRow), orders: state.data.orders, today: state.data.today, generated_at: "from " + file.name });
        toast(`Loaded ${rows.length} emails from ${file.name}`);
      } catch (err) { toast("Couldn't read that CSV: " + err.message); }
      ev.target.value = "";
    });
    renderChips();
    setData(window.UNIQ_RESULTS || { emails: [] });
  }

  document.addEventListener("DOMContentLoaded", init);
})();
