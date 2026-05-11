#!/bin/bash
set -e

mkdir -p dist

cp index.html dist/index.html
cp sw.js dist/sw.js
[ -f apple-touch-icon.png ] && cp apple-touch-icon.png dist/apple-touch-icon.png

echo "Build complete: dist/index.html + sw.js + apple-touch-icon.png"
