import re
import os
import requests
import time

OLLAMA_BASE_URL = os.getenv('OLLAMA_BASE_URL', 'http://localhost:11434')

def _ping(event, **kw):
    try:
        requests.post("http://localhost:5000/internal/llm-event",
                      json={"lab": "LLM05", "port": 5005, "event": event, **kw}, timeout=1)
    except Exception:
        pass

def generate_sql_prompt(natural_language_prompt):
    return f"""Convert the English request below into a single SQLite query. Output ONLY the SQL statement, nothing else.

Tables:
- user(id, username, email_address, password_hash, budget)
- item(id, name, barcode, price, description, owner)

Examples:
"How many users?" → SELECT COUNT(*) FROM user;
"List all products" → SELECT * FROM item;
"Modify the budget of alice to 10000" → UPDATE user SET budget = 10000 WHERE username = 'alice';
"Change the budget of bob to 500" → UPDATE user SET budget = 500 WHERE username = 'bob';

Request: {natural_language_prompt}
SQL:"""



def extract_sql_from_output(output: str) -> str:
    """
    Extracts the actual SQL query from LLM output.
    """
    # Strip markdown code fences
    output = re.sub(r"^```sql\s*", "", output, flags=re.IGNORECASE).strip()
    output = re.sub(r"^```\s*", "", output).strip()
    output = re.sub(r"```$", "", output).strip()

    # Try to grab SQL up to first semicolon
    match = re.search(r"(SELECT|INSERT|UPDATE|DELETE)[\s\S]+?;", output, re.IGNORECASE)
    if match:
        return match.group(0).strip()

    # No semicolon — grab from first SQL keyword to end of first line
    match = re.search(r"(SELECT|INSERT|UPDATE|DELETE).+", output, re.IGNORECASE)
    if match:
        return match.group(0).strip()

    return output.strip()

def query_llm(prompt: str, model=None):
    """
    Sends a prompt to the LLM via Ollama HTTP API and extracts + sanitizes the SQL query.
    """
    if model is None:
        model = os.getenv('PROMPTME_SQL_MODEL', 'sqlcoder')

    print("🔥 Calling Ollama with prompt:", prompt)
    _ping("start", model=model)
    t0 = time.time()

    try:
        response = requests.post(
            f"{OLLAMA_BASE_URL}/api/generate",
            json={"model": model, "prompt": prompt, "stream": False},
            timeout=600
        )
        response.raise_for_status()
        raw_output = response.json().get("response", "").strip()
        _ping("done", elapsed=round(time.time()-t0, 1), words=len(raw_output.split()))
    except Exception as e:
        _ping("done", elapsed=round(time.time()-t0, 1), words=0)
        print("LLM ERROR:", e)
        return "LLM Error: Model not found or execution failed."

    # Extract and sanitize SQL
    sql = extract_sql_from_output(raw_output)
    return sanitize_sql(sql)

def sanitize_sql(sql_query: str):
    """
    Cleans the SQL query to be compatible with SQLite.
    """
    if sql_query.lower().startswith("show"):
        sql_query = re.sub(r"show", "select", sql_query, flags=re.IGNORECASE)

    if "count" in sql_query.lower() and "from" not in sql_query.lower():
        sql_query = re.sub(r"count\((.*?)\)", "count(*)", sql_query, flags=re.IGNORECASE)

    # Remove thousand-separator commas inside numbers (e.g. 10,000 → 10000)
    sql_query = re.sub(r'(\d),(\d{3})', r'\1\2', sql_query)

    # Fix garbled numeric values in SET clauses (e.g. 1decafe, 1CT000 → extract digits only)
    def clean_set_value(m):
        prefix, val = m.group(1), m.group(2)
        if re.search(r'\d', val) and re.search(r'[a-zA-Z]', val):
            val = re.sub(r'[^0-9]', '', val)
        return prefix + val
    sql_query = re.sub(r'(=\s*)([^\s,;\'\"]+)', clean_set_value, sql_query)

    # Truncate anything after the first semicolon
    if ";" in sql_query:
        sql_query = sql_query[:sql_query.index(";") + 1]

    return sql_query.strip()

def should_generate_sql(user_message):
    """
    Determines if the user's message requires an SQL query or not.
    """
    message = user_message.lower()

    # If it’s a schema or metadata question, skip SQL generation
    schema_keywords = ["schema", "table structure", "columns", "fields", "tables"]
    if any(word in message for word in schema_keywords):
        return False

    sql_keywords = ["how many", "count", "total", "select", "items", "users", "prices", "sum", "average", "list", "update", "modify", "change", "set", "increase", "decrease"]
    return any(keyword in message for keyword in sql_keywords)



def result_to_nl(user_message, sql_query, rows):
    """
    Converts SQL output rows into a natural-language explanation.
    """
    if not rows:
        return "No results found."

    if "count" in sql_query.lower():
        return f"There are {rows[0][0]} results."

    # Render all rows for general SELECT
    return f"Here are the results:\n{rows}"
