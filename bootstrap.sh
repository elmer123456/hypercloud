#!/usr/bin/env bash
set -euo pipefail
rm -rf /tmp/drime-bundle /tmp/drime-bundle.zip
mkdir -p /tmp/drime-bundle
base64 -d bundle.b64 > /tmp/drime-bundle.zip
unzip -q -o /tmp/drime-bundle.zip -d /tmp/drime-bundle
cp -a /tmp/drime-bundle/drime-multi-vault/. .
OVERRIDE_FILE=''
for candidate in \
  hypercloud-release-logo-v3.b64 \
  hypercloud-release-icon-worker.b64 \
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
# Keep backend/package.json and frontend/android-icons in the selected bundle for API and APK builds.
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
pkg.devDependencies['@capacitor/android'] = '^6.2.1';
fs.writeFileSync(file, `${JSON.stringify(pkg, null, 2)}\n`);
NODE
cat > frontend/capacitor.config.json <<'JSON'
{
  "appId": "com.hypercloud.app",
  "appName": "Hypercloud",
  "webDir": "dist"
}
JSON
mkdir -p frontend/scripts
cat > frontend/scripts/patch-android-manifest.mjs <<'JS'
import fs from 'node:fs';

const manifestPath = 'android/app/src/main/AndroidManifest.xml';
let manifest = fs.readFileSync(manifestPath, 'utf8');
if (!manifest.includes('<application')) throw new Error('Android manifest has no <application> element');
for (const permission of ['android.permission.CAMERA', 'android.permission.RECORD_AUDIO']) {
  const declaration = `android:name="${permission}"`;
  if (!manifest.includes(declaration)) {
    manifest = manifest.replace('<application', `    <uses-permission ${declaration} />\n    <application`);
  }
}
fs.writeFileSync(manifestPath, manifest);
JS
npm install --package-lock-only --ignore-scripts --include=dev --no-audit --no-fund
echo "Cloud bundle extracted and workspace lockfile synchronized"
