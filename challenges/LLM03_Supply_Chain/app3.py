import subprocess
import threading
import os
import sys
import requests
from flask import Flask, render_template, request, jsonify, session
from models import generate_response, MODEL_REGISTRY
from flask_cors import CORS

app = Flask(__name__)
app.secret_key = "S3cret_Key"  # Needed for session
CORS(app)  # Allow frontend JS to call backend APIs

# ----- Home page -----
@app.route("/")
def index():
    return render_template("index.html")

# ----- List available models -----
@app.route("/models", methods=["GET"])
def list_models():
    return jsonify({"models": list(MODEL_REGISTRY.keys())})

# ----- Initialize model (could add lazy loading later) -----
@app.route("/init_model", methods=["POST"])
def init_model():
    data = request.json
    model_name = data.get("model")
    if model_name not in MODEL_REGISTRY:
        return jsonify({"error": "Invalid model"}), 400
    session["model"] = model_name
    session["history"] = []
    return jsonify({"message": f"{model_name} initialized"})

# ----- Handle chat -----
@app.route("/chat", methods=["POST"])
def chat():
    data = request.json
    prompt = data.get("prompt")
    model_name = session.get("model")
    history = session.get("history", [])

    if not model_name:
        return jsonify({"error": "Model not initialized"}), 400

    # Generate response
    response = generate_response(model_name, history, prompt)

    # Save conversation
    history.append({"role": "user", "content": prompt})
    history.append({"role": "assistant", "content": response})
    session["history"] = history

    return jsonify({"response": response})

CHALLENGE_DIR = os.path.dirname(os.path.abspath(__file__))

def start_secret_service():
    subprocess.Popen(
        [sys.executable, "config/secret-service.py"],
        cwd=CHALLENGE_DIR,
        stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, close_fds=True
    )

@app.route('/monitor/exfil')
def monitor_exfil():
    try:
        r = requests.get('http://127.0.0.1:5012/exfil', timeout=2)
        return jsonify(r.json())
    except Exception as e:
        return jsonify({"error": str(e)}), 503

@app.route('/monitor/flag')
def monitor_flag():
    try:
        r = requests.get('http://127.0.0.1:5012/flag', timeout=2)
        return jsonify(r.json())
    except Exception as e:
        return jsonify({"error": str(e)}), 503

@app.route('/prelab-cleanup', methods=['POST'])
def prelab_cleanup():
    import signal, time
    # Kill any process on port 5012
    result = subprocess.run(['lsof', '-ti:5012'], capture_output=True, text=True)
    killed = 0
    for pid in result.stdout.strip().split('\n'):
        if pid.strip():
            try:
                os.kill(int(pid.strip()), signal.SIGKILL)
                killed += 1
            except Exception:
                pass
    time.sleep(1)
    start_secret_service()
    time.sleep(1)
    return jsonify({"status": "ok", "message": f"Cleaned up {killed} old process(es). Exfil server restarted fresh."})

if __name__ == "__main__":
    threading.Thread(target=start_secret_service, daemon=True).start()
    app.run(host="0.0.0.0", port=5003, debug=False)
