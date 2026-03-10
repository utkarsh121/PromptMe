import os, time
import requests

OLLAMA_BASE = "http://localhost:11434"

def _ping(event, **kw):
    try:
        requests.post("http://localhost:5000/internal/llm-event",
                      json={"lab": "LLM09", "port": 5009, "event": event, **kw}, timeout=1)
    except Exception:
        pass

def query_llm(prompt):
    model = os.getenv('PROMPTME_CHAT_MODEL', 'mistral')
    _ping("start", model=model)
    t0 = time.time()
    try:
        resp = requests.post(f"{OLLAMA_BASE}/api/chat", json={
            "model": model,
            "messages": [{"role": "user", "content": prompt}],
            "stream": False
        }, timeout=1200)
        data = resp.json()
        if "error" in data:
            _ping("done", elapsed=round(time.time()-t0, 1), words=0)
            return f"[LLM Error]: {data['error']}"
        result = data["message"]["content"]
        _ping("done", elapsed=round(time.time()-t0, 1), words=len(result.split()))
        return result
    except Exception as e:
        _ping("done", elapsed=round(time.time()-t0, 1), words=0)
        return f"[LLM Error]: {e}"
