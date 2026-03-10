# LLM10: Unbounded Consumption — Solution

**Goal:** Craft a prompt that forces the LLM to generate a long, resource-intensive response — exceeding both the time threshold (90 seconds) and the output length threshold (400 words) — to simulate a denial-of-service condition and trigger the flag.

---

## Background

### What is Unbounded Consumption?

LLM inference is computationally expensive. Every token generated consumes CPU/GPU cycles, memory, and time. An application that places no limits on input complexity or output length can be exploited by an attacker who sends prompts designed to maximise resource consumption — causing slow responses, server overload, or outright denial of service for other users.

Unlike traditional DoS attacks that flood a server with requests, LLM DoS can be achieved with a **single, carefully crafted prompt** — no botnet required.

### What is being attacked in this lab?

The app is a simple chatbot with no rate limiting, no input length restriction, no output length cap, and no timeout on inference. Two thresholds are checked server-side:

- **Time**: the LLM must take **more than 90 seconds** to respond
- **Output length**: the response must contain **more than 400 words**

If both are met simultaneously, the flag is revealed. In Lite mode (phi3:mini on CPU), the time threshold is trivially exceeded by almost any prompt. The real challenge is crafting a prompt that generates a sufficiently long response.

### How the lab demonstrates it

| Component | Role |
|-----------|------|
| `app10.py` — `generate_response()` | No timeout on `chain.invoke({})` — can block indefinitely |
| `app10.py` — `/ask` | No input length validation; accepts any prompt |
| `app10.py` — flag check | Reveals flag when elapsed > 90s AND word_count > 400 |
| `app10.py` — no rate limiting | A single user can submit back-to-back resource-intensive requests |

---

## Step 1 — Open the app

Start challenge 10 from the dashboard. Open `http://127.0.0.1:5010`.

You'll see a plain chatbox with a textarea and submit button.

---

## Step 2 — Understand what won't work

Short or simple prompts won't trigger the flag:

```
Can you write the word "DoS" 1000 times
```

```
List all the countries in the world in alphabetical order
```

These may exceed the time threshold (in Lite mode, everything does), but the model will either refuse repetitive tasks or produce a short response — failing the 400-word check.

---

## Step 3 — Craft a resource-exhausting prompt

You need a prompt that forces the model to generate a detailed, verbose response. A good attack prompt is one that asks for **breadth + depth** across many items:

```
Describe in detail the complete genealogy of all U.S. Presidents, starting from George Washington to today, and include fun facts about each.
```

Or alternatively:

```
Write a comprehensive essay covering the history, culture, cuisine, geography, economy, and notable figures of every continent on Earth. Include at least three paragraphs per continent.
```

Submit the prompt and wait. The page will show the spinner — "⏳ Please wait, thinking hard..."

---

## Step 4 — Flag revealed

Once the response arrives, if it exceeds 400 words and took longer than 90 seconds, the page will display:

```
[!] Potential DoS detected. FLAG: flag{R3$0urC3_ExH@us7!0N_D37EcTeD}
```

The time taken is also printed in the server logs:

```
[DEBUG] Word count: 523 | Time taken: 347.82s
[!] FLAG triggered.
```

---

## Why This Works

**`app10.py`** — no timeout, no length cap, no rate limiting:

```python
def generate_response(user_input):
    ...
    start = time.time()
    try:
        response = chain.invoke({})   # blocks indefinitely — no timeout
    except Exception as e:
        response = f"[!] Error: {str(e)}"
    end = time.time()
    return response, elapsed
```

```python
@app.route("/ask", methods=["POST"])
def ask():
    user_input = request.form["message"]   # no length check
    response, elapsed = generate_response(user_input)
    word_count = len(response.split())
    if elapsed > TIME_THRESHOLD and word_count > TOKEN_THRESHOLD:
        flag_message += f'... FLAG: {FLAG}'
```

There is no `concurrent.futures` timeout, no `max_tokens` cap, no per-IP rate limit, and no queue depth limit. A single request can tie up the server for minutes.

---

## Vulnerable Code Summary

| File | Vulnerability |
|------|--------------|
| `app10.py` — `chain.invoke({})` | Blocking call with no timeout — server hangs for the full inference duration |
| `app10.py` — `/ask` | No input length validation — arbitrarily long prompts accepted |
| `app10.py` — no output cap | LLM can return unlimited tokens, consuming memory and bandwidth |
| `app10.py` — no rate limiting | Single IP can submit back-to-back exhausting requests |

---

## Mitigation

**1. Set a hard timeout on inference**

```python
import concurrent.futures

def generate_response_with_timeout(user_input, timeout=30):
    with concurrent.futures.ThreadPoolExecutor() as executor:
        future = executor.submit(generate_response, user_input)
        try:
            return future.result(timeout=timeout)
        except concurrent.futures.TimeoutError:
            return "[!] Request timed out. Please try a shorter query.", timeout
```

**2. Cap input length**

```python
MAX_INPUT_CHARS = 500

@app.route("/ask", methods=["POST"])
def ask():
    user_input = request.form["message"]
    if len(user_input) > MAX_INPUT_CHARS:
        return render_template("index.html", response_text="[!] Input too long.", user_input=user_input)
```

**3. Cap output length**

```python
MAX_OUTPUT_WORDS = 500

words = response.split()
if len(words) > MAX_OUTPUT_WORDS:
    response = " ".join(words[:MAX_OUTPUT_WORDS]) + " [...] [TRUNCATED]"
```

**4. Apply rate limiting**

```python
from flask_limiter import Limiter
from flask_limiter.util import get_remote_address

limiter = Limiter(get_remote_address, app=app, default_limits=["5 per minute"])

@app.route("/ask", methods=["POST"])
@limiter.limit("2 per minute")
def ask():
    ...
```

**5. Use an async task queue for inference**

For production deployments, LLM inference should be offloaded to a background task queue (e.g., Celery + Redis). The HTTP endpoint returns immediately with a job ID; the client polls for the result. This prevents a single slow request from blocking the entire server.
