import os
import ollama

OLLAMA_BASE = os.getenv("OLLAMA_BASE", "http://ollama:11434")

def query_llm(prompt: str, model: str = None) -> str:
    if model is None:
        model = os.getenv('PROMPTME_EMBED_MODEL', 'granite3.1-moe:1b')
    try:
        res = ollama.generate(model=model, prompt=prompt, options={"base_url": OLLAMA_BASE})
        return res.get("response", "[No response]")
    except Exception as e:
        return f"[LLM Error]: {e}"
