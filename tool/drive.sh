#!/usr/bin/env bash
# Driving the A72 over adb. The screen there has no working touch, so everything
# goes through input tap — and two of the rules below exist because the wrong
# one costs a whole session.
#
# Usage: A=RQ8R3077LMF ./tool/drive.sh <step> [args]
set -u
: "${A:?export A=<adb serial>}"

case "${1:-help}" in

wake)
  # The A72's screen sleeps on a 2 min timer and screencap fails outright while
  # it is asleep, so wake first and confirm rather than trusting the tap.
  adb -s "$A" shell input keyevent 224
  adb -s "$A" shell wm dismiss-keyguard 2>/dev/null || true
  sleep 1
  adb -s "$A" shell dumpsys user | tr -d '\r' | grep -m1 'State:' |
    sed 's/^ */  /'
  ;;

# Find a solid #B9F53E (the app accent) blob and print its centre. Far more
# reliable than reading coordinates off a screenshot and re-doing it per layout.
# The app's primary buttons and progress fills are the only thing this colour.
findbtn)
  # findbtn <x0> <y0> <x1> <y1> [min_pixels_per_row]
  X0="${2:-0}"; Y0="${3:-0}"; X1="${4:-1080}"; Y1="${5:-2400}"; MIN="${6:-12}"
  adb -s "$A" shell screencap -p /data/local/tmp/_fb.png
  adb -s "$A" pull /data/local/tmp/_fb.png "${TMPDIR:-/tmp}/_fb.png" >/dev/null 2>&1
  python3 - "$X0" "$Y0" "$X1" "$Y1" "$MIN" "${TMPDIR:-/tmp}/_fb.png" <<'PY'
import sys
from PIL import Image
x0, y0, x1, y1, mn, path = int(sys.argv[1]), int(sys.argv[2]), int(sys.argv[3]), int(sys.argv[4]), int(sys.argv[5]), sys.argv[6]
im = Image.open(path).convert('RGB'); px = im.load()
rows = {}
for y in range(y0, min(y1, im.size[1])):
    xs = [x for x in range(x0, min(x1, im.size[0]))
          if abs(px[x, y][0] - 185) < 30 and abs(px[x, y][1] - 245) < 30 and abs(px[x, y][2] - 62) < 34]
    if len(xs) >= mn:
        rows[y] = (min(xs), max(xs))
ys = sorted(rows)
if not ys:
    print('  (nenhuma mancha accent na faixa)'); sys.exit(1)
groups, cur = [], [ys[0]]
for y in ys[1:]:
    (cur if y - cur[-1] <= 3 else groups.append(cur) or (cur := [y])) if False else None
    if y - cur[-1] <= 3: cur.append(y)
    else: groups.append(cur); cur = [y]
groups.append(cur)
for g in groups:
    lo = min(rows[y][0] for y in g); hi = max(rows[y][1] for y in g)
    print(f'  y={g[0]}-{g[-1]}  centro=({(lo+hi)//2},{(g[0]+g[-1])//2})')
PY
  ;;

# Send the current text. Tapping the button is the ONLY way — see the note.
send)
  # send [x] [y]   defaults locate the button first
  if [ $# -ge 3 ]; then X="$2"; Y="$3"
  else read -r line < <("$0" findbtn 900 1100 1080 1450 12); X="${line##*centro=(}"; X="${X%%,*}"; Y="${line##*,}"; Y="${Y%%)*}"
       echo "  botão em ($X, $Y)"; fi
  adb -s "$A" shell input tap "$X" "$Y"
  echo "  botão de envio tocado"
  ;;

*) echo "uso: $0 {wake|findbtn|send}" ;;
esac
