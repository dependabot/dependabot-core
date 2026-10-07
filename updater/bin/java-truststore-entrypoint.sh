#!/usr/bin/env bash
set -e

if command -v keytool >/dev/null 2>&1 && [ -f /etc/ssl/certs/java/cacerts ] && [ -f /usr/local/share/ca-certificates/dbot-ca.crt ]; then
  # Delete the cert first to allow re-imports
  keytool -delete -alias dependabot-ca -keystore /etc/ssl/certs/java/cacerts -storepass changeit >/dev/null 2>&1 || true
  # Import the Dependabot proxy CA certificate
  keytool -importcert -noprompt -trustcacerts -alias dependabot-ca -file /usr/local/share/ca-certificates/dbot-ca.crt -keystore /etc/ssl/certs/java/cacerts -storepass changeit
fi

exec "$@"