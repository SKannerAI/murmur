# Murmur

A fully-local, privacy-preserving voice dictation app for macOS (Apple Silicon) — a
[Wispr Flow](https://wisprflow.ai) clone where **nothing leaves your Mac**.

Hold a hotkey, speak, release: Murmur transcribes your speech locally with Whisper,
cleans it up with a local LLM (fillers removed, grammar and punctuation fixed), and
types the result into whatever app you're using.

```
Right ⌥ (hold)                                  push-to-talk hotkey (CGEvent tap)
  + on-screen "Listening…" overlay              floating capsule on the pointer's
                                                screen while the key is held
  → AVAudioEngine, 16 kHz mono PCM              microphone capture
  → WhisperKit (CoreML, Apple Neural Engine)    local speech-to-text, biased
                                                toward your custom vocabulary
  → VocabularyCorrector                         deterministic phonetic/fuzzy
                                                fix-up of names, acronyms, jargon
  → Ollama @ localhost:11434 (qwen2.5:3b)       local LLM cleanup (fillers,
                                                grammar, vocab-aware) — falls back
                                                to raw transcript if Ollama is down
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
- While the key is held, a floating **"Listening…" capsule** (pulsing mic +
  waveform) appears bottom-center of the screen your pointer is on; it shows an
  orange **"Not ready yet…"** state if the model is still loading or a previous
  dictation is mid-pipeline.
- The menu-bar icon shows the pipeline state (recording / transcribing / cleaning).
- The menu-bar popover has settings: Whisper model (tiny.en → large-v3-turbo),
  cleanup on/off, Ollama model/URL, recording overlay on/off, sound feedback —
  plus a **Test insert** button to verify text injection without speaking.

### Custom vocabulary

Open the popover → **Custom vocabulary** and add names, acronyms, and jargon
(one per line or comma-separated), e.g. `OpenFGA`, `Priya`, `Kitcheck`. Each term
is applied at three points in the pipeline:

1. **Recognition** — terms are fed to the Whisper decoder as prompt tokens, so
   transcription itself prefers your spellings.
2. **Deterministic fix-up** — a sliding-window matcher (squashed exact match,
   edit distance, metaphone-lite phonetic key) corrects what Whisper still
   mangles: `open f g a` → `OpenFGA`, `pria` → `Priya`, `kit check` → `Kitcheck`,
   plus canonical casing. Conservative by design — matching thresholds are tuned
   so real words (*kitchen*, *prior*, *spicy*) are never "corrected" into vocab.
3. **Cleanup** — the term list is appended to the Ollama system prompt as a
   glossary of exact spellings.

Terms shorter than 3 characters are skipped by the fuzzy matcher (they would
false-positive on everything) but still reach layers 1 and 3.

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
- Add a tricky term (e.g. `OpenFGA`) to Custom vocabulary, then dictate
  *"schedule a sync about the open F G A migration"* → the exact spelling is
  inserted.
- On a multi-monitor setup, hold Right ⌥ with the pointer on each screen → the
  overlay appears on the pointer's screen.

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
- **Overlay placement on multi-display setups** — `NSScreen.main` follows the key
  window, which a menu-bar app never has, so the overlay targets the screen
  containing the mouse pointer instead (the best proxy for where the focused
  text field is).
- **Vocabulary matching order matters** — exact squashed matches claim their
  tokens before fuzzy matching runs, so a fuzzy multi-word window can't swallow
  a neighboring word ("to openfga" must not become "OpenFGA"). The phonetic key
  collapses only literal doubles *before* dropping vowels, keeping *prior* (PRR)
  distinct from *Priya* (PR).
- **Rebuilds can invalidate the Accessibility grant** — each `./build.sh`
  re-signs ad-hoc with a new signature; if the hotkey goes dead after an update,
  toggle Murmur off/on in System Settings → Privacy & Security → Accessibility
  and relaunch.

## Credits

Architecture informed by the open-source projects
[OpenWhisper](https://github.com/Rajvardhman05/openwhisper-app),
[speak2](https://github.com/zachswift615/speak2),
[Handy](https://github.com/cjpais/Handy), and
[Whispering](https://github.com/EpicenterHQ/epicenter);
STT by [WhisperKit](https://github.com/argmaxinc/WhisperKit) (Argmax);
cleanup via [Ollama](https://ollama.com).

MIT licensed.
