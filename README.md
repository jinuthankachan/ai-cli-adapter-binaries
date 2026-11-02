# AI CLI Adapter

Use your **Claude Code**, **OpenAI Codex** and **Google Antigravity** subscriptions from any app that talks to the Anthropic, OpenAI or Gemini API.

AI CLI Adapter is a small local HTTP server. It looks like the Anthropic, OpenAI and Gemini APIs, and it answers every request by running a coding-agent CLI that is already installed and logged in on your machine. Point an SDK, IDE plugin, chat UI, LangChain, LiteLLM or plain `curl` at `http://127.0.0.1:8787`, and the request runs through `claude`, `codex` or `agy`, without a separate API key or API billing.

This repository hosts the prebuilt binaries and the installer. Releases are on the [Releases page](https://github.com/jinuthankachan/ai-cli-adapter-binaries/releases).

## Features

* **Three API styles in one server**
  * OpenAI Chat Completions: `POST /v1/chat/completions`, `GET /v1/models`
  * Anthropic Messages: `POST /v1/messages`, `POST /v1/messages/count_tokens`
  * Gemini: `generateContent`, `streamGenerateContent`, `countTokens`, `GET /v1beta/models` (also under `/v1/` and `/v1alpha/`)
* **Three backends**: Claude Code (`claude`), OpenAI Codex CLI (`codex`), Google Antigravity CLI (`agy`). Any API style can reach any backend, for example the OpenAI SDK answered by Claude Code.
* **Streaming** (SSE) in all three styles, with keep-alives while the CLI starts.
* **Model routing**: pick a backend with a prefix (`claude:opus`, `codex:gpt-5.5`), aliases, per-backend model lists or regex rules.
* **Reasoning controls**: `reasoning_effort`, Anthropic `thinking`, Gemini `thinkingConfig` map to each CLI's effort setting. Reasoning text can optionally be returned to the client.
* **Stop sequences** that work with every backend, and token usage reported in each protocol's format.
* **Web dashboard** at `/`:
  * CLI paths, login checks and a test ping per backend
  * routing rules and aliases
  * request log
  * an **API compatibility** tab listing which upstream API fields are supported
* **Optional agent mode** per backend: let the CLI use its own tools inside a working directory you choose.
* **Optional API key** to protect the server when exposed beyond localhost.
* **Single native binary**: about 5 MB, about 8 MB of memory when idle, no runtime to install.

## Supported platforms

| OS | CPU | Release file |
|---|---|---|
| Linux (any distro, static binary) | x86_64 | `ai-cli-adapter-<version>-x86_64-unknown-linux-musl.tar.gz` |
| Linux (any distro, static binary) | arm64 / aarch64 | `ai-cli-adapter-<version>-aarch64-unknown-linux-musl.tar.gz` |
| macOS | Apple Silicon | `ai-cli-adapter-<version>-aarch64-apple-darwin.tar.gz` |
| macOS | Intel | `ai-cli-adapter-<version>-x86_64-apple-darwin.tar.gz` |

Windows is not supported.

## Requirements

At least one of these CLIs installed **and logged in**:

| Backend | Install and log in | Check |
|---|---|---|
| Claude Code | install per the [docs](https://docs.anthropic.com/en/docs/claude-code), then run `claude` once | `claude auth status` |
| OpenAI Codex CLI | `npm i -g @openai/codex`, then `codex login` | `codex login status` |
| Google Antigravity CLI | install [`agy`](https://antigravity.google/), then run `agy` once to sign in | `agy models` |

## Install

```bash
curl -fsSL https://raw.githubusercontent.com/jinuthankachan/ai-cli-adapter-binaries/main/install.sh | sh
```

The script picks the build for your OS and CPU, downloads the latest release, checks it against `SHA256SUMS`, and installs `ai-cli-adapter` into `~/.local/bin`. It needs `curl` and `tar`, and no root access.

To install **and** start it in the background at every login (systemd user service on Linux, launchd agent on macOS):

```bash
curl -fsSL https://raw.githubusercontent.com/jinuthankachan/ai-cli-adapter-binaries/main/install.sh | sh -s -- --service
```

Installer options (pass them after `sh -s --`):

| Option | Meaning |
|---|---|
| `--version v0.2.0` | install a specific release instead of the latest |
| `--dir /path/to/bin` | install somewhere other than `~/.local/bin` |
| `--service` | also run it in the background at login |
| `--uninstall` | remove the binary and the background service |
| `--purge` | with `--uninstall`: also delete settings and logs in `~/.ai-cli-adapter` |

To install system-wide, run `curl -fsSL …/install.sh | sudo sh -s -- --dir /usr/local/bin`. Don't combine `sudo` with `--service`, because the service would then be set up for root instead of for you.

If the script warns that `~/.local/bin` is not on your `PATH`, add `export PATH="$HOME/.local/bin:$PATH"` to your `~/.bashrc` or `~/.zshrc`.

### Manual install

1. Download the file for your platform and `SHA256SUMS` from the [latest release](https://github.com/jinuthankachan/ai-cli-adapter-binaries/releases/latest).
2. Verify and unpack:
   ```bash
   sha256sum -c SHA256SUMS --ignore-missing      # macOS: shasum -a 256 -c SHA256SUMS --ignore-missing
   tar -xzf ai-cli-adapter-*.tar.gz
   mkdir -p ~/.local/bin && mv ai-cli-adapter ~/.local/bin/
   ```
3. **macOS only:** the binary is not signed by Apple, so a file downloaded with a browser is blocked the first time you run it. Clear the download flag once:
   ```bash
   xattr -d com.apple.quarantine ~/.local/bin/ai-cli-adapter
   ```
   (The install script downloads with `curl`, which does not set this flag.)

## Quick start

```bash
ai-cli-adapter                       # serves http://127.0.0.1:8787
ai-cli-adapter --port 9000           # other port
ai-cli-adapter --version             # installed version
ai-cli-adapter --help                # all options
```

Open <http://127.0.0.1:8787/>. The dashboard checks every backend on load (executable found, version, login). Press **Ping** on a backend card to run a real prompt through it.

```bash
# OpenAI style, answered by Codex
curl http://127.0.0.1:8787/v1/chat/completions -H 'content-type: application/json' \
  -d '{"model":"codex-default","messages":[{"role":"user","content":"Say hi"}]}'

# Anthropic style, answered by Claude Code
curl http://127.0.0.1:8787/v1/messages -H 'content-type: application/json' -H 'anthropic-version: 2023-06-01' \
  -d '{"model":"claude-default","max_tokens":1024,"messages":[{"role":"user","content":"Say hi"}]}'

# Gemini style, streaming, answered by Antigravity
curl 'http://127.0.0.1:8787/v1beta/models/agy-default:streamGenerateContent?alt=sse' -H 'content-type: application/json' \
  -d '{"contents":[{"role":"user","parts":[{"text":"Say hi"}]}]}'
```

With the official SDKs, set the base URL and use any API key; the key is ignored unless you set one in the dashboard:

```python
from openai import OpenAI
OpenAI(base_url="http://127.0.0.1:8787/v1", api_key="unused") \
    .chat.completions.create(model="codex-default", messages=[{"role": "user", "content": "hi"}])

from anthropic import Anthropic
Anthropic(base_url="http://127.0.0.1:8787", api_key="unused") \
    .messages.create(model="claude-default", max_tokens=1024, messages=[{"role": "user", "content": "hi"}])

from google import genai
genai.Client(api_key="unused", http_options={"base_url": "http://127.0.0.1:8787"}) \
    .models.generate_content(model="agy-default", contents="hi")
```

Expect 3 to 15 seconds before the first token. Each request starts a fresh CLI process, and the CLIs take a few seconds to boot.

## Choosing a backend and model

The `model` field decides which CLI runs, checked in this order:

1. **Prefix**: `claude:opus`, `codex:gpt-5.5`, `agy:gemini-3.8-flash-high`. The part after the colon is passed to the CLI; `codex:` alone means the CLI's default model.
2. **Aliases** set in the dashboard, for example `gpt-4o` → `codex:gpt-5.5`.
3. **Model lists**: a name in a backend's model list goes to that backend. **Fetch models** in the dashboard fills the list from the CLI.
4. **Routing rules** (regular expressions). By default `claude…`/`anthropic…` go to Claude Code, `gpt…`/`o1…`/`codex…` to Codex, and `gemini…`/`agy…` to Antigravity.
5. **Default backend** (Claude Code unless changed).

`claude-default`, `codex-default` and `agy-default` always work and mean "the CLI's own default model".

## Configuration

Settings are in `~/.ai-cli-adapter/config.json`, created on first start. The dashboard edits the same file, and changes apply immediately except host and port, which need a restart.

| Setting | Default | Meaning |
|---|---|---|
| `server.host` / `server.port` | `127.0.0.1` / `8787` | bind address |
| `server.apiKey` | empty | require this key on API calls (`Authorization: Bearer`, `x-api-key`, `x-goog-api-key` or `?key=`) |
| `server.maxConcurrent` | `4` | CLI processes at once; further requests queue |
| `server.requestTimeoutMs` | `600000` | stop the CLI and answer 504 after this long |
| `server.exposeReasoning` | `false` | include thinking text in responses |
| `backends.<id>.enabled` | `true` | turn a backend off |
| `backends.<id>.path` | `claude` / `codex` / `agy` | executable name or absolute path |
| `backends.<id>.allowTools` | `false` | agent mode: the CLI may use its tools in the backend's working directory |

Command-line flags `--host`, `--port` and `--config PATH` override the file for one run. Set `AI_CLI_ADAPTER_HOME` to move the whole `~/.ai-cli-adapter` directory, or `AI_CLI_ADAPTER_DEBUG=1` to log every CLI command and its raw output.

## Not supported

* Function calling / tool definitions sent by the client are ignored; the CLIs do their own tool use.
* Images, audio and files in messages are dropped.
* `temperature`, `top_p`, `n > 1`, JSON mode / `response_format` and logprobs are ignored.
* The OpenAI Responses API and the legacy `/v1/completions` endpoint.

The dashboard's **API compatibility** tab has the full list, field by field.

## Running in the background

`--service` in the installer sets this up. To manage the service afterwards:

| | Linux (systemd) | macOS (launchd) |
|---|---|---|
| Status | `systemctl --user status ai-cli-adapter` | `launchctl print gui/$(id -u)/io.github.jinuthankachan.ai-cli-adapter` |
| Logs | `journalctl --user -u ai-cli-adapter -f` | `tail -f ~/Library/Logs/ai-cli-adapter.log` |
| Restart | `systemctl --user restart ai-cli-adapter` | `launchctl kickstart -k gui/$(id -u)/io.github.jinuthankachan.ai-cli-adapter` |

The service keeps the `PATH` from when you installed it, so it finds the CLIs. If you install a CLI somewhere new later, rerun the installer with `--service`. On Linux, run `loginctl enable-linger $USER` to keep the service running while you are logged out.

## Upgrade

Run the install command again. It replaces the binary and restarts the background service if one is installed. Your settings in `~/.ai-cli-adapter` are kept. Check the result with `ai-cli-adapter --version`.

## Uninstall

```bash
# remove the binary and the background service, keep settings
curl -fsSL https://raw.githubusercontent.com/jinuthankachan/ai-cli-adapter-binaries/main/install.sh | sh -s -- --uninstall

# also delete settings, API key, request log and working directories
curl -fsSL https://raw.githubusercontent.com/jinuthankachan/ai-cli-adapter-binaries/main/install.sh | sh -s -- --uninstall --purge
```

Add `--dir /path/to/bin` if you installed somewhere other than `~/.local/bin`.

To uninstall by hand, stop the service if you set one up, then delete:

* the binary: `~/.local/bin/ai-cli-adapter`
* the Linux service: `~/.config/systemd/user/ai-cli-adapter.service`
* the macOS service: `~/Library/LaunchAgents/io.github.jinuthankachan.ai-cli-adapter.plist`
* optionally your settings: `~/.ai-cli-adapter`

## Security

* By default the server listens on `127.0.0.1` only. **Before binding to another address (`--host 0.0.0.0`), set an API key in the dashboard.** Without one, anyone who can reach the port can run prompts on your subscriptions and change which executables the server runs, which amounts to running commands as you.
* The dashboard API accepts requests from localhost without a key, and from anywhere else only with the key.
* The config file is written readable by you only (`0600`).
* With **agent mode** on, the CLI can edit files in the backend's working directory. Leave it off unless you need it.

## Troubleshooting

* **A CLI shows as missing in the dashboard**: it is not on the `PATH` the server was started with. Put the absolute path (from `which claude`) in the backend's "Executable path" field.
* **Codex: `The '<model>' model is not supported when using Codex with a ChatGPT account`**: use `codex-default` or a model your plan includes.
* **agy: `agy produced no text because it tried to use tools`**: the model wanted to run a command. Rephrase, or turn on **Allow tools** for agy.
* **504 timeouts**: raise `server.requestTimeoutMs` for long agent runs.
* **Port already in use**: start with `--port 9000`, or change the port in the dashboard and restart.
* **macOS says the binary "cannot be opened"**: see the `xattr` step under [Manual install](#manual-install).

Report problems in this repository's [issues](https://github.com/jinuthankachan/ai-cli-adapter-binaries/issues).

## License

[MIT](LICENSE)
