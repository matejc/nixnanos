#! /usr/bin/env nix-shell
#! nix-shell -i bash -p jq curl

echo '{'
curl -s https://storage.googleapis.com/packagehub/manifest.json | jq -r 'to_entries[] | "  \"\(.key)\" = fetchurl rec { name = \"\(.key)\"; url = \"https://storage.googleapis.com/packagehub/${name}.tar.gz\"; sha256: \"\(.value.sha256)\"; };"'
echo '}'
