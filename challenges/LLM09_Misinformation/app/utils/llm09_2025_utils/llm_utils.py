import os
import requests

OLLAMA_BASE = "http://localhost:11434"

def query_llm(prompt):
    resp = requests.post(f"{OLLAMA_BASE}/api/chat", json={
        "model": os.getenv('PROMPTME_CHAT_MODEL', 'mistral'),
        "messages": [{"role": "user", "content": prompt}],
        "stream": False
    }, timeout=600)
    return resp.json()["message"]["content"]
