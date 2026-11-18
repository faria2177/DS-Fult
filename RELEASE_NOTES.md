## DocScanner v0.5.55

- ✍️ Edit Text now makes changed or added words blend into the page:
  - Only the old letters are removed; the paper keeps its own texture, and table lines crossing the text stay
  - DS AI draws the original words in several fonts (normal, serif like Times, condensed, typewriter; regular and bold) and uses the one that matches the printed letters best
  - Same height, letter width and baseline as the original line, in the darkest ink colour of the original letters, softened like the scan
  - Left, centred and right-aligned lines keep their alignment (judged from the lines around them); a longer text grows the right way and only narrows or shrinks if it would leave the page
