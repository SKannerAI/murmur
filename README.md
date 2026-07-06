# Murmur

A fully-local, privacy-preserving voice dictation app for macOS (Apple Silicon) — a
[Wispr Flow](https://wisprflow.ai) clone where **nothing leaves your Mac**.

Hold a hotkey, speak, release: Murmur transcribes your speech locally with Whisper,
cleans it up with a local LLM (fillers removed, grammar and punctuation fixed), and
types the result into whatever app you're using.

```
Right ⌥ (hold)                                  push-to-talk hotkey (CGEvent tap)
  → AVAudioEngine, 16 kHz mono PCM              microphone capture
  → WhisperKit (CoreML, Apple Neural Engine)    local speech-to-text
  → Ollama @ localhost:11434 (qwen2.5:3b)       local LLM cleanup — falls back to
                                                raw transcript if Ollama is down
  → NSPasteboard + synthetic Cmd+V              insert into the frontmost app,
                                                original clipboard restored
```

Wispr Flow runs this same two-stage pipeline (ASR → Llama-based transcript
enhancement) on cloud GPUs; Murmur re-implements it entirely on-device.

## Requirements

- Apple Silicon Mac (M1 or later), macOS 14+
- Xcode Command Line Tools (`xcode-select --install`) — full Xcode not required
- [Ollama](https://ollama.com) for the cleanup step (optional — without it you get
  raw Whisper transcripts)

## Setup

```bash
# 1. LLM cleanup backend (optional but recommended)
brew install ollama
ollama pull qwen2.5:3b
ollama serve   # or launch the Ollama app; it listens on localhost:11434

# 2. Build (first build fetches WhisperKit and takes a few minutes)
./build.sh

# 3. Run
open build/Murmur.app
```

On first launch:

1. Grant **Microphone** when prompted.
2. Grant **Accessibility** (System Settings → Privacy & Security → Accessibility) —
   required for the global hotkey and the synthetic paste. Relaunch Murmur after
   granting.
3. The selected Whisper model downloads once from HuggingFace and is cached; after
   that transcription is fully offline.

## Usage

- **Hold Right Option (⌥)** and speak; release to transcribe, clean, and insert.
- The menu-bar icon shows the pipeline state (recording / transcribing / cleaning).
- The menu-bar popover has settings: Whisper model (tiny.en → large-v3-turbo),
  cleanup on/off, Ollama model/URL, sound feedback — plus a **Test insert** button
  to verify text injection without speaking.

### Choosing models

| Component | Default | Notes |
|---|---|---|
| STT | `base.en` (~140 MB) | Fastest useful quality. Try `large-v3-turbo` (~950 MB) for best accuracy — still ~1s-class on M-series via the Neural Engine. |
| Cleanup | `qwen2.5:3b` (~1.9 GB) | Good speed/quality for the (easy) cleanup task. Also try `llama3.2:3b`, `gemma2:2b`, `phi3.5`. |

## Verification checklist

- Dictate into TextEdit, Notes, a browser field, **and a terminal/editor like
  VS Code or Zed** — the CGEvent-tap hotkey works even in self-drawn apps where
  Carbon hotkeys silently fail.
- Dictate *"um so like the the meeting is at uh three pm"* → with cleanup on, you
  should get *"The meeting is at 3 PM."*
- Quit Ollama and dictate again → the raw transcript is inserted (graceful
  fallback), no hang, no error.
- Check your clipboard after a dictation → your previous clipboard contents are
  restored.

## Design notes & gotchas

- **CGEvent tap, not Carbon `RegisterEventHotKey`** — Carbon hotkeys only fire if
  the frontmost app declines the key, so they never fire inside GPU-drawn apps.
- **Cleanup can never lose a dictation** — any Ollama failure (down, timeout,
  empty/suspicious output, refusal-looking text) falls back to the raw transcript.
- **Paste, don't type** — pasteboard + Cmd+V is far faster and more reliable than
  synthesizing per-character key events; the original clipboard is restored ~0.5s
  later. Secure input fields (passwords) may block synthetic paste by design.
- Whisper's bracketed noise annotations (`[BLANK_AUDIO]` etc.) are stripped before
  cleanup/insert; recordings under 0.5s are ignored as accidental hotkey taps.

## Credits

Architecture informed by the open-source projects
[OpenWhisper](https://github.com/Rajvardhman05/openwhisper-app),
[speak2](https://github.com/zachswift615/speak2),
[Handy](https://github.com/cjpais/Handy), and
[Whispering](https://github.com/EpicenterHQ/epicenter);
STT by [WhisperKit](https://github.com/argmaxinc/WhisperKit) (Argmax);
cleanup via [Ollama](https://ollama.com).

MIT licensed.
