> **AI agents:** read [AGENTS.md](AGENTS.md) first.

# HoldTalk

Free, open-source dictation for your Mac. Hold a key, speak, let go, and the text appears at your cursor.
It runs locally with whisper.cpp, with no accounts and no telemetry.

| Do this | What happens |
| --- | --- |
| Hold `fn` | Records while held, then pastes on release |
| Double-tap `fn` | Records hands-free. One more tap stops and pastes. |
| Press Esc | Cancels the recording or transcription |

## Install

Needs macOS 13 or later.

```bash
git clone https://github.com/tommypurcell/HoldTalk.git
cd HoldTalk
brew install whisper-cpp
scripts/download-model.sh small
scripts/build-app.sh --install
open ~/Applications/HoldTalk.app
```

Then:

1. In **System Settings → Privacy & Security**, allow HoldTalk under **Microphone**, **Input Monitoring** and **Accessibility**.
2. In **System Settings → Keyboard**, set **Press 🌐 key to** **Do Nothing**.

## Optional: clean up the text

Add a Groq, Anthropic or OpenAI key to remove filler words and fix punctuation. Without one, you get the raw transcript.

```bash
cp .env.example ~/.config/holdtalk/.env
chmod 600 ~/.config/holdtalk/.env
```

With a key, your text is sent to that provider. Your audio stays on your Mac unless you choose a cloud transcriber.

## More

- [Guide](docs/guide.md): settings, changing the hotkey, privacy and troubleshooting
- [Contributing](CONTRIBUTING.md)

## Credits

Built with Claude Code from the Wispr Flow prompt on [Can I Vibecode It?](https://canivibecodeit.com/wispr-flow).
Transcription runs on [whisper.cpp](https://github.com/ggml-org/whisper.cpp) and OpenAI's Whisper models.

## License

[MIT](LICENSE)
