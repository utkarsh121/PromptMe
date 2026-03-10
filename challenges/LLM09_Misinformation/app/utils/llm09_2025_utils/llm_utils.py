import os
import requests

OLLAMA_BASE = "http://localhost:11434"

def query_llm(prompt):
    try:
        resp = requests.post(f"{OLLAMA_BASE}/api/chat", json={
            "model": os.getenv('PROMPTME_CHAT_MODEL', 'mistral'),
            "messages": [{"role": "user", "content": prompt}],
            "stream": False
        }, timeout=1200)
        data = resp.json()
        if "error" in data:
            return f"[LLM Error]: {data['error']}"
        return data["message"]["content"]
    except Exception as e:
        return f"[LLM Error]: {e}"
