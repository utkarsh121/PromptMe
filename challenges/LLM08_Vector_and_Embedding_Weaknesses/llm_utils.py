import os
import requests

OLLAMA_BASE = "http://localhost:11434"

def query_llm(prompt: str, model: str = None) -> str:
    if model is None:
        model = os.getenv('PROMPTME_EMBED_MODEL', 'granite3.1-moe:1b')
    try:
        resp = requests.post(f"{OLLAMA_BASE}/api/generate", json={
            "model": model,
            "prompt": prompt,
            "stream": False
        }, timeout=600)
        return resp.json().get("response", "[No response]")
    except Exception as e:
        return f"[LLM Error]: {e}"
