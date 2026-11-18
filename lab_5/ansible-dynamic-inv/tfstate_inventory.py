#!/usr/bin/env python3
import json
import os
import sys

TFSTATE_PATH = os.path.expanduser("~/terraform-inv/terraform.tfstate")

def get_inventory():
    hosts = []
    hostvars = {}

    if os.path.exists(TFSTATE_PATH):
        with open(TFSTATE_PATH, "r", encoding="utf-8") as f:
            state = json.load(f)

        for res in state.get("resources", []):
            if res.get("type") == "yandex_compute_instance":
                for inst in res.get("instances", []):
                    attrs = inst.get("attributes", {})
                    name = attrs.get("name")
                    net = attrs.get("network_interface", [])
                    if name and net:
                        ip = net[0].get("nat_ip_address") or net[0].get("ip_address")
                        hosts.append(name)
                        hostvars[name] = {
                            "ansible_host": ip,
                            "ansible_user": "ubuntu"
                        }

    return {
        "yc_tf_vms": {"hosts": hosts},
        "_meta": {"hostvars": hostvars}
    }

if __name__ == "__main__":
    inv = get_inventory()
    if len(sys.argv) == 2 and sys.argv[1] == "--list":
        print(json.dumps(inv, indent=2))
    elif len(sys.argv) == 3 and sys.argv[1] == "--host":
        print(json.dumps(inv["_meta"]["hostvars"].get(sys.argv[2], {}), indent=2))
