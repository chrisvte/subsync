#!/bin/bash
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"
DEPS_DIR="$DIR/deps"
VENV_DIR="$DIR/venv"

# Ensure libraries can be found
export LD_LIBRARY_PATH="$DEPS_DIR/install/lib:$DEPS_DIR/install/lib64:$LD_LIBRARY_PATH"
# Preload system libstdc++ to avoid Miniconda conflict
export LD_PRELOAD=/lib64/libstdc++.so.6
# Ensure python knows where to find everything if not fully installed
export PYTHONPATH="$DIR:$PYTHONPATH"

# Activate venv
source "$VENV_DIR/bin/activate"

# Run
python3 -m subsync
