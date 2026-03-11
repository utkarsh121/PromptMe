from flask import Flask, render_template, redirect, request, jsonify, Response, stream_with_context
import subprocess, sys, os, requests, psutil, time, socket, json
from collections import deque
from threading import Lock

app = Flask(__name__)

running_apps = {}

# ── Lite-mode hardcoded model constants ───────────────────────────
MODELS_LITE = ['phi3:mini', 'granite3.1-moe:1b']

LITE_ENV = {
    'PROMPTME_CHAT_MODEL':     'phi3:mini',
    'PROMPTME_CHAT_MODEL_2':   'phi3:mini',
    'PROMPTME_SQL_MODEL':      'phi3:mini',
    'PROMPTME_GUARDIAN_MODEL': 'granite3.1-moe:1b',
    'PROMPTME_EMBED_MODEL':    'granite3.1-moe:1b',
}

OLLAMA_BASE = "http://localhost:11434"

# ── LLM activity feed (last 40 events, thread-safe) ───────────────
activity_log = deque(maxlen=40)
activity_lock = Lock()
activity_listeners = []
activity_listeners_lock = Lock()


def push_activity(event: dict):
    event.setdefault('ts', time.strftime('%H:%M:%S'))
    with activity_lock:
        activity_log.append(event)
    msg = f"data: {json.dumps(event)}\n\n"
    with activity_listeners_lock:
        dead = []
        for q in activity_listeners:
            try:
                q.append(msg)
            except Exception:
                dead.append(q)
        for q in dead:
            activity_listeners.remove(q)


# ── Helpers ────────────────────────────────────────────────────────

def is_port_in_use(port):
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
        return s.connect_ex(('localhost', port)) == 0


def start_challenge(port, app_path):
    if is_port_in_use(port):
        raise RuntimeError(f"Port {port} is already in use.")

    os.makedirs("logs", exist_ok=True)
    env = os.environ.copy()
    env.update(LITE_ENV)

    with open(f"logs/challenge_{port}.log", "w") as log:
        process = subprocess.Popen(
            [sys.executable, app_path],
            stdout=log, stderr=log,
            close_fds=True, env=env
        )
    running_apps[port] = process


def wait_until_responsive(url, timeout=30):
    start = time.time()
    while time.time() - start < timeout:
        try:
            if requests.get(url, timeout=2).status_code == 200:
                return True
        except Exception:
            pass
        time.sleep(1)
    return False


# ── Dashboard ──────────────────────────────────────────────────────

@app.route('/')
def dashboard():
    risks = [
        {'id': 1,  'title': 'Prompt Injection',           'icon': 'fas fa-code'},
        {'id': 2,  'title': 'Sensitive Info Disclosure',  'icon': 'fas fa-shield-alt'},
        {'id': 3,  'title': 'Supply Chain',                'icon': 'fas fa-shipping-fast'},
        {'id': 4,  'title': 'Data & Model Poisoning',      'icon': 'fas fa-skull'},
        {'id': 5,  'title': 'Improper Output Handling',    'icon': 'fas fa-exclamation-triangle'},
        {'id': 6,  'title': 'Excessive Agency',            'icon': 'fas fa-user-secret'},
        {'id': 7,  'title': 'System Prompt Leakage',       'icon': 'fas fa-file-alt'},
        {'id': 8,  'title': 'Vector & Embedding Weaknesses','icon': 'fas fa-project-diagram'},
        {'id': 9,  'title': 'Misinformation',              'icon': 'fas fa-bullhorn'},
        {'id': 10, 'title': 'Unbounded Consumption',       'icon': 'fas fa-infinity'},
    ]
    return render_template('dashboard.html', risks=risks)


# ── Challenge start / stop ─────────────────────────────────────────

CHALLENGE_MAP = {
    1:  (5001, "challenges/LLM01_Prompt_Injection/app1.py"),
    2:  (5002, "challenges/LLM02_Sensitive_Information_Disclosure/app2.py"),
    3:  (5003, "challenges/LLM03_Supply_Chain/app3.py"),
    4:  (5004, "challenges/LLM04_Data_and_Model_Poisoning/app4.py"),
    5:  (5005, "challenges/LLM05_Improper_Output_Handling/app5.py"),
    6:  (5006, "challenges/LLM06_Excessive_Agency/app6.py"),
    7:  (5007, "challenges/LLM07_System_Prompt_Leakage/app7.py"),
    8:  (5008, "challenges/LLM08_Vector_and_Embedding_Weaknesses/app8.py"),
    9:  (5009, "challenges/LLM09_Misinformation/app9.py"),
    10: (5010, "challenges/LLM10_Unbounded_Consumption/app10.py"),
    11: (5011, "challenges/ADDN01_Indirect_Prompt_Injection/app11.py"),
}

