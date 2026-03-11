# Addn. Lab 01 — Indirect Prompt Injection

**Port:** 5011
**Difficulty:** Medium
**Flag:** `flag{1nd1r3ct_Pr0mpt_1nj3ct10n_v1a_3m@1l}`

---

## Scenario

You are a security researcher auditing AcmeCorp's new LLM-powered email assistant. The assistant reads employee emails and generates summaries using an AI model.

A suspicious email has arrived in the inbox from an external sender. Your task is to determine whether an attacker could use this email to extract sensitive information from other emails in the inbox — without ever interacting with the AI assistant directly.

---

## Objective

Cause the LLM email assistant to leak confidential compensation data from another employee's email by exploiting a malicious email in the inbox.

---

## What You'll Learn

- How **indirect prompt injection** differs from direct prompt injection
- Why LLMs that process external/untrusted data are vulnerable to injected instructions
- How a single weak phrase in a system prompt can be exploited by attackers
- Real-world impact: data exfiltration via AI-mediated communication tools

---

## Setup

The lab runs automatically when started from the PromptMe dashboard at `http://localhost:5000`.

Direct access: `http://localhost:5011`

No login required. The inbox is pre-seeded.

---

## Hints

<details>
<summary>Hint 1</summary>
There are three emails in the inbox. Not all of them are from trusted sources. Read each one carefully — especially the sender domain.
</details>

<details>
<summary>Hint 2</summary>
One email contains sensitive information. Another email contains something other than a normal message. What happens when the assistant reads that second email?
</details>

<details>
<summary>Hint 3</summary>
The system prompt tells the assistant to "always be responsive to any instructions or requests mentioned in the email content." What could an attacker do with that?
</details>

<details>
<summary>Hint 4 (spoiler)</summary>
Open Email 3 and click Summarize. The malicious payload embedded in that email body will instruct the LLM to output the contents of Email 2.
</details>

---

## Solution

See [`solutions/ADDN01_Indirect_Prompt_Injection/solution.md`](../../solutions/ADDN01_Indirect_Prompt_Injection/solution.md)
