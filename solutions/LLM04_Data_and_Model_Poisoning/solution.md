# LLM04: Data and Model Poisoning — Solution

**Goal:** Discover that the LLM's knowledge base is a publicly editable CSV file, tamper with it to swap LLM01 out of the top position, then trigger the flag by querying the poisoned list.

---

## Background

### What is Data Poisoning in LLM applications?

LLM applications commonly use **Retrieval-Augmented Generation (RAG)** — instead of relying on the model's training alone, they pull answers from an external knowledge source at query time. The quality and trustworthiness of that source directly determines the quality and trustworthiness of the model's output.

**Data poisoning** is the attack where an adversary corrupts that source. If the knowledge base is editable — whether it's a shared spreadsheet, an open wiki, an unprotected file on disk, or a database with weak ACLs — an attacker can inject false, misleading, or harmful content. The LLM has no way to distinguish authentic data from poisoned data: it simply retrieves the nearest match and generates a response from it.

The consequences range from misinformation (the model gives wrong answers) to full exploitation (the model reveals flags, executes injections, or assists attackers).

### What is being attacked in this lab?

This app is a chatbot that answers questions about the OWASP LLM Top 10. Under the hood:

1. Questions are semantically matched against a CSV knowledge base (`test_docs/owasp_llm_qa.csv`) using a sentence-transformer embedding model
2. The matched Q&A pair is injected into a prompt sent to the LLM
3. The LLM generates a response based on that context

The **CSV file is accessible and writable** — it lives on disk with no access controls. The app even tells you where it is when you ask.

A tamper-detection mechanism watches for a specific sign of poisoning: if the answer to "List top 10 LLM Vulnerabilities" no longer starts with `LLM01: Prompt Injection`, the app concludes the data has been tampered with and appends the flag to the response.

### How the lab demonstrates it

| Component | Role |
|-----------|------|
| `test_docs/owasp_llm_qa.csv` | The unprotected knowledge base — editable by anyone with filesystem access |
| `llm_service_1.py` `is_tampered()` | Tamper check — detects if LLM01 is no longer first in the Top 10 list |
| `llm_service_1.py` `is_source_question()` | Reveals the knowledge base path when asked |
| **Reload Knowledge Base** button | Forces the app to re-read the CSV without restart |

---

## Step 1 — Open the app

Start challenge 4 from the dashboard. Open `http://127.0.0.1:5004`.

You'll see a simple chatbot with a text input and a **Reload Knowledge Base** button at the bottom.

---

## Step 2 — Discover the knowledge base

Ask the chatbot:

```
What is the source of information
```

The app responds:

```
My knowledge base comes from directory /test_docs/owasp_llm_qa.csv
```

The chatbot has leaked its own data source. This is by design — to teach students to look for information disclosure as part of recon.

---

## Step 3 — Examine the knowledge base

The file is at:

```
/home/utkarsh/Downloads/PromptMe/challenges/LLM04_Data_and_Model_Poisoning/test_docs/owasp_llm_qa.csv
```

Open it in any text editor. The first data row is the key one:

```
Question,Answer
List top 10 LLM Vulnerabilities,LLM01: Prompt Injection LLM02: Sensitive Information Disclosure LLM03: ...
```

---

## Step 4 — Verify baseline (optional)

Before poisoning, confirm normal behavior. Ask:

```
List top 10 LLM Vulnerabilities
```

You'll get a clean list starting with `LLM01: Prompt Injection` — no flag.

---

## Step 5 — Poison the knowledge base

Edit `test_docs/owasp_llm_qa.csv`. In the first data row, change the answer so that `LLM01: Prompt Injection` is **no longer the first item**. For example, swap LLM01 and LLM02:

**Before:**
```
List top 10 LLM Vulnerabilities,LLM01: Prompt Injection LLM02: Sensitive Information Disclosure ...
```

**After:**
```
List top 10 LLM Vulnerabilities,LLM02: Sensitive Information Disclosure LLM01: Prompt Injection ...
```

Save the file.

---

## Step 6 — Reload the knowledge base

Click the **Reload Knowledge Base** button in the app. You should see:

```
🔄 Knowledge base reloaded successfully!
```

This re-reads the CSV and re-encodes the embeddings — your poisoned data is now active.

---

