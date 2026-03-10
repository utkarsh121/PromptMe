# LLM05: Improper Output Handling — Solution

**Goal:** Use the chat assistant to make the LLM generate and execute an SQL UPDATE that inflates your budget, then purchase an item to reveal the flag.

---

## Background

### What is Improper Output Handling?

LLMs produce text. That text can be code, markup, system commands, SQL queries, or anything else. **Improper Output Handling** happens when an application takes LLM output and passes it directly to a downstream interpreter — a shell, a database, a browser — without validation, sanitization, or parameterization.

The LLM is not "doing the injection". The injection happens because the application treats LLM output as trusted, executable input. From the database's perspective, LLM-generated SQL is no different from attacker-supplied SQL — it can read, modify, and (if not blocked) destroy data.

This is the LLM equivalent of classic injection vulnerabilities:
- LLM output → `eval()` = Remote Code Execution
- LLM output → SQL cursor = SQL Injection
- LLM output → HTML render = XSS

### What is being attacked in this lab?

The app is an e-commerce marketplace. Users register with a budget of **0** and cannot afford any items. A chat assistant on the `/chat` page accepts natural language questions about the database. Internally, the assistant:

1. Detects if the question requires SQL (keywords like "modify", "update", "list", "count")
2. Sends the question to the LLM with a SQL-generation prompt — which **includes an example of an UPDATE statement**
3. Executes the generated SQL directly: `cursor.execute(generated_sql)`
4. Returns the result to the user

There is no parameterization, no allowlist of safe operations, and the `is_dangerous_sql()` check only blocks `DROP`, `DELETE`, and `TRUNCATE` — **UPDATE is permitted**.

### How the lab demonstrates it

| Component | Role |
|-----------|------|
| `Market/utils/llm_utils.py` `generate_sql_prompt()` | Builds the LLM prompt with the DB schema and an UPDATE example |
| `Market/utils/llm_utils.py` `query_llm()` | Calls the LLM and extracts SQL from the response |
| `Market/routes.py` `/chat` | Executes `cursor.execute(generated_sql)` with no parameterization |
| `Market/routes.py` `/market` | Shows the flag when a user successfully purchases an item |

---

## Step 1 — Open the app

Start challenge 5 from the dashboard. Open `http://127.0.0.1:5005`.

---

## Step 2 — Register an account

Click **Register** and create a new account. After registration you are logged in automatically and redirected to the **Market** page.

Notice your budget is **0 $** — you cannot afford any item.

---

## Step 3 — Go to the Chat page

Click **Chat** in the navigation bar to open `http://127.0.0.1:5005/chat`.

---

## Step 4 — Inject via natural language

Type the following message (replace `yourname` with your actual username):

```
modify the budget of yourname to 10000
```

The assistant detects the keyword "modify", generates an SQL UPDATE via the LLM, and executes it directly. After a moment (LLM inference takes a few minutes on CPU), you'll see a response like:

```
✅ Query executed successfully.

(SQL Executed: UPDATE user SET budget = 10000 WHERE username = 'yourname';)
```

The LLM-generated SQL was executed without any parameterization or review.

---

## Step 5 — Purchase an item

Go back to the **Market** page (`http://127.0.0.1:5005/market`). Your budget now shows **10,000 $**.

Click **Purchase Item!** on any product. The flag appears:

```
FLAG-CTF{SQL_lnjecti0n_Succ3ful}
```

---

## Why This Works

**`Market/utils/llm_utils.py`** — the SQL generation prompt includes an UPDATE example, teaching the LLM exactly how to modify budgets:

```python
def generate_sql_prompt(natural_language_prompt):
    return f"""
...
Examples:
- "Modify the budget of user 'user01' to 10000" -> UPDATE user SET budget = 10000 WHERE username = 'user01';

ONLY return SQL. No explanations, no markdown.
Q: {natural_language_prompt}
A:"""
```

**`Market/routes.py`** — the generated SQL is executed directly with no parameterization:

```python
cursor.execute(generated_sql)   # ← no parameterization, no allowlist
```

**`Market/routes.py`** — the dangerous SQL check only blocks destructive operations, not data modification:

```python
def is_dangerous_sql(sql: str) -> bool:
    lowered = sql.lower()
    return any(danger in lowered for danger in ["drop", "delete", "truncate"])
    # UPDATE is not blocked
```

The LLM behaves exactly as instructed. The vulnerability is not in the model — it's in the application's decision to execute whatever the model returns.

---

## Vulnerable Code Summary

| File | Vulnerability |
|------|--------------|
| `Market/utils/llm_utils.py` `generate_sql_prompt()` | Prompt explicitly teaches the LLM to generate UPDATE statements |
| `Market/utils/llm_utils.py` `query_llm()` | Returns raw LLM output as executable SQL with no validation |
| `Market/routes.py` `/chat` | `cursor.execute(generated_sql)` — no parameterization, no operation allowlist |
| `Market/routes.py` `is_dangerous_sql()` | Only blocks DROP/DELETE/TRUNCATE; UPDATE and INSERT are permitted |

---

## Mitigation

**1. Never execute LLM output directly — use parameterized queries**

LLM output is untrusted input. Treat it the same way you treat user input from a web form.

```python
# VULNERABLE
cursor.execute(generated_sql)

# SAFE — parse intent, use parameterized query
def update_budget(username: str, amount: int):
    cursor.execute(
        "UPDATE user SET budget = ? WHERE username = ?",
        (amount, username)
    )
```

**2. Allowlist permitted SQL operations**

If the chat assistant only needs to answer questions (SELECT), do not allow write operations.

```python
ALLOWED_OPERATIONS = {"select"}

def is_safe_sql(sql: str) -> bool:
    first_word = sql.strip().split()[0].lower()
    return first_word in ALLOWED_OPERATIONS
```

**3. Use a read-only database connection for queries**

Open the DB connection in read-only mode so that even if an UPDATE is executed, it fails at the DB layer.

```python
import sqlite3
con = sqlite3.connect(f"file:{db_path}?mode=ro", uri=True)
```

**4. Restrict what data the LLM can access**

The SQL prompt exposes the full schema including the `budget` column. Restrict access: create a read-only view of non-sensitive columns and only expose that to the LLM.

**5. Do not include write examples in the LLM prompt**

The `generate_sql_prompt()` function explicitly demonstrates UPDATE syntax. Remove write examples from any prompt that feeds into an execution pipeline.

**6. Validate LLM output with a secondary check before execution**

Parse the generated SQL with a proper SQL parser (e.g., `sqlglot`) and reject anything that is not a SELECT or does not match the expected schema.

```python
import sqlglot

def is_safe_select(sql: str) -> bool:
    try:
        statements = sqlglot.parse(sql)
        return all(isinstance(s, sqlglot.expressions.Select) for s in statements if s)
    except Exception:
        return False
```
