from flask import request, render_template
from app import app
from app.utils.llm06_utils.llm06_service import process_user_input

@app.route("/")
def home():
    return render_template("index.html")


@app.route('/chat', methods=['POST'])
def chat():
    data = request.json
    user_message = data.get('message', '')
    return process_user_input(user_message)
