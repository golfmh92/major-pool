#!/bin/bash
set -e

mkdir -p dist

cp index.html dist/index.html
cp sw.js dist/sw.js
cp _headers dist/_headers
[ -f apple-touch-icon.png ] && cp apple-touch-icon.png dist/apple-touch-icon.png

echo "Build complete: dist/index.html + sw.js + _headers + apple-touch-icon.png"