## Step 7 — Trigger the flag

Ask the chatbot again:

```
List top 10 LLM Vulnerabilities
```

The response will now include the poisoned list followed by the flag:

```
...

flag{Data_P0!s0ning_Succ3ssfu1}
```

---

## Why This Works

**`llm_service_1.py`** — the source disclosure (direct string return, no LLM involved):

```python
SOURCE_QUESTION_KEYWORDS = [
    "source of information", "knowledge base", "training data", ...
]

def is_source_question(question: str) -> bool:
    lowered = question.lower()
    return any(keyword in lowered for keyword in SOURCE_QUESTION_KEYWORDS)

def get_answer(question: str) -> str:
    if is_source_question(question):
        return "My knowledge base comes from directory /test_docs/owasp_llm_qa.csv"
```

**`llm_service_1.py`** — the tamper detection on the raw CSV value:

```python
def is_tampered(answer: str) -> bool:
    lines = [line.strip().lower() for line in answer.strip().splitlines() if line.strip()]
    expected_first = "llm01: prompt injection"
    return not any(line.startswith(expected_first) for line in lines)

def get_answer(question: str) -> str:
    ...
    matched_q, matched_a = get_context_for_question(question)
    ...
    # Only run tamper check if question is about the Top 10
    if matched_q.strip().lower() == "list top 10 llm vulnerabilities":
        if is_tampered(matched_a):
            flag = "\n\nflag{Data_P0!s0ning_Succ3ssfu1}"
            answer += flag
```

The tamper check runs on `matched_a` — the **raw CSV value** — before the LLM generates its response. Once LLM01 is no longer first in that string, the flag is appended unconditionally.

There is no access control, no write-protection, no integrity check (e.g., file hash), and no audit log on the CSV file.

---

## Vulnerable Code Summary

| File | Vulnerability |
|------|--------------|
| `test_docs/owasp_llm_qa.csv` | No write protection — any user with filesystem access can edit the knowledge base |
| `llm_service_1.py` `get_answer()` | Directly reveals knowledge base path in response; no validation of source integrity |
| `app4.py` `/reload` | Anyone can trigger a hot-reload of poisoned data with no authentication |
| `llm_service_1.py` `reload_knowledge_base()` | Reads CSV with no checksum or signature verification |

---

## Mitigation

**1. Enforce strict read-only access on knowledge base files**

Knowledge base files used for RAG should be owned by a dedicated service account with read-only permissions. Application users and web processes should not be able to write to them.

```bash
# Make the knowledge base read-only for the app user
chmod 444 test_docs/owasp_llm_qa.csv
chown admin:admin test_docs/owasp_llm_qa.csv
```

**2. Verify knowledge base integrity before loading**

Maintain a SHA-256 hash of the knowledge base. Verify it on every load — reject and alert on mismatch.

```python
import hashlib

EXPECTED_HASH = "abc123..."   # computed from the trusted version

def reload_knowledge_base():
    with open(CSV_PATH, "rb") as f:
        actual_hash = hashlib.sha256(f.read()).hexdigest()
    if actual_hash != EXPECTED_HASH:
        raise RuntimeError("Knowledge base integrity check failed — possible tampering")
    # proceed with load
```

**3. Protect the reload endpoint**

The `/reload` endpoint accepts unauthenticated POST requests. It should require admin authentication.

```python
from functools import wraps
from flask import session, abort

def require_admin(f):
    @wraps(f)
    def decorated(*args, **kwargs):
        if not session.get("is_admin"):
            abort(403)
        return f(*args, **kwargs)
    return decorated

@app.route("/reload", methods=["POST"])
@require_admin
def reload_data():
    ...
```

**4. Never expose internal data source paths**

The app directly returns the knowledge base file path in its response. This aids attackers in reconnaissance. Strip internal paths from all user-facing outputs.

**5. Use immutable, version-controlled knowledge bases**

Store knowledge base content in a version-controlled system (e.g., Git). Deploy only approved, signed versions. Reject runtime modifications. Use an append-only audit log for any change.

**6. Apply input/output monitoring**

Log all questions and answers. Alert when the output distribution changes significantly — e.g., a previously stable "Top 10" answer suddenly changes order. Anomaly detection on RAG outputs can catch poisoning early.
