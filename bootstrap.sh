#!/usr/bin/env bash
set -euo pipefail
rm -rf /tmp/drime-bundle /tmp/drime-bundle.zip
mkdir -p /tmp/drime-bundle
base64 -d bundle.b64 > /tmp/drime-bundle.zip
unzip -q -o /tmp/drime-bundle.zip -d /tmp/drime-bundle
cp -a /tmp/drime-bundle/drime-multi-vault/. .
OVERRIDE_FILE=''
for candidate in \
  hypercloud-release-20261109-mp-links.b64 \
  hypercloud-release-20261105.b64 \
  hypercloud-release-20261104.b64 \
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
# Replace the admin activation-code interstitial with the subscription page after signup.
node <<'NODE'
const fs = require('node:fs');
function replaceOnce(file, before, after) {
  const source = fs.readFileSync(file, 'utf8');
  if (!source.includes(before)) throw new Error(`Expected pattern missing in ${file}`);
  fs.writeFileSync(file, source.replace(before, after));
}
replaceOnce('frontend/src/pages/Login.tsx', `      if (data.activationRequired) {
        sessionStorage.setItem('hypercloud-activation-token', data.activationToken);
        nav('/activate');
      } else if (data.mfaRequired) {
        setMfaChallenge({ id: data.challengeId, method: data.method, frequency: data.frequency, emailHint: data.emailHint });
        setEmailCode('');
        setTotpCode('');
      } else {
        clearFastReadCache();
        localStorage.setItem('token', data.token);
        nav('/files');
      }`, `      if (data.mfaRequired) {
        setMfaChallenge({ id: data.challengeId, method: data.method, frequency: data.frequency, emailHint: data.emailHint });
        setEmailCode('');
        setTotpCode('');
      } else if (register || data.activationRequired) {
        sessionStorage.removeItem('hypercloud-activation-token');
        nav('/planes?registro=1', { replace: true });
      } else {
        clearFastReadCache();
        localStorage.setItem('token', data.token);
        nav('/files');
      }`);
replaceOnce('frontend/src/pages/Login.tsx', `      clearFastReadCache();
      localStorage.setItem('token', data.token);
      nav('/files');
    } catch (err: any) {`, `      if (register) {
        sessionStorage.removeItem('hypercloud-activation-token');
        nav('/planes?registro=1', { replace: true });
      } else {
        clearFastReadCache();
        localStorage.setItem('token', data.token);
        nav('/files');
      }
    } catch (err: any) {`);
replaceOnce('frontend/src/App.tsx', `const ActivationPage = lazy(() => import('./pages/Activation').then(module => ({ default: module.ActivationPage })));
`, '');
replaceOnce('frontend/src/App.tsx', '<Route path="/activate" element={<Page><ActivationPage/></Page>}/>', '<Route path="/activate" element={<Navigate to="/planes" replace/>}/>');
replaceOnce('frontend/src/pages/Plans.tsx', "import { Link } from 'react-router-dom';", "import { Link, useLocation } from 'react-router-dom';");
replaceOnce('frontend/src/pages/Plans.tsx', `export function PlansPage() {
  return (`, `export function PlansPage() {
  const registrationComplete = new URLSearchParams(useLocation().search).get('registro') === '1';
  return (`);
replaceOnce('frontend/src/pages/Plans.tsx', `        </header>

        <section className="mx-auto mt-12 max-w-3xl text-center sm:mt-16">`, `        </header>

        {registrationComplete && (
          <div role="status" className="mx-auto mt-6 max-w-3xl rounded-xl border border-emerald-300/30 bg-emerald-300/10 p-4 text-center text-sm text-emerald-100">
            Cuenta creada. Elige una suscripción para continuar.
          </div>
        )}

        <section className="mx-auto mt-12 max-w-3xl text-center sm:mt-16">`);
console.log('Subscription redirect patch applied');
NODE

# Release bundles store backend sources at backend/, while workspace builds expect backend/src/.
if [ -f backend/app.ts ] && [ ! -f backend/src/app.ts ]; then
  mkdir -p backend/src
  for source in app.ts config.ts crypto.ts lib.ts controllers middleware prisma services types workers; do
    if [ -e "backend/$source" ]; then
      mv "backend/$source" backend/src/
    fi
  done
fi
if [ "$OVERRIDE_FILE" = "hypercloud-release-20261105.b64" ] && [ -f hypercloud-vault-startup-retry.patch ]; then
  git apply --check --whitespace=nowarn hypercloud-vault-startup-retry.patch
  git apply --whitespace=nowarn hypercloud-vault-startup-retry.patch
  echo "Vault startup retry patch applied"
fi
if [ ! -f backend/src/app.ts ] || [ ! -f backend/src/prisma/schema.prisma ]; then
  echo "Backend source is incomplete: expected backend/src/app.ts and backend/src/prisma/schema.prisma" >&2
  exit 1
fi
if [ "$OVERRIDE_FILE" != "hypercloud-release-20261105.b64" ] && [ "$OVERRIDE_FILE" != "hypercloud-release-20261109-mp-links.b64" ] && [ -f hypercloud-hotfix-20261104-r2.patch ]; then
  git apply --check --whitespace=nowarn hypercloud-hotfix-20261104-r2.patch
  git apply --whitespace=nowarn hypercloud-hotfix-20261104-r2.patch
  echo "Upload continuity, PIN cadence, and Android TV fixes applied"
