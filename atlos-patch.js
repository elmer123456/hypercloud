const fs = require('node:fs');
const file = 'frontend/src/pages/Plans.tsx';
let source = fs.readFileSync(file, 'utf8');
if (source.includes('ATLOS cryptocurrency checkout')) throw new Error('ATLOS patch already applied');
const planConfig = "const enterpriseUrl = String(import.meta.env.VITE_MP_ENTERPRISE_URL || 'https://mpago.la/12wizvb').trim();";
if (!source.includes(planConfig)) throw new Error('Mercado Pago plan settings not found');
source = source.replace(planConfig, `${planConfig}\nconst atlosMerchantId = 'DDDZ46ELBA';\n\nfunction openAtlosCheckout(planName: string, amount: number) {\n  const widget = (window as Window & { atlos?: any }).atlos;\n  if (!widget?.Pay) {\n    window.alert('El checkout de ATLOS aún está cargando. Inténtalo de nuevo en unos segundos.');\n    return;\n  }\n  widget.Pay({\n    merchantId: atlosMerchantId,\n    orderId: \`hypercloud-\${planName.toLowerCase()}-\${crypto.randomUUID()}\`,\n    orderAmount: amount,\n    orderCurrency: 'USD',\n    captureEmail: true,\n    recurrence: widget.RECURRENCE_MONTH,\n    language: 'es',\n    theme: 'dark',\n    onSuccess: () => window.alert('ATLOS confirmó el pago. Hypercloud verificará manualmente la activación del plan; conserva el correo de confirmación.'),\n  });\n}`);
const start = source.indexOf('function PlanAction(');
const end = source.indexOf('\nexport function PlansPage()', start);
if (start < 0 || end < 0) throw new Error('PlanAction block not found');
const replacement = `function PlanAction({ href, action, trial, planName, amount }: { href: string; action: string; trial: boolean; planName: string; amount: number }) {\n  if (trial) {\n    return (\n      <Link to="/signup" className="inline-flex min-h-12 w-full items-center justify-center gap-2 rounded-xl bg-white px-4 py-3 font-bold text-slate-950 hover:bg-slate-200">\n        {action}<ArrowUpRight size={17} aria-hidden="true"/>\n      </Link>\n    );\n  }\n\n  return (\n    <div className="grid w-full gap-2">\n      <a href={href} target="_blank" rel="noopener noreferrer" className="inline-flex min-h-12 w-full items-center justify-center gap-2 rounded-xl bg-emerald-300 px-4 py-3 font-bold text-slate-950 hover:bg-emerald-200">\n        <CreditCard size={17} aria-hidden="true"/>{action}<ArrowUpRight size={17} aria-hidden="true"/>\n      </a>\n      <button type="button" onClick={() => openAtlosCheckout(planName, amount)} className="inline-flex min-h-12 w-full items-center justify-center gap-2 rounded-xl border border-sky-300/30 bg-sky-300/10 px-4 py-3 font-bold text-sky-100 hover:bg-sky-300/20" aria-label={\`Pagar \${planName} con ATLOS en cripto\`}>\n        Pagar con ATLOS · Cripto\n      </button>\n    </div>\n  );\n}`;
source = source.slice(0, start) + replacement + source.slice(end);
const actionCall = '<PlanAction href={plan.href} action={plan.action} trial={plan.name === \'Trial\'}/>';
const actionCallNew = '<PlanAction href={plan.href} action={plan.action} trial={plan.name === \'Trial\'} planName={plan.name} amount={plan.name === \'Premium\' ? 4.99 : 8.99}/>';
if (!source.includes(actionCall)) throw new Error('PlanAction invocation not found');
source = source.replace(actionCall, actionCallNew);
const oldCopy = 'Los enlaces de Mercado Pago abren el checkout de cada plan. El importe y la moneda serán los configurados en ese enlace; un enlace único no cambia automáticamente a la moneda local de cada país. En esta modalidad, los pagos y la activación del plan se verifican manualmente; Hypercloud no actualiza automáticamente los límites de cuentas.';
const currentCopy = 'Los enlaces de Mercado Pago abren el checkout de cada plan. El importe y la moneda serán los configurados en ese enlace; un enlace único no cambia automáticamente a la moneda local de cada país. El pago y la asignación del plan se verifican manualmente antes de aumentar el límite. Las cuotas de cada proveedor siguen aplicando; el espacio se agrega solo dentro de tu cuenta, no se comparte entre usuarios.';
const newCopy = 'Mercado Pago conserva sus enlaces actuales. ATLOS acepta pagos cripto internacionales con suscripción mensual en USD; la recurrencia la administra ATLOS. Hypercloud verifica manualmente el pago y asigna el plan; las cuotas y condiciones de cada proveedor siguen aplicando, y el espacio se agrega solo dentro de tu cuenta, no se comparte entre usuarios.';
if (source.includes(oldCopy)) source = source.replace(oldCopy, newCopy);
else if (source.includes(currentCopy)) source = source.replace(currentCopy, newCopy);
else throw new Error('Plan payment disclosure not found');
fs.writeFileSync(file, source);
const htmlFile = 'frontend/index.html';
let html = fs.readFileSync(htmlFile, 'utf8');
const script = '<script async src="https://atlos.io/packages/app/atlos.js"></script>';
if (!html.includes(script)) {
  if (!html.includes('</body>')) throw new Error('HTML body close tag not found');
  html = html.replace('</body>', `${script}\n</body>`);
  fs.writeFileSync(htmlFile, html);
}
console.log('ATLOS monthly crypto checkout patch applied');

