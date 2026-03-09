from flask import Flask, render_template, redirect, request, jsonify, Response, stream_with_context
import subprocess, sys, os, requests, psutil, time, socket

app = Flask(__name__)

running_apps = {}
lite_mode = False

MODELS_FULL = ['mistral', 'llama3', 'sqlcoder', 'granite3-guardian', 'granite3.1-moe:1b']
MODELS_LITE = ['phi3:mini', 'granite3.1-moe:1b']
MODELS_ALL  = list(set(MODELS_FULL + MODELS_LITE))

OLLAMA_BASE = "http://localhost:11434"


def get_model_env():
    if lite_mode:
        return {
            'PROMPTME_CHAT_MODEL':     'phi3:mini',
            'PROMPTME_CHAT_MODEL_2':   '',
            'PROMPTME_SQL_MODEL':      'phi3:mini',
            'PROMPTME_GUARDIAN_MODEL': 'granite3.1-moe:1b',
            'PROMPTME_EMBED_MODEL':    'granite3.1-moe:1b',
        }
    return {
        'PROMPTME_CHAT_MODEL':     'mistral',
        'PROMPTME_CHAT_MODEL_2':   'llama3',
        'PROMPTME_SQL_MODEL':      'sqlcoder',
        'PROMPTME_GUARDIAN_MODEL': 'granite3-guardian',
        'PROMPTME_EMBED_MODEL':    'granite3.1-moe:1b',
    }


def is_port_in_use(port):
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as sock:
        return sock.connect_ex(('localhost', port)) == 0

def start_challenge(port, app_path):
    global running_apps

    if is_port_in_use(port):
        raise RuntimeError(f"Port {port} is already in use. Challenge cannot be started.")

    log_file = f"logs/challenge_{port}.log"
    os.makedirs("logs", exist_ok=True)

    env = os.environ.copy()
    env.update(get_model_env())

    with open(log_file, "w") as log:
        process = subprocess.Popen(
            [sys.executable, app_path],
            stdout=log,
            stderr=log,
            close_fds=True,
            env=env
        )

    running_apps[port] = process


@app.route('/')
def dashboard():
    risks = [
        { 'id': 1, 'title': 'Prompt Injection', 'icon': 'fas fa-code' },
        { 'id': 2, 'title': 'Sensitive Info Disclosure', 'icon': 'fas fa-shield-alt' },
        { 'id': 3, 'title': 'Supply Chain', 'icon': 'fas fa-shipping-fast' },
        { 'id': 4, 'title': 'Data & Model Poisoning', 'icon': 'fas fa-skull' },
        { 'id': 5, 'title': 'Improper Output Handling', 'icon': 'fas fa-exclamation-triangle' },
        { 'id': 6, 'title': 'Excessive Agency', 'icon': 'fas fa-user-secret' },
        { 'id': 7, 'title': 'System Prompt Leakage', 'icon': 'fas fa-file-alt' },
        { 'id': 8, 'title': 'Vector & Embedding Weaknesses', 'icon': 'fas fa-project-diagram' },
        { 'id': 9, 'title': 'Misinformation', 'icon': 'fas fa-bullhorn' },
        { 'id': 10, 'title': 'Unbounded Consumption', 'icon': 'fas fa-infinity' }
    ]
    return render_template('dashboard.html', risks=risks, lite_mode=lite_mode)


def wait_until_responsive(url, timeout=30):
    start_time = time.time()
    while time.time() - start_time < timeout:
        try:
            response = requests.get(url, timeout=2)
            if response.status_code == 200:
                return True
        except requests.exceptions.RequestException:
            pass
        time.sleep(1)
    return False


@app.route('/start/<int:challenge_id>')
def start_challenge_route(challenge_id):
    client_host = request.host.split(":")[0]
    challenge_map = {
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
    }
    if challenge_id not in challenge_map:
        return "Unknown Challenge ID", 404

    port, app_path = challenge_map[challenge_id]

    try:
        start_challenge(port, app_path)
    except RuntimeError as e:
        return f"<h3>Error: {str(e)}</h3><p>Please stop the existing service manually or choose a different port.</p>", 409

    target_url = f"http://{client_host}:{port}/"
    if wait_until_responsive(target_url):
        return redirect(f"http://{client_host}:{port}/")
    else:
        return f"Challenge {challenge_id} failed to start in time. Check logs.", 500


@app.route('/stop/<int:challenge_id>')
def stop_challenge_route(challenge_id):
    global running_apps
    port = 5000 + challenge_id
    if port in running_apps:
        try:
            process = running_apps[port]
            process.terminate()
            process.wait(timeout=5)
        except (psutil.NoSuchProcess, psutil.TimeoutExpired, ProcessLookupError):
            process.kill()
        del running_apps[port]
        return f"Challenge {challenge_id} stopped."
    return f"No running instance for Challenge {challenge_id}."


# ── Mode toggle ───────────────────────────────────────────────────────────────

@app.route('/mode', methods=['GET'])
def get_mode():
    return jsonify({'lite': lite_mode})

@app.route('/mode/toggle', methods=['POST'])
def toggle_mode():
    global lite_mode
    lite_mode = not lite_mode
    return jsonify({'lite': lite_mode})


# ── Ollama status / load / unload ─────────────────────────────────────────────

@app.route('/ollama/status')
def ollama_status():
    try:
        tags_resp = requests.get(f"{OLLAMA_BASE}/api/tags", timeout=3)
        pulled = tags_resp.json().get('models', [])
        ps_resp = requests.get(f"{OLLAMA_BASE}/api/ps", timeout=3)
        loaded = ps_resp.json().get('models', [])
        loaded_names = {m['name'] for m in loaded}
        return jsonify({
            'running': True,
            'pulled': [{'name': m['name'], 'size': m.get('size', 0)} for m in pulled],
            'loaded_names': list(loaded_names)
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


# ── Pull models (SSE streaming) ───────────────────────────────────────────────

@app.route('/ollama/pull-stream')
def pull_stream():
    mode = request.args.get('mode', 'current')
    if mode == 'lite':
        models = MODELS_LITE
    elif mode == 'full':
        models = MODELS_FULL
    else:
        models = MODELS_LITE if lite_mode else MODELS_FULL

    def generate():
        for model in models:
            yield f"data: Pulling {model}...\n\n"
            try:
                with requests.post(
                    f"{OLLAMA_BASE}/api/pull",
                    json={"name": model, "stream": True},
                    stream=True, timeout=600
                ) as resp:
                    for line in resp.iter_lines():
                        if line:
                            import json as _json
                            try:
                                obj = _json.loads(line)
                                status = obj.get("status", "")
                                if status:
                                    yield f"data: {status}\n\n"
                            except Exception:
                                pass
                yield f"data: [{model}] done\n\n"
            except Exception as e:
                yield f"data: [{model}] error: {e}\n\n"
        yield "data: __DONE__\n\n"

    return Response(stream_with_context(generate()),
                    mimetype='text/event-stream',
                    headers={'Cache-Control': 'no-cache', 'X-Accel-Buffering': 'no'})


# ── Remove all PromptMe models ────────────────────────────────────────────────

@app.route('/ollama/remove-all', methods=['POST'])
def remove_all_models():
    results = {}
    for model in MODELS_ALL:
        try:
            resp = requests.delete(f"{OLLAMA_BASE}/api/delete",
                                   json={"name": model}, timeout=10)
            results[model] = "removed" if resp.status_code in (200, 404) else f"error {resp.status_code}"
        except Exception as e:
            results[model] = f"error: {e}"
    return jsonify(results)


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=5000, debug=False)
