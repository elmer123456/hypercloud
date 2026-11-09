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
