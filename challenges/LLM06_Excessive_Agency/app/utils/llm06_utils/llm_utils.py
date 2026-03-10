import os
import requests

OLLAMA_BASE_URL = os.getenv('OLLAMA_BASE_URL', 'http://localhost:11434')

def query_llm(prompt):
    model = os.getenv('PROMPTME_CHAT_MODEL', 'mistral')
    try:
        response = requests.post(
            f"{OLLAMA_BASE_URL}/api/generate",
            json={"model": model, "prompt": prompt, "stream": False},
            timeout=600
        )
        response.raise_for_status()
        return response.json().get("response", "").strip()
    except Exception as e:
        return f"LLM Error: {e}"
