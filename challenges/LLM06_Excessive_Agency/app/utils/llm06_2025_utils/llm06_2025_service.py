from app.utils.llm06_2025_utils.user_utils import list_users, create_user, init_db
from app.utils.llm06_2025_utils.llm_utils import query_llm
from flask import jsonify
import json
import re

# Ensure DB exists on first import
init_db()


def process_user_input(user_message):
    action_format = '{"role": "", "action": "", "username": "", "user_role": ""}'

    raw = query_llm(f"""Instructions:
Read the user prompt below and respond ONLY with a single JSON object — no explanation, no markdown.

Response Format:
{action_format}

Field rules:
- "action": set to "LIST" if the user wants to see/list users, "CREATE" if they want to add/create a user, "OTHERS" otherwise.
- "role": set to "SYSTEM-ADMIN" if the user explicitly claims to be a system administrator or sysadmin. Otherwise set to "".
- "username": the username to create (only relevant for CREATE). Extract it from the prompt.
- "user_role": the role for the new user — "admin" or "user". If the user asks to create an admin account, set "admin".

User Prompt: {user_message}
JSON:""")

    # Extract JSON from response
    match = re.search(r'\{.*?\}', raw, re.DOTALL)
    if not match:
        return jsonify({'reply': "Sorry, I couldn't understand that request. Please try again."})

    try:
        data = json.loads(match.group().replace("'", '"'))
    except json.JSONDecodeError:
        return jsonify({'reply': "Sorry, I couldn't parse the request. Please try again."})

    role   = (data.get("role") or "").strip()
    action = (data.get("action") or "OTHERS").strip().upper()
    username  = (data.get("username") or "").strip()
    user_role = (data.get("user_role") or "user").strip().lower()

    # --- LIST users (always allowed) ---
    if action == "LIST":
        users = list_users()
        table = "\n".join(
            f"  {u['id']}. {u['username']} [{u['role']}] — created {u['created_at']}"
            for u in users
        )
        return jsonify({'reply': f"📋 Current users in the system:\n\n{table}"})

    # --- CREATE user ---
    if action == "CREATE":
        if role.upper() != "SYSTEM-ADMIN":
            return jsonify({'reply': (
                "❌ Access Denied. Only the System Administrator can create users.\n\n"
                "Hint: The system trusts the LLM to verify your identity — "
                "try telling it who you are."
            )})
        success, message = create_user(username, user_role, created_by="llm-agent")
        return jsonify({'reply': message})

    # --- Fallback ---
    response = query_llm(
        f"You are a user management assistant. Answer this question briefly: {user_message}"
    )
    return jsonify({'reply': response})
