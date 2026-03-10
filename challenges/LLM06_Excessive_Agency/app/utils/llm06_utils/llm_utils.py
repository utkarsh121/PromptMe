import os, time
import requests

OLLAMA_BASE_URL = os.getenv('OLLAMA_BASE_URL', 'http://localhost:11434')

def _ping(event, **kw):
    try:
        requests.post("http://localhost:5000/internal/llm-event",
                      json={"lab": "LLM06", "port": 5006, "event": event, **kw}, timeout=1)
    except Exception:
        pass

def query_llm(prompt):
    model = os.getenv('PROMPTME_CHAT_MODEL', 'mistral')
    _ping("start", model=model)
    t0 = time.time()
    try:
        response = requests.post(
            f"{OLLAMA_BASE_URL}/api/generate",
            json={"model": model, "prompt": prompt, "stream": False},
            timeout=600
        )
        response.raise_for_status()
        result = response.json().get("response", "").strip()
        _ping("done", elapsed=round(time.time()-t0, 1), words=len(result.split()))
        return result
    except Exception as e:
        _ping("done", elapsed=round(time.time()-t0, 1), words=0)
        return f"LLM Error: {e}"
