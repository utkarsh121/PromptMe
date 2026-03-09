# AI Security Lab — OWASP LLM Top 10 CTF

<p>
<img src="https://github.com/R3dShad0w7/PromptMe/blob/main/static/logo.png?raw=true" width="600" alt="Thumbnail"/>
</p>

### An intentionally vulnerable application designed to demonstrate the OWASP Top 10 for Large Language Model (LLM) Applications.

AI Security Lab is an educational project that showcases security vulnerabilities in large language models (LLMs) and their web integrations. It includes 10 hands-on challenges inspired by the OWASP LLM Top 10, demonstrating how these vulnerabilities can be discovered and exploited in real-world scenarios.

This project is intended for AI Security professionals to explore potential security risks in LLMs and learn effective mitigation strategies.

## Overview (No API Key required)

The project is primarily developed using Python and the Ollama framework with open-source LLM models. The exercises are structured as **CTF (Capture The Flag) challenges**, each with a clear objective, optional hints, and a flag awarded upon successful completion.

The dashboard supports two modes to accommodate different hardware:

| Mode | Models used | Minimum RAM |
|------|------------|-------------|
| **Full** | mistral, llama3, sqlcoder, granite3-guardian, granite3.1-moe:1b | 16 GB |
| **Lite** | phi3:mini, granite3.1-moe:1b | 8 GB |

---

## Getting Started

### Prerequisites

* Python 3.10 or higher
* pip (Python package installer)
* [Ollama](https://ollama.com/download) installed and running

### Setup

#### 1. Clone the repository
```bash
git clone https://github.com/utkarsh121/PromptMe.git
cd PromptMe
```

#### 2. Install dependencies
```bash
pip install -r requirements.txt
```

#### 3. Start Ollama
```bash
ollama serve   # run in a separate terminal
```

#### 4. Pull models

**Option A — Use the dashboard (recommended)**
Start the app (`python main.py`), open http://127.0.0.1:5000, select your mode with the **Lite/Full toggle** (top-left), then click **Pull Models**. Progress streams live in the browser.

**Option B — Manual pull**

Full mode:
```bash
ollama pull mistral
ollama pull llama3
ollama pull sqlcoder
ollama pull granite3-guardian
ollama pull granite3.1-moe:1b
```

Lite mode (8 GB RAM VMs):
```bash
ollama pull phi3:mini
ollama pull granite3.1-moe:1b
```

Or via Docker:
```bash
docker run -d --name ollama_server -p 11434:11434 ollama/ollama:latest
docker exec -it ollama_server ollama pull phi3:mini
```

#### 5. Start the application
```bash
python main.py
```
Open http://127.0.0.1:5000

#### 6. Launch a challenge
Click the **Start** button on any challenge tile. Each challenge runs as an isolated Flask app on its own port (5001–5010).

---

## Dashboard Features

| Feature | Location | Description |
|---------|----------|-------------|
| **Lite / Full toggle** | Top-left | Switch between lightweight and full model sets. Affects new challenge launches; running challenges need restart. |
| **Pull Models** | Top-left | Pulls models for the current mode with live progress |
| **Remove Models** | Top-left | Removes all lab models from Ollama to free disk space |
| **Ollama status** | Top-right | Shows which models are pulled and loaded in RAM, with Load/Unload toggles |

---

## Challenges

| # | Challenge | Port | OWASP Category |
|---|-----------|------|---------------|
| 1 | Prompt Injection | 5001 | LLM01 |
| 2 | Sensitive Information Disclosure | 5002 | LLM02 |
| 3 | Supply Chain | 5003 | LLM03 |
| 4 | Data & Model Poisoning | 5004 | LLM04 |
| 5 | Improper Output Handling | 5005 | LLM05 |
| 6 | Excessive Agency | 5006 | LLM06 |
| 7 | System Prompt Leakage | 5007 | LLM07 |
| 8 | Vector & Embedding Weaknesses | 5008 | LLM08 |
| 9 | Misinformation | 5009 | LLM09 |
| 10 | Unbounded Consumption | 5010 | LLM10 |

---

## Compatibility

Supports macOS and Linux. Windows compatibility is in progress.

> **Note for LLM10 (Unbounded Consumption) in Lite mode:** `phi3:mini` generates responses faster than `mistral`. If the 90-second time threshold is hard to trigger, craft a more elaborate prompt to force a longer response.

---

## Solutions

[Solutions](https://github.com/utkarsh121/PromptMe/tree/main/solutions) are provided for beginners. Each solution explains the vulnerability, the attack steps, and the underlying vulnerable code.

---

## Disclaimer

AI Security Lab is an intentionally vulnerable application created for educational purposes. The application uses insecure code and packages to demonstrate real-world risks. **Run it in a virtual or sandboxed environment only.**

The vulnerabilities shown are for learning purposes and must never be implemented in production systems.

---

## Contributing

Contributions are welcome! To contribute:

1. Fork the repository
2. Create a new branch (`git checkout -b feature-name`)
3. Make your changes and commit them
4. Push to your fork and open a Pull Request

---

## Connect

Questions, issues, or suggestions? Reach out on [Discord](https://discord.gg/hB8Prk3w).

---

## License

MIT License — see [LICENSE](LICENSE) for details.

## Authors

[Divyesh](https://github.com/divyesh-0x01), [Srithesh](https://github.com/0xbughunter), [Praveen](https://github.com/praveen-kv), [Ranjit](https://www.linkedin.com/in/ranjit-singh-a788b579/), [Sumanth](https://github.com/SumanthGowda)
