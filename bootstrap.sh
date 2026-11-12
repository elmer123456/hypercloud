#!/usr/bin/env bash
set -euo pipefail
rm -rf /tmp/drime-bundle /tmp/drime-bundle.zip
mkdir -p /tmp/drime-bundle
base64 -d bundle.b64 > /tmp/drime-bundle.zip
unzip -q -o /tmp/drime-bundle.zip -d /tmp/drime-bundle
cp -a /tmp/drime-bundle/drime-multi-vault/. .
OVERRIDE_FILE=''
for candidate in \
  hypercloud-release-20261112-r2.b64 \
  hypercloud-release-20261112.b64 \
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
# Subscription signup plus private 12-character, one-use activation codes.
node <<'NODE'
const fs = require('node:fs');
function replaceOnce(file, before, after) {
  const source = fs.readFileSync(file, 'utf8');
  if (!source.includes(before)) throw new Error(`Expected pattern missing in ${file}: ${before.slice(0, 90)}`);
  fs.writeFileSync(file, source.replace(before, after));
}
replaceOnce('backend/src/controllers/admin.ts', `  const parsed = z.object({
    quantity: z.coerce.number().int().min(1).max(5000),
    maxUses: z.coerce.number().int().min(1).max(10000).default(1),
    expiresAt: z.string().datetime().optional(),
    note: z.string().trim().max(300).optional(),
  }).safeParse(req.body);
  if (!parsed.success) return res.status(400).json({ error: 'INVALID_INPUT' });
  const codes: { code: string; codeHash: string; codeLabel: string; maxUses: number; expiresAt: Date | null; note: string | null }[] = [];
  const seen = new Set<string>();
  while (codes.length < parsed.data.quantity) {
    const raw = crypto.randomBytes(16).toString('hex').toUpperCase();
    const code = \`HC-\${raw.match(/.{1,4}/gu)!.join('-')}\`;
    const hash = crypto.createHmac('sha256', env.JWT_SECRET).update(raw).digest('hex');
    if (seen.has(hash)) continue;
    seen.add(hash);
    codes.push({
      code,
      codeHash: hash,
      codeLabel: \`HC-\${raw.slice(-4)}\`,
      maxUses: parsed.data.maxUses,
      expiresAt: parsed.data.expiresAt ? new Date(parsed.data.expiresAt) : null,
      note: parsed.data.note || null,
    });
  }
  await prisma.activationCode.createMany({
    data: codes.map(({ codeHash: hash, codeLabel, maxUses, expiresAt, note }) => ({ codeHash: hash, codeLabel, maxUses, expiresAt, note })),
  });
  res.status(201).json({ codes: codes.map(({ code }) => code), count: codes.length });`, `  const parsed = z.object({
    quantity: z.coerce.number().int().min(1).max(5000),
    note: z.string().trim().max(300).optional(),
  }).safeParse(req.body);
  if (!parsed.success) return res.status(400).json({ error: 'INVALID_INPUT' });
  const alphabet = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
  const codes: { code: string; codeHash: string; codeLabel: string; maxUses: number; expiresAt: Date; note: string | null }[] = [];
  const seen = new Set<string>();
  while (codes.length < parsed.data.quantity) {
    let code = '';
    for (let i = 0; i < 12; i++) code += alphabet[crypto.randomInt(alphabet.length)];
    const hash = crypto.createHmac('sha256', env.JWT_SECRET).update(code).digest('hex');
    if (seen.has(hash)) continue;
    seen.add(hash);
    codes.push({ code, codeHash: hash, codeLabel: code.slice(-4), maxUses: 1, expiresAt: new Date(Date.now() + 5 * 60_000), note: parsed.data.note || null });
  }
  await prisma.activationCode.createMany({
    data: codes.map(({ codeHash, codeLabel, maxUses, expiresAt, note }) => ({ codeHash, codeLabel, maxUses, expiresAt, note })),
  });
  res.status(201).json({ codes: codes.map(({ code }) => code), count: codes.length });`);
