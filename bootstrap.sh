set -euo pipefail
rm -rf /tmp/drime-bundle /tmp/drime-bundle.zip
mkdir -p /tmp/drime-bundle
base64 -d bundle.b64 > /tmp/drime-bundle.zip
unzip -q -o /tmp/drime-bundle.zip -d /tmp/drime-bundle
cp -a /tmp/drime-bundle/drime-multi-vault/. .
if [ -f overrides.b64 ]; then
  base64 -d overrides.b64 > /tmp/drime-overrides.zip
  unzip -q -o /tmp/drime-overrides.zip -d .
  echo "Overrides applied"
fi
echo "Cloud bundle extracted"
