#!/bin/bash

if [ ! $# -eq "2" ]; then
    echo "Usage: $0 key file" >&2
    exit 1
fi

KEY=$1
FILE=$2

SIGNEDFILE=$(echo -n "$FILE" | sed 's/\.rofl$/.signed.rofl/')

# Turn this on if you want to extract signature and verify
# tail -c +263 "$FILE" | openssl dgst -sign "$KEY" -sha1 > "$FILE.sig.bin"
# tail -c +263 "$FILE" | openssl dgst -signature "$FILE.sig.bin" -sha1 -verify "$BASE/my/my.pub"

head -c 6 "$FILE" > "$SIGNEDFILE"
tail -c +263 "$FILE" | openssl dgst -sign "$KEY" -sha1 >> "$SIGNEDFILE"
tail -c +263 "$FILE" >> "$SIGNEDFILE"

echo $SIGNEDFILE
