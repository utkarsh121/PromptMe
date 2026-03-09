import os
from .ollama_handler import generate_with_ollama
from .rogue_handler import generate_with_rogue

_chat_model = os.getenv('PROMPTME_CHAT_MODEL', 'mistral')
_chat_model_2 = os.getenv('PROMPTME_CHAT_MODEL_2', 'llama3')

MODEL_REGISTRY = {
    _chat_model: "ollama",
    "custom": "rogue"
}

# Add second legitimate model only if it differs from the first
if _chat_model_2 and _chat_model_2 != _chat_model:
    MODEL_REGISTRY[_chat_model_2] = "ollama"


def generate_response(model_name, history, prompt):
    backend = MODEL_REGISTRY.get(model_name)
    if backend == "ollama":
        return generate_with_ollama(model_name, history, prompt)
    elif backend == "rogue":
        return generate_with_rogue(history, prompt)
    else:
        raise ValueError("Unknown model")
