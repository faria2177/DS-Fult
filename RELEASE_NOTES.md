## DocScanner v0.5.54

- 🔧 Edit Text / text recognition: fixed the release-build error "Attempt to invoke virtual method 'java.lang.Class java.lang.Object.getClass()'…" — the app shrinker was removing parts of Google ML Kit
- 🩺 AI Mode → **Check APIs**: tests every saved API key and model and shows which ones work (only a short test message is sent)
- 🔀 AI Mode → **Auto-switch if an API fails** (on by default): if one model or provider fails, the next model and then your other saved providers are tried automatically
- 📚 AI Mode → **Models**: add as many models as you like for OpenRouter, Groq or Gemini; OpenRouter has **Browse free models** to pick from its current free list
- ➕ New provider: **DeepAI** (text generator API)
