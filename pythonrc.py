# ~/.pythonrc.py
# Auto-loaded at Python REPL startup if PYTHONSTARTUP is set

import datetime as dt
import os
import pprint
import sys
from pathlib import Path

# --- Pretty printing ---
pp = pprint.PrettyPrinter(indent=2, width=100).pprint


# --- Shortcuts & helpers ---
def ls(path="."):
    """List files in a directory."""
    print("\n".join(sorted(os.listdir(path))))


def cd(path):
    """Change current working directory."""
    os.chdir(path)
    print(f"📂 {os.getcwd()}")


def pwd():
    """Print current working directory."""
    print(os.getcwd())


def head(file, n=10):
    """Show first n lines of a file."""
    with open(file) as f:
        for i, line in enumerate(f):
            if i >= n:
                break
            print(line, end="")


# --- Quality of life tweaks ---
sys.ps1 = "🐍 >>> "
sys.ps2 = "    ... "
os.environ["PYTHONBREAKPOINT"] = "ipdb.set_trace"  # if you use ipdb

# --- History file (persistent REPL history) ---
import atexit
import readline
import rlcompleter

history_file = Path("~/.pyhistory").expanduser()
readline.parse_and_bind("tab: complete")

if history_file.exists():
    readline.read_history_file(history_file)

atexit.register(readline.write_history_file, history_file)

print("✅ Python RC loaded: auto-imports, helpers, and history ready.")
