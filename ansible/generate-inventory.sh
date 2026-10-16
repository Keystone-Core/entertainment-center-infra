#!/bin/sh
# Génère inventory/terraform.yml à partir de la sortie Terraform linux_hosts
set -e
cd "$(dirname "$0")"
terraform -chdir=../terraform output -json linux_hosts | python3 -c '
import json, sys
hosts = json.load(sys.stdin)
print("# Généré par generate-inventory.sh - ne pas modifier à la main")
print("---")
print("all:")
print("  children:")
print("    linux:")
print("      children:")
print("        serveurs:")
print("          hosts:")
for name in sorted(hosts):
    ip = hosts[name].split(" - ")[-1].strip()
    print(f"            {name}:")
    print(f"              ansible_host: {ip}")
' > inventory/terraform.yml
echo "Inventaire généré : inventory/terraform.yml"
