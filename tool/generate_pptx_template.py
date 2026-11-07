"""Regenerate the tiny, standards-compliant PPTX skeleton used by To PPT.

Run with python-pptx installed:
    python3 tool/generate_pptx_template.py

Only the blank slide/template/theme are bundled. Document images and text are
added on-device in Dart. No user documents are sent to a server.
"""

from pathlib import Path

from pptx import Presentation
from pptx.util import Inches


def main() -> None:
    project = Path(__file__).resolve().parents[1]
    destination = project / "assets" / "pptx" / "blank_template.pptx"
    destination.parent.mkdir(parents=True, exist_ok=True)
    presentation = Presentation()
    presentation.slide_width = Inches(13.333333)
    presentation.slide_height = Inches(7.5)
    presentation.slides.add_slide(presentation.slide_layouts[6])
    presentation.save(destination)
    print(f"Generated {destination} ({destination.stat().st_size} bytes)")


if __name__ == "__main__":
    main()
