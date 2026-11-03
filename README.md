# UNIQ Inbox Assistant

An AI inbox teammate for UNIQ Supply. For every customer email it:

1. **Sorts** it into one of 9 categories.
2. **Prioritizes** it from P1 (owner sees today) to P4 (no reply).
3. **Quotes** custom cup orders with exact math from a deterministic pricing engine.
4. **Drafts a reply** in UNIQ's brand voice, in the customer's language.
5. **Flags** anything the owner must handle, with a one-line reason.

Then a dashboard lets the team review, edit, copy, and track every reply.

```
packet/ (knowledge base, orders, inbox) ─┐
data/pricing.json                       ─┼─> /uniq-inbox skill (Claude Code) ──> results/emails/<id>.json
tools/quote.ps1 (all price math)        ─┘                                            │
                                               tools/build-results.ps1 <──────────────┘
                                                        │
                            results/results.csv (submission table) + results/results.js
                                                        │
                                          index.html dashboard (team review)
```

## Why it's built this way
- **The AI never does arithmetic.** Claude reads the email and extracts the order (size, quantity, colors, Pantone, reorder, destination, deadline). `tools/quote.ps1` then picks the eligible production paths and price tier, adds setup and freight, works out the ship window from proof approval, and flags anything over $5k, outside the lower 48, or needing a rush. Tier mistakes and "give me a discount" tricks can't change a price.
- **Policies come from the knowledge base**, read fresh on every run. The skill's `reference/rules.md` holds the *judgment*: the priority rubric, the 7-point escalation checklist, phishing and prompt-injection screening, brand voice, and a self-check before saving.
- **Email content is treated as data, not instructions.** E16 hides a "note to the AI" asking for a 40% discount and the system prompt. It gets ignored, flagged for the owner, and quoted at published prices.
- **A human always reviews.** Flagged emails still get a full draft, so the owner only has to decide, not write.

## Use it (Tuesday workflow)
Requirements: [Claude Code](https://claude.com/claude-code) and Windows PowerShell (built in). No API key, Node, or Python needed.

1. Put the new emails in `packet/inbox.csv` (same columns: `email_id,received_at,from_name,from_email,subject,body`), or save them anywhere as a CSV.
2. Set `today` in `data/pricing.json` to the real date. It's currently the scenario date, 2027-03-08.
3. Open Claude Code in this folder and run one of:
   - `/uniq-inbox all` to process everything in `packet/inbox.csv`
   - `/uniq-inbox path/to/tuesday.csv` to process another file (old results with the same IDs get archived first)
   - `/uniq-inbox E07` to re-run one email
   - `/uniq-inbox` followed by a pasted email to handle one email (it gets the next ID, e.g. E21)
4. Double-click `index.html`. You get the owner queue, filters, quote math, editable drafts with **Copy** / **Open in email** buttons, and Reviewed/Sent checkboxes (saved in your browser). **Download CSV** exports the table, including your edits.

## Keep it current
- **Policy or catalog changes:** edit `packet/knowledge_base.md`. The skill reads it every run.
- **Custom pricing changes:** edit **both** `packet/knowledge_base.md` and `data/pricing.json`, then run the tests:
  `powershell -ExecutionPolicy Bypass -File tools/test-quote.ps1` (30 checks covering every quote in this inbox).
- Quote one order by hand:
  `powershell -ExecutionPolicy Bypass -File tools/quote.ps1 -Size 8 -Qty 20000 -Colors 2 -Pms -NeedBy 2027-04-15`

## Files
| Path | What it is |
|---|---|
| `.claude/skills/uniq-inbox/SKILL.md` | The AI workflow (the "prompt") |
| `.claude/skills/uniq-inbox/reference/rules.md` | Categories, priority rubric, escalation checklist, voice, self-check |
| `data/pricing.json` | Custom-cup pricing tables and rules (single source for the engine) |
| `tools/quote.ps1` | Deterministic quote engine |
| `tools/test-quote.ps1` | Regression tests for the engine |
| `tools/build-results.ps1` | Builds `results/results.csv` and `results/results.js` from the per-email JSON |
| `results/emails/*.json` | One full triage record per email |
| `results/results.csv` | Submission table: email_id, category, priority, needs_human, quote, draft_reply |
| `index.html`, `app/` | Review dashboard (vanilla HTML/CSS/JS, works from file://) |
| `WRITEUP.md` | Submission write-up |
