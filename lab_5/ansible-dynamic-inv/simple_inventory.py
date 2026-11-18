#!/usr/bin/env python3
import json
import sys

inventory = {
    "webservers": {
        "hosts": ["app-1", "app-2"],
        "vars": {"ansible_user": "ubuntu"}
    },
    "_meta": {
        "hostvars": {
            "app-1": {"ansible_host": "192.168.10.11"},
            "app-2": {"ansible_host": "192.168.10.12"}
        }
    }
}

if len(sys.argv) == 2 and sys.argv[1] == "--list":
    print(json.dumps(inventory, indent=2))
elif len(sys.argv) == 3 and sys.argv[1] == "--host":
    print(json.dumps(inventory["_meta"]["hostvars"].get(sys.argv[2], {}), indent=2))
else:
    print(json.dumps({}))
