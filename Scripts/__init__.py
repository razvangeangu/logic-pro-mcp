from __future__ import annotations

import sys
from pathlib import Path


_PACKAGE_DIR = Path(__file__).resolve().parent
_PACKAGE_DIR_STR = str(_PACKAGE_DIR)
if _PACKAGE_DIR_STR not in sys.path:
    sys.path.insert(0, _PACKAGE_DIR_STR)
