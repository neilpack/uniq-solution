# How to use the UNIQ Inbox Assistant

**What you need:** a Windows PC with [Claude Code](https://claude.com/claude-code) installed, and this repo downloaded or cloned. You don't need an API key, Node, or Python.

## Step 1: Add the new emails
Put them in `packet/inbox.csv` using the same columns: `email_id, received_at, from_name, from_email, subject, body`. For a single email, you can skip this and paste it in at Step 3.

## Step 2: Set today's date
Open `data/pricing.json` and change `"today"` to the current date (for example `"2027-03-09"`). Lead times and the return and damage windows are all counted from this date.

## Step 3: Run the AI
Open Claude Code in the repo folder and type one of these:
- `/uniq-inbox all`: processes every email in the inbox file
- `/uniq-inbox E07`: processes one email by its ID
- `/uniq-inbox` followed by a pasted email: processes one new email (it gets the next free ID)

For each email, the AI checks order history, gets exact pricing from the quote engine, sets a priority, decides whether the owner needs to step in, and writes a draft reply. When it finishes, it prints a summary table and the top 3 emails for the owner.

## Step 4: Open the dashboard
Double-click `index.html`. At the top you'll see:
- **Tiles:** how many emails are at each priority, how many need a human, and the total dollar value quoted. Click a tile to filter.
- **Owner queue:** every flagged email, most urgent first, each with a one-line note on what the owner needs to decide.

## Step 5: Review each email
Click an email in the list on the left. The right panel shows:
- The summary and the **Needs human** reason
- The **draft reply**, which you can edit right there (edits save automatically in your browser)
- The **quote**, with the full math from the pricing engine
- The customer's **order history** and the **original email**

Use the search box, the P1–P4 chips, the category dropdown, or the "Needs human" checkbox to narrow the list.

## Step 6: Send the replies
- **Copy reply** copies the text so you can paste it into your email program.
- **Open in email** opens a new email already addressed to the customer, with the subject and reply filled in.
- For emails marked "Needs human", the owner reviews the draft before anything is sent.
- Emails marked "No reply" (spam, phishing, sales pitches) don't need any action.

## Step 7: Track your progress
Tick **Reviewed** and **Sent / handled** on each email. Check **Hide sent** to see only what's left.

## Step 8: Export (optional)
Click **Download CSV** to get the full results table, including any edits you made to the drafts.

---

**Tip:** if custom cup prices change, update both `packet/knowledge_base.md` and `data/pricing.json`, then run:

```
powershell -ExecutionPolicy Bypass -File tools/test-quote.ps1
```

to check the math still works.
