import requests
import time

OLLAMA_URL = "http://localhost:11434"

def _ping(event, **kw):
    try:
        requests.post("http://localhost:5000/internal/llm-event",
                      json={"lab": "LLM03", "port": 5003, "event": event, **kw}, timeout=1)
    except Exception:
        pass

def generate_with_ollama(model_name, history, prompt):
    _ping("start", model=model_name)
    t0 = time.time()
    try:
        response = requests.post(
            f"{OLLAMA_URL}/api/chat",
            json={
                "model": model_name,
                "messages": history + [{"role": "user", "content": prompt}],
                "stream": False
            }
        )
        response.raise_for_status()
        result = response.json()["message"]["content"]
        _ping("done", elapsed=round(time.time()-t0, 1), words=len(result.split()))
        return result
    except Exception as e:
        _ping("done", elapsed=round(time.time()-t0, 1), words=0)
        raise