fi
# The newest release bundle already includes the selected PIN/reliability patches.
if [ "$OVERRIDE_FILE" != "hypercloud-release-20261104.b64" ] && [ "$OVERRIDE_FILE" != "hypercloud-release-20261105.b64" ] && [ "$OVERRIDE_FILE" != "hypercloud-release-20261109-mp-links.b64" ]; then
  if [ -f hypercloud-hotfix-20261031.patch ]; then
    git apply --check --whitespace=nowarn hypercloud-hotfix-20261031.patch
    git apply --whitespace=nowarn hypercloud-hotfix-20261031.patch
    echo "Reliability and security hotfix applied"
  fi
  if [ -f hypercloud-pin-lock.patch ]; then
    git apply --check --whitespace=nowarn hypercloud-pin-lock.patch
    git apply --whitespace=nowarn hypercloud-pin-lock.patch
    echo "PIN lock-on-exit hotfix applied"
  fi
  if [ -f hypercloud-pin-navigation.patch ]; then
    git apply --check --whitespace=nowarn hypercloud-pin-navigation.patch
    git apply --whitespace=nowarn hypercloud-pin-navigation.patch
    echo "Protected-section navigation hotfix applied"
  fi
fi
node <<'NODE'
const fs = require('node:fs');
const file = 'frontend/package.json';
const pkg = JSON.parse(fs.readFileSync(file, 'utf8'));
pkg.dependencies ??= {};
pkg.devDependencies ??= {};
pkg.dependencies['@capacitor/core'] = '^6.2.1';
pkg.dependencies['@capacitor/app'] = '^6.0.2';
pkg.dependencies['@capacitor/filesystem'] = '^6.0.4';
pkg.dependencies['@capacitor/network'] = '^6.0.4';
pkg.dependencies['@capacitor/share'] = '^6.0.4';
pkg.devDependencies['@capacitor/cli'] = '^6.2.1';
pkg.devDependencies['@capacitor/android'] = '^6.2.1';
fs.writeFileSync(file, `${JSON.stringify(pkg, null, 2)}\n`);
const backendFile = 'backend/package.json';
const backendPkg = JSON.parse(fs.readFileSync(backendFile, 'utf8'));
backendPkg.dependencies ??= {};
backendPkg.dependencies.megajs = '^1.3.10';
fs.writeFileSync(backendFile, `${JSON.stringify(backendPkg, null, 2)}\n`);
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
import path from 'node:path';


const manifestPath = 'android/app/src/main/AndroidManifest.xml';
let manifest = fs.readFileSync(manifestPath, 'utf8');
if (!manifest.includes('<application')) throw new Error('Android manifest has no <application> element');
for (const permission of ['android.permission.CAMERA', 'android.permission.RECORD_AUDIO']) {
  const declaration = `android:name="${permission}"`;
  if (!manifest.includes(declaration)) manifest = manifest.replace('<application', `    <uses-permission ${declaration} />\n    <application`);
}
for (const feature of ['android.software.leanback', 'android.hardware.touchscreen']) {
  const declaration = `android:name="${feature}"`;
  if (!manifest.includes(declaration)) manifest = manifest.replace('<application', `    <uses-feature ${declaration} android:required="false" />\n    <application`);
}
manifest = manifest.replace(/<application\b([^>]*)>/, (tag, attributes) => attributes.includes('android:banner=') ? tag : `<application${attributes} android:banner="@drawable/hypercloud_tv_banner">`);
const launcher = /(<intent-filter>(?:(?!<\/intent-filter>)[\s\S])*?<action\s+android:name="android\.intent\.action\.MAIN"\s*\/>[\s\S]*?<category\s+android:name="android\.intent\.category\.LAUNCHER"\s*\/>)([\s\S]*?<\/intent-filter>)/;
if (!manifest.includes('android.intent.category.LEANBACK_LAUNCHER')) {
  if (!launcher.test(manifest)) throw new Error('Android launcher intent filter not found for Leanback support');
  manifest = manifest.replace(launcher, '$1\n                <category android:name="android.intent.category.LEANBACK_LAUNCHER" />$2');
}
fs.writeFileSync(manifestPath, manifest);
const banner = 'android-icons/tv_banner.png';
if (fs.existsSync(banner)) {
  const drawableDir = 'android/app/src/main/res/drawable-nodpi';
  fs.mkdirSync(drawableDir, { recursive: true });
  fs.copyFileSync(banner, path.join(drawableDir, 'hypercloud_tv_banner.png'));
}
JS
npm install --package-lock-only --ignore-scripts --include=dev --no-audit --no-fund
echo "Cloud bundle extracted and workspace lockfile synchronized"
if [ -f hypercloud-app-lock.patch ] && [ "$OVERRIDE_FILE" != "hypercloud-release-20261104.b64" ] && [ "$OVERRIDE_FILE" != "hypercloud-release-20261105.b64" ] && [ "$OVERRIDE_FILE" != "hypercloud-release-20261109-mp-links.b64" ]; then
  git apply --check --whitespace=nowarn hypercloud-app-lock.patch
  git apply --whitespace=nowarn hypercloud-app-lock.patch
  echo "Optional PIN app lock applied"
fi
# Include the latest signed APK in the public Render static-site build.
if [ -f Hypercloud.apk ]; then
  mkdir -p frontend/public
  cp -f Hypercloud.apk frontend/public/Hypercloud.apk
fi
