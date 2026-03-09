import ollama
import os

def query_llm(prompt):
    response = ollama.chat(model=os.getenv('PROMPTME_CHAT_MODEL', 'mistral'), messages=[{'role': 'user', 'content': prompt}])
    return response['message']['content']