replaceOnce('backend/src/controllers/auth.ts', `    const parsed = credentials.safeParse(req.body);
    if (!parsed.success) return res.status(400).json({ error: 'INVALID_INPUT' });
    if (env.ALLOW_REGISTRATION === 'false') {
      return res.status(403).json({ error: 'REGISTRATION_CLOSED' });
    }

    const email = parsed.data.email.toLowerCase();
    if (await prisma.user.findUnique({ where: { email } })) {
      return res.status(409).json({ error: 'EMAIL_IN_USE' });
    }

    const user = await prisma.user.create({
      data: { email, passwordHash: await bcrypt.hash(parsed.data.password, 12) },
      select: { id: true, authVersion: true },
    });
    await prisma.user.update({ where: { id: user.id }, data: { activatedAt: null } });
    res.status(201).json({
      activationRequired: true,
      activationToken: issueActivationToken(user.id),
    });`, `    const parsed = credentials.extend({ activationCode: z.string().trim().max(32).optional() }).safeParse(req.body);
    if (!parsed.success) return res.status(400).json({ error: 'INVALID_INPUT' });
    if (env.ALLOW_REGISTRATION === 'false') {
      return res.status(403).json({ error: 'REGISTRATION_CLOSED' });
    }

    const email = parsed.data.email.toLowerCase();
    if (await prisma.user.findUnique({ where: { email } })) {
      return res.status(409).json({ error: 'EMAIL_IN_USE' });
    }
    const passwordHash = await bcrypt.hash(parsed.data.password, 12);
    const normalizedCode = parsed.data.activationCode?.toUpperCase().replace(/[^A-Z0-9]/gu, '');
    if (parsed.data.activationCode && normalizedCode?.length !== 12) {
      return res.status(400).json({ error: 'INVALID_ACTIVATION_CODE' });
    }

    if (normalizedCode) {
      const codeHash = crypto.createHmac('sha256', env.JWT_SECRET).update(normalizedCode).digest('hex');
      const now = new Date();
      const result = await prisma.$transaction(async tx => {
        const code = await tx.activationCode.findUnique({ where: { codeHash } });
        if (!code || code.revokedAt || code.expiresAt && code.expiresAt <= now || code.useCount >= code.maxUses) {
          return { error: 'INVALID_ACTIVATION_CODE' as const };
        }
        const claimed = await tx.activationCode.updateMany({
          where: { id: code.id, useCount: { lt: 1 }, revokedAt: null, expiresAt: { gt: now } },
          data: { useCount: { increment: 1 } },
        });
        if (claimed.count !== 1) return { error: 'INVALID_ACTIVATION_CODE' as const };
        const user = await tx.user.create({
          data: { email, passwordHash, activatedAt: now },
          select: { id: true, authVersion: true },
        });
        await tx.activationCodeRedemption.create({ data: { codeId: code.id, userId: user.id } });
        return user;
      });
      if ('error' in result) return res.status(400).json({ error: result.error });
      return res.status(201).json({ token: issueToken(result.id, result.authVersion), activated: true });
    }

    const user = await prisma.user.create({
      data: { email, passwordHash, activatedAt: null },
      select: { id: true },
    });
    res.status(201).json({ activationRequired: true, activationToken: issueActivationToken(user.id) });`);
replaceOnce('frontend/src/pages/Login.tsx', `  const [register, setRegister] = useState(() => location.pathname === '/signup');
  useEffect(() => setRegister(location.pathname === '/signup'), [location.pathname]);`, `  const [register, setRegister] = useState(() => location.pathname === '/signup');
  const [useActivationCode, setUseActivationCode] = useState(false);
  const [activationCode, setActivationCode] = useState('');
  useEffect(() => setRegister(location.pathname === '/signup'), [location.pathname]);`);
