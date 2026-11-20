#!/bin/sh
set -eu
WORK="$1"
SRC="$2"
XMLWF="$3"
mkdir -p "$WORK/tests"
if [ ! -f "$WORK/tests/xmlts.zip" ]; then
  if command -v curl >/dev/null 2>&1; then
    curl -fsSL -o "$WORK/tests/xmlts.zip" https://www.w3.org/XML/Test/xmlts20080827.zip
  else
    wget -O "$WORK/tests/xmlts.zip" https://www.w3.org/XML/Test/xmlts20080827.zip
  fi
fi
if [ ! -d "$WORK/tests/xmlconf" ]; then
  (cd "$WORK/tests" && unzip -q xmlts.zip)
fi
(cd "$WORK" && bash "$SRC/tests/xmltest.sh" "$XMLWF" > "$WORK/tests/xmltest.log" 2>&1 || true)
cp "$WORK/tests/xmltest.log" "$WORK/tests/xmltest.log.raw"
bash "$SRC/fix-xmltest-log.sh" "$WORK/tests/xmltest.log"
diff -u "$SRC/tests/xmltest.log.expected" "$WORK/tests/xmltest.log"
