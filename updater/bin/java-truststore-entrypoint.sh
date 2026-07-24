#!/usr/bin/env bash
set -e

if command -v keytool >/dev/null 2>&1 && [ -f /usr/local/share/ca-certificates/dbot-ca.crt ]; then
  keytool -importcert \
    -alias dbot-ca \
    -file /usr/local/share/ca-certificates/dbot-ca.crt \
    -cacerts \
    -storepass changeit \
    -noprompt >/dev/null 2>&1 || true
fi

exec "$@"