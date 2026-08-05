#!/usr/bin/env python3
"""Inventario dinamico do Ansible, alimentado pelo state do Terraform.

Varre infra/terraform/clients/<nome>/ (ignorando "_template"), roda
"terraform output -json" em cada pasta ja aplicada e monta o inventario
Ansible a partir dos outputs (public_ipv4, client_name).

Uso:
    ansible-playbook -i infra/ansible/inventory/terraform_inventory.py site.yml
    python3 terraform_inventory.py --list   # debug manual

Requer o binario "terraform" no PATH e cada pasta de cliente ja
inicializada/aplicada (terraform init && terraform apply).
"""
import json
import subprocess
import sys
from pathlib import Path
from typing import Optional

REPO_ROOT = Path(__file__).resolve().parents[3]
CLIENTS_DIR = REPO_ROOT / "infra" / "terraform" / "clients"
SKIP_DIRS = {"_template"}


def terraform_outputs(client_dir: Path) -> Optional[dict]:
    try:
        result = subprocess.run(
            ["terraform", f"-chdir={client_dir}", "output", "-json"],
            capture_output=True,
            text=True,
            timeout=30,
        )
    except FileNotFoundError:
        print("ERRO: binario 'terraform' nao encontrado no PATH.", file=sys.stderr)
        return None

    if result.returncode != 0:
        print(
            f"AVISO: 'terraform output' falhou em {client_dir} (ainda nao aplicado?): "
            f"{result.stderr.strip()}",
            file=sys.stderr,
        )
        return None

    try:
        raw = json.loads(result.stdout)
    except json.JSONDecodeError:
        print(f"AVISO: saida de 'terraform output -json' invalida em {client_dir}.", file=sys.stderr)
        return None

    return {key: value.get("value") for key, value in raw.items()}


def build_inventory() -> dict:
    inventory = {
        "vps_clients": {"hosts": []},
        "_meta": {"hostvars": {}},
    }

    if not CLIENTS_DIR.is_dir():
        return inventory

    for client_dir in sorted(CLIENTS_DIR.iterdir()):
        if not client_dir.is_dir() or client_dir.name in SKIP_DIRS:
            continue

        outputs = terraform_outputs(client_dir)
        if not outputs or not outputs.get("public_ipv4"):
            continue

        client_name = outputs.get("client_name", client_dir.name)
        inventory["vps_clients"]["hosts"].append(client_name)
        inventory["_meta"]["hostvars"][client_name] = {
            "ansible_host": outputs["public_ipv4"],
            "ansible_user": "root",
            "client_name": client_name,
            "public_ipv6": outputs.get("public_ipv6"),
            # ID numerico da VPS na Hostinger - usado pela role
            # hostinger_firewall para ativar o firewall neste servidor.
            "hostinger_vps_id": outputs.get("server_id"),
        }

    return inventory


def main() -> None:
    if len(sys.argv) > 1 and sys.argv[1] == "--list":
        print(json.dumps(build_inventory(), indent=2))
    elif len(sys.argv) > 2 and sys.argv[1] == "--host":
        # Hostvars ja vao em _meta no --list; Ansible so chama --host se
        # _meta nao foi fornecido, mas respondemos vazio por contrato.
        print(json.dumps({}))
    else:
        print("Uso: terraform_inventory.py --list | --host <nome>", file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    main()
