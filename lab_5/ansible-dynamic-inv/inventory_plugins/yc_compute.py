from ansible.plugins.inventory import BaseInventoryPlugin, Constructable, Cacheable
from ansible.errors import AnsibleParserError
import os
import yandexcloud
from yandex.cloud.compute.v1.instance_service_pb2 import ListInstancesRequest
from yandex.cloud.compute.v1.instance_service_pb2_grpc import InstanceServiceStub

DOCUMENTATION = '''
    name: yc_compute
    plugin_type: inventory
    short_description: Yandex Cloud Compute inventory source
    description:
        - Get inventory hosts from Yandex Cloud Compute service.
    extends_documentation_fragment:
        - constructed
    options:
        plugin:
            description: Name of the plugin
            required: true
            choices: ['yc_compute']
        folders:
            description: List of folder IDs
            required: true
            type: list
'''

class InventoryModule(BaseInventoryPlugin, Constructable, Cacheable):
    NAME = 'yc_compute'

    def verify_file(self, path):
        valid = False
        if super(InventoryModule, self).verify_file(path):
            if path.endswith(('yc.yml', 'yc.yaml')):
                valid = True
        return valid

    def parse(self, inventory, loader, path, cache=True):
        super(InventoryModule, self).parse(inventory, loader, path, cache)
        self._read_config_data(path)

        token = os.environ.get('YC_TOKEN')
        if not token:
            raise AnsibleParserError('YC_TOKEN environment variable is required')

        sdk = yandexcloud.SDK(iam_token=token)
        instance_service = sdk.client(InstanceServiceStub)

        folders = self.get_option('folders')
        self.inventory.add_group('yc_cloud')

        for folder_id in folders:
            response = instance_service.List(ListInstancesRequest(folder_id=folder_id))
            for inst in response.instances:
                if inst.status == 2:  # RUNNING
                    self.inventory.add_host(inst.name, group='yc_cloud')
                    ip = ''
                    if len(inst.network_interfaces) > 0:
                        iface = inst.network_interfaces[0]
                        nat = iface.primary_v4_address.one_to_one_nat.address
                        priv = iface.primary_v4_address.address
                        ip = nat if nat else priv
                    self.inventory.set_variable(inst.name, 'ansible_host', ip)
                    self.inventory.set_variable(inst.name, 'ansible_user', 'ubuntu')
