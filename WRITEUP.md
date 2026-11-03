# Submission write-up (draft for the reply email)

**What I built.** A Claude Code skill (`/uniq-inbox`) works the inbox. A PowerShell pricing engine does all the quote math, and a plain HTML/CSS/JS dashboard lets the team review, edit, copy, and track every reply. Claude reads each email, checks order history, classifies, prioritizes, runs the 7-point escalation checklist, and drafts a reply in brand voice (in Spanish and French where needed). Every custom price comes from `tools/quote.ps1`, which never guesses: it picks the eligible production paths and tier, adds setup and freight, works out the ship window from proof approval, and flags anything over $5k, outside the lower 48, or needing a rush. Thirty regression tests cover every quote in this inbox. It's built for Tuesday: drop new emails into a CSV (or paste one), run `/uniq-inbox all`, and open `index.html`.

**If the owner can only read 3 today:**
1. **E05, Big Sky festival:** $6,390 (or $7,281 with the 2-week rush), and they need a firm yes/no today. Standard USA lead time puts April 5 at risk, overseas is impossible, and only the owner can approve a rush.
2. **E03, Sweet Basin Creamery:** the biggest opportunity in the inbox. A 14-shop chain unhappy with its vendor: $10,900 overseas or $16,650 USA, recurring business.
3. **E10, Hollis price match:** an "order today or I walk" ultimatum at 7¢ vs our published 12.8¢. Only the owner can decide whether to respond beyond published pricing, and it's lost by tonight if no one does.

(Also flagged but less time-critical: E08 custom-color complaint, E16 hidden AI instructions/discount, E12 Canada freight, E13 Net 30, E14 phishing.)

**What I'd build next with a week:**
- Connect it to the real mailbox (Gmail/Outlook) so emails flow in and approved drafts go out as replies, with no copying and pasting.
- Generate `pricing.json` straight from the knowledge base, so pricing lives in one place.
- Add a carrier transit-time lookup, so we can say "arrives by" instead of "ships by".
- Build a small eval set of tricky emails that re-runs whenever the rules change.

**Known gaps and assumptions (honest list):**
- **Transit times:** the KB has none, so dates are "ships approximately," assuming the proof is approved the next business day. On deadline emails I kept a 5-business-day transit cushion.
- **Holidays:** business days skip weekends only.
- **Pricing in two places:** custom pricing exists in both the KB and `pricing.json`, so it has to be updated in both (the tests catch drift on known cases).
- **Missing color counts:** where the logo color count was missing (E10, E12), I quoted 1 and 2 colors.
- **Need-by dates:** "season starting in May" was read as May 1 (E03).
- **Currency:** prices are assumed USD for the Canadian customer; the owner should confirm.
- **Runs inside Claude Code:** the AI step needs Claude Code (there's no API key, so no hosted app). The dashboard itself runs anywhere.
- **Judgment calls:** E02 and E20 are judgment calls on priority (P2 and P3).

**Process / prompts.**
- The full prompts are the skill files: `.claude/skills/uniq-inbox/SKILL.md` (the workflow) and `reference/rules.md` (judgment rules).
- I built it with Claude Code: I read the KB and all 20 emails first, wrote an answer key by hand, built and tested the pricing engine against it, then ran the skill on all 20 and checked every row against the key.
- I also ran a made-up "Tuesday" email (Alaska shipping, 8,500 photo-logo cups) through the skill to confirm it handles new cases. That run surfaced a rounding improvement in the engine, which I fixed.
