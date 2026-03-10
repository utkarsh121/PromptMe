// Pre-lab cleanup: kill any orphan exfil process and restart secret-service fresh
async function preLabCleanup() {
  const statusEl = document.getElementById('cleanup-status');
  statusEl.className = 'cleanup-status';
  statusEl.innerText = 'Running cleanup…';
  try {
    const res = await fetch('/prelab-cleanup', { method: 'POST' });
    const data = await res.json();
    statusEl.className = 'cleanup-status ok';
    statusEl.innerText = '✓ ' + data.message;
    setTimeout(pollExfil, 1500);
    setTimeout(pollFlag,  1500);
  } catch (err) {
    statusEl.className = 'cleanup-status fail';
    statusEl.innerText = '✗ Cleanup failed — ' + err;
  }
}

// ── Live monitors ────────────────────────────────────────────────────────────

function startMonitors() {
  pollExfil();
  pollFlag();
  setInterval(pollExfil, 3000);
  setInterval(pollFlag,  5000);
}

async function pollExfil() {
  const out = document.getElementById('exfil-output');
  const dot = document.getElementById('exfil-dot');
  try {
    const res = await fetch('/monitor/exfil');
    const data = await res.json();
    if (data.length === 0) {
      out.className = 'monitor-output';
      out.innerText = '[ ] Empty — no data captured yet';
      dot.className = 'dot dot-empty';
    } else {
      out.className = 'monitor-output has-data';
      out.innerText = JSON.stringify(data, null, 2);
      dot.className = 'dot dot-live';
    }
  } catch (e) {
    out.className = 'monitor-output';
    out.innerText = '✗ Exfil server not reachable (run Pre-lab Cleanup)';
    dot.className = 'dot dot-error';
  }
}

async function pollFlag() {
  const out = document.getElementById('flag-output');
  const dot = document.getElementById('flag-dot');

  // Only reveal flag once exfil has captured something
  try {
    const exfilRes = await fetch('/monitor/exfil');
    const exfilData = await exfilRes.json();
    if (!Array.isArray(exfilData) || exfilData.length === 0) {
      out.className = 'monitor-output';
      out.innerText = '🔒 Locked — exfil data must be captured first';
      dot.className = 'dot dot-idle';
      return;
    }
  } catch (e) {
    out.className = 'monitor-output';
    out.innerText = '✗ Flag server not reachable (run Pre-lab Cleanup)';
    dot.className = 'dot dot-error';
    return;
  }

  try {
    const res = await fetch('/monitor/flag');
    const data = await res.json();
    out.className = 'monitor-output flag-found';
    out.innerText = JSON.stringify(data, null, 2);
    dot.className = 'dot dot-live';
  } catch (e) {
    out.className = 'monitor-output';
    out.innerText = '✗ Flag server not reachable (run Pre-lab Cleanup)';
    dot.className = 'dot dot-error';
  }
}

// ── Startup ───────────────────────────────────────────────────────────────────

// Dynamically populate the model dropdown on page load
window.onload = async () => {
  try {
    const res = await fetch("/models");
    const data = await res.json();
    const select = document.getElementById("model-select");

    data.models.forEach(model => {
      const opt = document.createElement("option");
      opt.value = model;
      opt.innerText = model;
      select.appendChild(opt);
    });
  } catch (error) {
    alert("Failed to load models.");
  }
  startMonitors();
};

// Initialize the selected model and show chat UI
async function initModel() {
  const model = document.getElementById("model-select").value;
  if (!model) {
    alert("Please select a model.");
    return;
  }

  const loadingEl = document.getElementById("loading");
  loadingEl.style.display = "block";

  try {
    const res = await fetch("/init_model", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ model })
    });

    loadingEl.style.display = "none";

    if (res.ok) {
      document.getElementById("chat-window").style.display = "block";
      document.getElementById("messages").innerHTML = "";
    } else {
      alert("Failed to initialize model.");
    }
  } catch (err) {
    loadingEl.style.display = "none";
    alert("An error occurred while initializing the model.");
  }
}

// Handle sending a message and receiving a response
async function sendMessage() {
  const promptInput = document.getElementById("prompt");
  const prompt = promptInput.value.trim();
  if (!prompt) return;

  // Show user message
  appendMessage("You", prompt, "msg-user");
  promptInput.value = "";
  promptInput.disabled = true;

  // Temporary bot response placeholder
  const loadingMsg = document.createElement("div");
  loadingMsg.className = "msg-bot";
  loadingMsg.innerText = "Bot: Thinking...";
  document.getElementById("messages").appendChild(loadingMsg);

  try {
    const res = await fetch("/chat", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ prompt })
    });

    const data = await res.json();
    loadingMsg.innerText = `Bot: ${data.response}`;
  } catch (err) {
    loadingMsg.innerText = "Bot: Error getting response.";
    loadingMsg.style.color = "red";
  }

  promptInput.disabled = false;
  promptInput.focus();

  // Scroll to bottom
  const msgBox = document.getElementById("messages");
  msgBox.scrollTop = msgBox.scrollHeight;
}

// Append a message to the chat window
function appendMessage(sender, text, className) {
  const msgDiv = document.createElement("div");
  msgDiv.className = className;
  msgDiv.innerText = `${sender}: ${text}`;
  document.getElementById("messages").appendChild(msgDiv);
}