replaceOnce('frontend/src/pages/Login.tsx', `        password,
        ...(!register ? { deviceId: deviceId() } : {}),`, `        password,
        ...(register && useActivationCode ? { activationCode: activationCode.trim().toUpperCase() } : {}),
        ...(!register ? { deviceId: deviceId() } : {}),`);
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
      } else if (register && useActivationCode && data.token) {
        clearFastReadCache();
        localStorage.setItem('token', data.token);
        setActivationCode('');
        nav('/files', { replace: true });
      } else if (register || data.activationRequired) {
        sessionStorage.removeItem('hypercloud-activation-token');
        nav('/planes?registro=1', { replace: true });
      } else {
        clearFastReadCache();
        localStorage.setItem('token', data.token);
        nav('/files');
      }`);
replaceOnce('frontend/src/pages/Login.tsx', `      setError(code === 'ACCOUNT_SUSPENDED'
        ? 'Esta cuenta está temporalmente suspendida. Contacta al administrador.'`, `      setError(code === 'INVALID_ACTIVATION_CODE'
        ? 'Código inválido, vencido o ya utilizado.'
        : code === 'ACCOUNT_SUSPENDED'
        ? 'Esta cuenta está temporalmente suspendida. Contacta al administrador.'`);
replaceOnce('frontend/src/pages/Login.tsx', `        /></>}
        {mfaChallenge && <div className="space-y-3">`, `        />
        {register && useActivationCode && <label className="mb-3 block text-sm font-medium">Código de activación<input required autoComplete="off" maxLength={12} minLength={12} pattern="[A-Za-z0-9]{12}" value={activationCode} onChange={e => setActivationCode(e.target.value.replace(/[^A-Za-z0-9]/g, '').slice(0, 12).toUpperCase())} placeholder="12 letras y números" className="focus-neon mt-1 w-full rounded-xl bg-white/5 p-3 font-mono uppercase"/></label>}
        </>}
        {mfaChallenge && <div className="space-y-3">`);
replaceOnce('frontend/src/pages/Login.tsx', `        {!mfaChallenge && <button
          type="button"
          onClick={() => { const next = !register; setRegister(next); setError(''); setMfaChallenge(null); nav(next ? '/signup' : '/login', { replace: true }); }}
          className="mt-4 w-full text-vault-muted hover:text-white"
        >
          {register ? 'Ya tengo cuenta' : 'Crear usuario'}
        </button>}`, `        {!mfaChallenge && register && <button type="button" onClick={() => { setUseActivationCode(v => !v); setActivationCode(''); setError(''); }} className="mt-4 w-full rounded-xl border border-vault-primary/30 p-3 text-sm font-semibold text-vault-primary hover:bg-vault-primary/10">{useActivationCode ? 'Crear cuenta con suscripción' : 'Crear con Código de activación'}</button>}
        {!mfaChallenge && <button
          type="button"
          onClick={() => { const next = !register; setRegister(next); setUseActivationCode(false); setActivationCode(''); setError(''); setMfaChallenge(null); nav(next ? '/signup' : '/login', { replace: true }); }}
          className="mt-4 w-full text-vault-muted hover:text-white"
        >
          {register ? 'Ya tengo cuenta' : 'Crear usuario'}
        </button>}`);
replaceOnce('frontend/src/pages/AdminPanel.tsx', `  const [quantity, setQuantity] = useState(100);
  const [maxUses, setMaxUses] = useState(1);
  const [note, setNote] = useState('');
  const [expiresAt, setExpiresAt] = useState('');`, `  const [quantity, setQuantity] = useState(100);
  const [note, setNote] = useState('');`);
replaceOnce('frontend/src/pages/AdminPanel.tsx', `      const { data } = await adminApi.post('/admin/codes/generate', {
        quantity, maxUses, note: note || undefined,
        expiresAt: expiresAt ? new Date(expiresAt).toISOString() : undefined,
      }, { headers: { Authorization: \`Bearer \${token}\` } });`, `      const { data } = await adminApi.post('/admin/codes/generate', {
        quantity, note: note || undefined,
      }, { headers: { Authorization: \`Bearer \${token}\` } });`);
replaceOnce('frontend/src/pages/AdminPanel.tsx', `              <form onSubmit={generateCodes} className="grid gap-3 sm:grid-cols-2 lg:grid-cols-[.7fr_.7fr_1.2fr_1.2fr_auto]">
                <label className="text-xs text-vault-muted">Cantidad<input type="number" min={1} max={5000} value={quantity} onChange={e => setQuantity(Math.max(1, Math.min(5000, Number(e.target.value))))} className={\`\${field} mt-1\`}/></label>
                <label className="text-xs text-vault-muted">Usos por código<input type="number" min={1} max={10000} value={maxUses} onChange={e => setMaxUses(Math.max(1, Math.min(10000, Number(e.target.value))))} className={\`\${field} mt-1\`}/></label>
                <label className="text-xs text-vault-muted">Nota / lote<input maxLength={300} value={note} onChange={e => setNote(e.target.value)} placeholder="Ej. Lote noviembre" className={\`\${field} mt-1\`}/></label>
                <label className="text-xs text-vault-muted">Vencimiento (opcional)<input type="datetime-local" value={expiresAt} onChange={e => setExpiresAt(e.target.value)} className={\`\${field} mt-1\`}/></label>
                <button disabled={busy} className="flex min-h-10 items-center justify-center gap-2 self-end rounded-xl bg-vault-primary px-4 font-bold text-black disabled:opacity-50">{busy ? <LoaderCircle className="animate-spin"/> : <KeyRound size={16}/>}Generar</button>
              </form>`, `              <p className="mb-3 text-xs text-vault-muted">Cada código contiene 12 caracteres aleatorios, se usa una sola vez y vence a los 5 minutos.</p>
              <form onSubmit={generateCodes} className="grid gap-3 sm:grid-cols-2 lg:grid-cols-[.7fr_1.2fr_auto]">
                <label className="text-xs text-vault-muted">Cantidad<input type="number" min={1} max={5000} value={quantity} onChange={e => setQuantity(Math.max(1, Math.min(5000, Number(e.target.value))))} className={\`\${field} mt-1\`}/></label>
                <label className="text-xs text-vault-muted">Nota / lote<input maxLength={300} value={note} onChange={e => setNote(e.target.value)} placeholder="Ej. Lote noviembre" className={\`\${field} mt-1\`}/></label>
                <button disabled={busy} className="flex min-h-10 items-center justify-center gap-2 self-end rounded-xl bg-vault-primary px-4 font-bold text-black disabled:opacity-50">{busy ? <LoaderCircle className="animate-spin"/> : <KeyRound size={16}/>}Generar</button>
              </form>`);
replaceOnce('frontend/src/pages/AdminPanel.tsx', `c.useCount}/{c.maxUses} usos · {c.note || 'Sin nota'} · vence {c.expiresAt ? new Date(c.expiresAt).toLocaleDateString('es') : 'nunca'}`, `c.useCount}/{c.maxUses} usos · {c.note || 'Sin nota'} · vence {c.expiresAt ? new Date(c.expiresAt).toLocaleString('es') : 'nunca'}`);
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
console.log('Activation-code signup patch applied');
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
if [ "$OVERRIDE_FILE" != "hypercloud-release-20261105.b64" ] && [ "$OVERRIDE_FILE" != "hypercloud-release-20261109-mp-links.b64" ] && [ "$OVERRIDE_FILE" != "hypercloud-release-20261112-r2.b64" ] && [ "$OVERRIDE_FILE" != "hypercloud-release-20261112.b64" ] && [ -f hypercloud-hotfix-20261104-r2.patch ]; then
  git apply --check --whitespace=nowarn hypercloud-hotfix-20261104-r2.patch
  git apply --whitespace=nowarn hypercloud-hotfix-20261104-r2.patch
  echo "Upload continuity, PIN cadence, and Android TV fixes applied"
fi
# The newest release bundle already includes the selected PIN/reliability patches.
if [ "$OVERRIDE_FILE" != "hypercloud-release-20261104.b64" ] && [ "$OVERRIDE_FILE" != "hypercloud-release-20261105.b64" ] && [ "$OVERRIDE_FILE" != "hypercloud-release-20261109-mp-links.b64" ] && [ "$OVERRIDE_FILE" != "hypercloud-release-20261112-r2.b64" ] && [ "$OVERRIDE_FILE" != "hypercloud-release-20261112.b64" ]; then
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
if [ -f hypercloud-app-lock.patch ] && [ "$OVERRIDE_FILE" != "hypercloud-release-20261104.b64" ] && [ "$OVERRIDE_FILE" != "hypercloud-release-20261105.b64" ] && [ "$OVERRIDE_FILE" != "hypercloud-release-20261109-mp-links.b64" ] && [ "$OVERRIDE_FILE" != "hypercloud-release-20261112-r2.b64" ] && [ "$OVERRIDE_FILE" != "hypercloud-release-20261112.b64" ]; then
  git apply --check --whitespace=nowarn hypercloud-app-lock.patch
  git apply --whitespace=nowarn hypercloud-app-lock.patch
  echo "Optional PIN app lock applied"
fi
# Include the latest signed APK in the public Render static-site build.
if [ -f Hypercloud.apk ]; then
  mkdir -p frontend/public
  cp -f Hypercloud.apk frontend/public/Hypercloud.apk
fi
# Make the existing landing-page APK button download the file directly.
node <<'NODE'
const fs = require('node:fs');
const file = 'frontend/src/pages/Landing.tsx';
if (fs.existsSync(file)) {
  let source = fs.readFileSync(file, 'utf8');
  const marker = '<a href="/Hypercloud.apk"';
  if (!source.includes(marker)) throw new Error('Landing APK link not found');
  if (!source.includes('download="Hypercloud.apk"')) {
    source = source.replace(marker, `${marker} download="Hypercloud.apk"`);
    fs.writeFileSync(file, source);
  }
}
const htmlFile = 'frontend/index.html';
if (fs.existsSync(htmlFile)) {
  const html = fs.readFileSync(htmlFile, 'utf8');
  const titled = html.replace(/<title>[^<]*<\/title>/i, '<title>Hypercloud</title>');
  if (!/<title>[^<]*<\/title>/i.test(html)) throw new Error('HTML title tag not found');
  if (html !== titled) fs.writeFileSync(htmlFile, titled);
}
NODE

# Publish ATLOS recurring crypto checkout while preserving Mercado Pago.
# Keep the generated Android package in sync with the selected release bundle.
node atlos-patch.js
