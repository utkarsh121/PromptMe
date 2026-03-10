import os, time
import requests

OLLAMA_BASE = "http://localhost:11434"

def _ping(event, **kw):
    try:
        requests.post("http://localhost:5000/internal/llm-event",
                      json={"lab": "LLM08", "port": 5008, "event": event, **kw}, timeout=1)
    except Exception:
        pass

def query_llm(prompt: str, model: str = None) -> str:
    if model is None:
        model = os.getenv('PROMPTME_EMBED_MODEL', 'granite3.1-moe:1b')
    _ping("start", model=model)
    t0 = time.time()
    try:
        resp = requests.post(f"{OLLAMA_BASE}/api/generate", json={
            "model": model,
            "prompt": prompt,
            "stream": False
        }, timeout=600)
        result = resp.json().get("response", "[No response]")
        _ping("done", elapsed=round(time.time()-t0, 1), words=len(result.split()))
        return result
    except Exception as e:
        _ping("done", elapsed=round(time.time()-t0, 1), words=0)
        return f"[LLM Error]: {e}"
