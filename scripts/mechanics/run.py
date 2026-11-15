#!/usr/bin/env python3
"""Compatibility entry point used by individual scenario reproduction commands."""
import sys
from pathlib import Path
sys.path.insert(0,str(Path(__file__).resolve().parents[1]))
from mechanics.harness import main
if __name__=='__main__':raise SystemExit(main())
