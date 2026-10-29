#!/usr/bin/env bash
set -euo pipefail
rm -rf /tmp/drime-bundle /tmp/drime-bundle.zip
mkdir -p /tmp/drime-bundle
base64 -d bundle.b64 > /tmp/drime-bundle.zip
unzip -q -o /tmp/drime-bundle.zip -d /tmp/drime-bundle
cp -a /tmp/drime-bundle/drime-multi-vault/. .
OVERRIDE_FILE=''
for candidate in \
  hypercloud-release-free-fast-site.b64 \
  hypercloud-release-navigation-projects.b64 \
  hypercloud-release-20261026-mfa-share.b64 \
  hypercloud-release-20261031.b64 \
  hypercloud-release-20261021.b64 \
  hypercloud-release-20261020.b64 \
  overrides.b64; do
  if [ -f "$candidate" ]; then
    OVERRIDE_FILE="$candidate"
    break
  fi
done
if [ -n "$OVERRIDE_FILE" ]; then
  base64 -d "$OVERRIDE_FILE" > /tmp/drime-overrides.zip
  rm -rf backend/src frontend/src
  unzip -q -o /tmp/drime-overrides.zip -d .
  echo "Overrides applied from $OVERRIDE_FILE"
fi
node <<'NODE'
const fs = require('node:fs');
const file = 'frontend/package.json';
const pkg = JSON.parse(fs.readFileSync(file, 'utf8'));
pkg.dependencies ??= {};
pkg.devDependencies ??= {};
pkg.dependencies['@capacitor/core'] = '^6.2.1';
pkg.dependencies['@capacitor/filesystem'] = '^6.0.4';
pkg.dependencies['@capacitor/share'] = '^6.0.4';
pkg.devDependencies['@capacitor/cli'] = '^6.2.1';
