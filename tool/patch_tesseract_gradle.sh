#!/usr/bin/env bash
set -euo pipefail

# New Flutter/pub versions may put a hosted plugin under a different cache
# layout. Resolve the actual installed package via package_config.json rather
# than assuming ~/.pub-cache/hosted/pub.dev/<name>-<version>/.
plugin_root="$(python3 - <<'PY'
import json
from pathlib import Path
from urllib.parse import unquote, urlparse

config = Path('.dart_tool/package_config.json').resolve()
if not config.is_file():
    print('')
    raise SystemExit(0)
packages = json.loads(config.read_text()).get('packages', [])
plugin = next((p for p in packages
               if p.get('name') == 'flutter_tesseract_ocr'), None)
if not plugin:
    print('')
else:
    root = plugin.get('rootUri', '')
    parsed = urlparse(root)
    if parsed.scheme == 'file':
        print(unquote(parsed.path))
    elif not parsed.scheme:
        print((config.parent / unquote(root)).resolve())
    else:
        print('')
PY
)"

if [[ -z "$plugin_root" ]]; then
  echo 'Tesseract package not resolved; no legacy Gradle patch required.'
  exit 0
fi

plugin_gradle="$plugin_root/android/build.gradle"
if [[ ! -f "$plugin_gradle" ]]; then
  # Some package releases no longer ship a Groovy Android Gradle script.
  # In that case there is nothing from the legacy buildscript to repair.
  echo "No legacy Tesseract build.gradle at $plugin_gradle; skipping patch."
  exit 0
fi

# The Android host already supplies the supported AGP. Remove the obsolete
# Groovy buildscript/jcenter declaration without touching package sources
# committed to the repository or breaking repeat CI invocations.
sed -i '/^buildscript {/,/^}/d' "$plugin_gradle"
sed -i 's/jcenter()/mavenCentral()/g' "$plugin_gradle"
echo 'Patched resolved Tesseract Gradle repositories.'
