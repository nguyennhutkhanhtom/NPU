"""Find an authenticated X11 display belonging to this Linux account.

Never print/read Xauthority cookies or relax X server access controls.
An active own RDP session can supply X11 when SSH has no forwarded display.
"""
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys


def main():
    if sys.platform != 'linux' or not shutil.which('xdpyinfo'):
        raise SystemExit('Linux xdpyinfo is required to validate X11')
    uid = os.getuid()
    candidates = [(os.environ.get('DISPLAY', ''), os.environ.get('XAUTHORITY', ''))]
    for process in Path('/proc').iterdir():
        if not process.name.isdigit():
            continue
        try:
            if process.stat().st_uid != uid:
                continue
            fields = (process / 'environ').read_bytes().split(b'\0')
            display = next((f[8:].decode() for f in fields if f.startswith(b'DISPLAY=')), '')
            authority = next((f[11:].decode() for f in fields if f.startswith(b'XAUTHORITY=')), '')
            candidates.append((display, authority))
        except (OSError, UnicodeError):
            continue
    seen = set()
    for display, authority in candidates:
        if not re.fullmatch(r'[A-Za-z0-9_.:/-]+:[0-9]+(?:\.[0-9]+)?', display):
            # A local display starts directly with a colon.
            if not re.fullmatch(r':[0-9]+(?:\.[0-9]+)?', display):
                continue
        authority = Path(authority or Path.home() / '.Xauthority').resolve()
        try:
            if not authority.is_file() or authority.stat().st_uid != uid:
                continue
        except OSError:
            continue
        candidate = (display, str(authority))
        if candidate in seen or any(c in str(authority) for c in '\r\n\t'):
            continue
        seen.add(candidate)
        environment = dict(os.environ, DISPLAY=display, XAUTHORITY=str(authority))
        try:
            check = subprocess.run(['xdpyinfo'], env=environment, stdout=subprocess.DEVNULL,
                                   stderr=subprocess.DEVNULL, timeout=5)
        except subprocess.TimeoutExpired:
            continue
        if check.returncode == 0:
            print(display + '\t' + str(authority))
            return
    raise SystemExit('No authenticated own X11 display. Open your RDP desktop, or use working SSH -X with a local X server; --x11 remains required.')


if __name__ == '__main__':
    main()
