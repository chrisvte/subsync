#!/bin/bash
set -e

# Configuration
DEPS_DIR="$(pwd)/deps"
VENV_DIR="$(pwd)/venv"
CORES=$(nproc)

echo "=== Subsync Linux Setup ==="

# 1. Dependency Checks
echo "[*] Checking system dependencies..."
MISSING_DEPS=0

check_cmd() {
    if ! command -v "$1" &> /dev/null; then
        echo "Error: '$1' command not found."
        return 1
    fi
    return 0
}

check_pkg() {
    if ! pkg-config --exists "$1"; then
        echo "Error: pkg-config package '$1' not found."
        return 1
    fi
    return 0
}

check_cmd python3 || MISSING_DEPS=1
check_cmd pip3 || MISSING_DEPS=1
check_cmd gcc || MISSING_DEPS=1
check_cmd g++ || MISSING_DEPS=1
check_cmd make || MISSING_DEPS=1
check_cmd autoconf || MISSING_DEPS=1
check_cmd automake || MISSING_DEPS=1
check_cmd libtool || MISSING_DEPS=1
check_cmd pkg-config || MISSING_DEPS=1
check_cmd bison || MISSING_DEPS=1

if [ $MISSING_DEPS -eq 1 ]; then
    echo "Please install the missing build tools above and try again."
    echo "On Ubuntu/Debian: sudo apt install build-essential python3-dev python3-pip automake autoconf libtool bison pkg-config"
    exit 1
fi

# Check for libraries
echo "[*] Checking for libraries..."
MISSING_LIBS=0
check_pkg libavcodec || MISSING_LIBS=1
check_pkg libavformat || MISSING_LIBS=1
check_pkg libavutil || MISSING_LIBS=1
check_pkg libswresample || MISSING_LIBS=1

# Check for ALSA or PulseAudio headers (needed for pocketsphinx/sphinxbase)
# Note: Pocketsphinx might need alsa headers even if not used directly
if ! pkg-config --exists alsa && ! pkg-config --exists libpulse; then
    echo "Warning: Neither ALSA nor PulseAudio dev libraries found via pkg-config."
    echo "Pocketsphinx compilation might fail."
    MISSING_LIBS=1
fi

if [ $MISSING_LIBS -eq 1 ]; then
    echo "Please install the missing development libraries."
    echo "On Ubuntu/Debian: sudo apt install libavcodec-dev libavformat-dev libavutil-dev libswresample-dev libasound2-dev libpulse-dev"
    exit 1
fi

# 2. Build Directory
mkdir -p "$DEPS_DIR"

# 3. SphinxBase
echo "[*] Building SphinxBase..."
cd "$DEPS_DIR"
if [ ! -f "$DEPS_DIR/install/lib/libsphinxbase.so" ] && [ ! -f "$DEPS_DIR/install/lib/libsphinxbase.a" ] && [ ! -f "$DEPS_DIR/install/lib64/libsphinxbase.so" ] && [ ! -f "$DEPS_DIR/install/lib64/libsphinxbase.a" ]; then
    rm -rf sphinxbase # Clean failure
    git clone https://github.com/cmusphinx/sphinxbase.git
    cd sphinxbase
    # Use version from ~2020 compatible with subsync
    git checkout $(git rev-list -n 1 --before="2020-06-01" HEAD)
    ./autogen.sh
    # Some systems require -fPIC for shared libraries
    export CFLAGS="-fPIC"
    ./configure --prefix="$DEPS_DIR/install" --without-python
    make -j"$CORES"
    make install
else
    echo "SphinxBase already present."
fi

# 4. PocketSphinx
echo "[*] Building PocketSphinx..."
cd "$DEPS_DIR"
if [ ! -f "$DEPS_DIR/install/lib/libpocketsphinx.so" ] && [ ! -f "$DEPS_DIR/install/lib/libpocketsphinx.a" ] && [ ! -f "$DEPS_DIR/install/lib64/libpocketsphinx.so" ] && [ ! -f "$DEPS_DIR/install/lib64/libpocketsphinx.a" ]; then
    rm -rf pocketsphinx # Clean failure
    git clone https://github.com/cmusphinx/pocketsphinx.git
    cd pocketsphinx
    # Use version from ~2020 compatible with subsync
    git checkout $(git rev-list -n 1 --before="2020-06-01" HEAD)
    
    export PKG_CONFIG_PATH="$DEPS_DIR/install/lib/pkgconfig:$DEPS_DIR/install/lib64/pkgconfig:$PKG_CONFIG_PATH"
    # Ensure checking lib64 as well
    export LD_LIBRARY_PATH="$DEPS_DIR/install/lib:$DEPS_DIR/install/lib64:$LD_LIBRARY_PATH"
    
    ./autogen.sh
    export CFLAGS="-fPIC"
    ./configure --prefix="$DEPS_DIR/install" --without-python
    make -j"$CORES"
    make install
else
    echo "PocketSphinx already present."
fi


# 5. Python Environment
echo "[*] Setting up Python virtual environment..."
cd "$DEPS_DIR/.."
if [ ! -d "$VENV_DIR" ]; then
    python3 -m venv "$VENV_DIR"
fi

source "$VENV_DIR/bin/activate"

echo "[*] Installing Python dependencies..."
pip install setuptools
pip install -r requirements.txt
# wxPython isn't in requirements.txt (it was in snapcraft python-packages)
# We need to install it.
pip install wxPython

# 6. Build Subsync
echo "[*] Building Subsync..."
export SPHINXBASE_DIR="$DEPS_DIR/install"
export POCKETSPHINX_DIR="$DEPS_DIR/install"
# FFMPEG is system installed, so we don't set FFMPEG_DIR unless needed. setup.py should find it via pkg-config.
# Export paths for build
export PKG_CONFIG_PATH="$DEPS_DIR/install/lib/pkgconfig:$DEPS_DIR/install/lib64/pkgconfig:$PKG_CONFIG_PATH"
export LD_LIBRARY_PATH="$DEPS_DIR/install/lib:$DEPS_DIR/install/lib64:$LD_LIBRARY_PATH"
export USE_PKG_CONFIG=yes

python setup.py build_py
python setup.py build_ext --inplace

echo "=== Setup Complete ==="
echo "Run ./run_linux.sh to start subsync."