@app.route('/start/<int:challenge_id>')
def start_challenge_route(challenge_id):
    if challenge_id not in CHALLENGE_MAP:
        return "Unknown Challenge ID", 404

    port, app_path = CHALLENGE_MAP[challenge_id]
    client_host = request.host.split(":")[0]

    try:
        start_challenge(port, app_path)
    except RuntimeError as e:
        return f"<h3>Error: {e}</h3><p>Stop the existing service or restart the challenge.</p>", 409

    target_url = f"http://{client_host}:{port}/"
    if wait_until_responsive(target_url):
        return redirect(target_url)
    return f"Challenge {challenge_id} failed to start in time. Check logs.", 500


@app.route('/stop/<int:challenge_id>')
def stop_challenge_route(challenge_id):
    port = 5000 + challenge_id
    if port in running_apps:
        try:
            p = running_apps[port]
            p.terminate()
            p.wait(timeout=5)
        except Exception:
            try:
                running_apps[port].kill()
            except Exception:
                pass
        del running_apps[port]
        return f"Challenge {challenge_id} stopped."
    return f"No running instance for Challenge {challenge_id}."


# ── Ollama status / load / unload / restart ────────────────────────

@app.route('/ollama/status')
def ollama_status():
    try:
        pulled  = requests.get(f"{OLLAMA_BASE}/api/tags", timeout=3).json().get('models', [])
        loaded  = requests.get(f"{OLLAMA_BASE}/api/ps",   timeout=3).json().get('models', [])
        loaded_names = {m['name'] for m in loaded}
        return jsonify({
            'running': True,
            'pulled': [{'name': m['name'], 'size': m.get('size', 0)} for m in pulled],
            'loaded_names': list(loaded_names),
        })
    except Exception:
        return jsonify({'running': False, 'pulled': [], 'loaded_names': []})


@app.route('/ollama/unload/<path:model_name>', methods=['POST'])
def ollama_unload(model_name):
    try:
        requests.post(f"{OLLAMA_BASE}/api/generate",
                      json={"model": model_name, "keep_alive": 0}, timeout=5)
        return jsonify({'success': True})
    except Exception as e:
        return jsonify({'success': False, 'error': str(e)})


@app.route('/ollama/load/<path:model_name>', methods=['POST'])
def ollama_load(model_name):
    try:
        requests.post(f"{OLLAMA_BASE}/api/generate",
                      json={"model": model_name, "keep_alive": -1, "prompt": ""}, timeout=30)
        return jsonify({'success': True})
    except Exception as e:
        return jsonify({'success': False, 'error': str(e)})


@app.route('/ollama/restart', methods=['POST'])
def ollama_restart():
    try:
        result = subprocess.run(
            ["docker", "restart", "ollama"],
            capture_output=True, text=True, timeout=30
        )
        if result.returncode == 0:
            push_activity({'lab': 'System', 'event': 'ollama_restart', 'msg': 'Ollama container restarted'})
            return jsonify({'success': True})
        return jsonify({'success': False, 'error': result.stderr.strip()})
    except Exception as e:
        return jsonify({'success': False, 'error': str(e)})


# ── Pull lite models (SSE streaming) ──────────────────────────────

@app.route('/ollama/pull-stream')
def pull_stream():
    def generate():
        for model in MODELS_LITE:
            yield f"data: {json.dumps({'type': 'start', 'model': model})}\n\n"
            try:
                with requests.post(
                    f"{OLLAMA_BASE}/api/pull",
                    json={"name": model, "stream": True},
                    stream=True, timeout=600
                ) as resp:
                    for line in resp.iter_lines():
                        if line:
                            try:
                                obj = json.loads(line)
                                completed = obj.get("completed", 0)
                                total = obj.get("total", 0)
                                pct = int(completed / total * 100) if total > 0 else None
                                yield f"data: {json.dumps({'type': 'progress', 'model': model, 'status': obj.get('status', ''), 'pct': pct})}\n\n"
                            except Exception:
                                pass
                yield f"data: {json.dumps({'type': 'done', 'model': model})}\n\n"
            except Exception as e:
                yield f"data: {json.dumps({'type': 'error', 'model': model, 'msg': str(e)})}\n\n"
        yield "data: __DONE__\n\n"

    return Response(stream_with_context(generate()),
                    mimetype='text/event-stream',
                    headers={'Cache-Control': 'no-cache', 'X-Accel-Buffering': 'no'})


# ── LLM activity feed ──────────────────────────────────────────────

@app.route('/internal/llm-event', methods=['POST'])
def llm_event():
    """Challenge apps POST here before/after every LLM call."""
    try:
        push_activity(request.get_json(force=True) or {})
    except Exception:
        pass
    return '', 204


@app.route('/events/activity')
def activity_stream():
    """SSE stream — dashboard subscribes here for live LLM events."""
    buf = deque()
    with activity_listeners_lock:
        activity_listeners.append(buf)

    def generate():
        # Send backlog (last 10) on connect
        with activity_lock:
            backlog = list(activity_log)[-10:]
        for ev in backlog:
            yield f"data: {json.dumps(ev)}\n\n"

        while True:
            while buf:
                yield buf.popleft()
            time.sleep(0.5)

    return Response(stream_with_context(generate()),
                    mimetype='text/event-stream',
                    headers={'Cache-Control': 'no-cache', 'X-Accel-Buffering': 'no'})


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=5000, debug=False)
