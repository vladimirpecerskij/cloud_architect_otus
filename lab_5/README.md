# Домашнее задание №5: Настройка и использование динамических инвентори и плагинов Ansible

**Цель работы:** изучить и настроить три способа динамического формирования списка хостов в Ansible без ручного ведения статического `inventory.ini`:
1. Простейший исполняемый скрипт инвентори на Python (`simple_inventory.py`).
2. Скрипт парсинга файла состояния Terraform (`tfstate_inventory.py`).
3. Полноценный плагин инвентори для прямой интеграции с API Yandex Cloud (`yc_compute`).

---

## 1. Архитектура и структура проекта

```text
lab_5/
├── README.md                                  # Подробный отчёт о выполнении
├── terraform-inv/
│   └── main.tf                                # Инфраструктура Terraform (VPC, SG, 2 ВМ Ubuntu 22.04)
└── ansible-dynamic-inv/
    ├── ansible.cfg                            # Конфигурация Ansible (подключение плагинов)
    ├── simple_inventory.py                    # 1. Программный скрипт инвентори
    ├── tfstate_inventory.py                   # 2. Парсер файла состояния terraform.tfstate
    ├── yc.yc.yml                              # 3. Конфигурационный файл облачного плагина
    └── inventory_plugins/
        └── yc_compute.py                      # Кастомный плагин инвентори на базе Yandex Cloud gRPC SDK
```

---

## 2. Реализация и верификация трёх подходов

### 2.1. Простейший динамический инвентори (`simple_inventory.py`)

Скрипт на Python поддерживает обязательные для Ansible аргументы командной строки `--list` и `--host <hostname>`, возвращая валидную JSON-структуру с группой `webservers` и блоком оптимизации `_meta.hostvars`.

**Проверка через `ansible-inventory`:**
```text
vladimir@vladimir-VirtualBox:~/ansible-dynamic-inv$ ansible-inventory -i ./simple_inventory.py --list
{
    "_meta": {
        "hostvars": {
            "app-1": {
                "ansible_host": "192.168.10.11",
                "ansible_user": "ubuntu"
            },
            "app-2": {
                "ansible_host": "192.168.10.12",
                "ansible_user": "ubuntu"
            }
        },
        "profile": "inventory_legacy"
    },
    "all": {
        "children": [
            "ungrouped",
            "webservers"
        ]
    },
    "webservers": {
        "hosts": [
            "app-1",
            "app-2"
        ]
    }
}
```

---

### 2.2. Динамический инвентори из состояния Terraform (`tfstate_inventory.py`)

Скрипт считывает локальный JSON-файл `terraform.tfstate`, находит ресурсы типа `yandex_compute_instance` и автоматически извлекает имена виртуальных машин и их публичные IP-адреса (`nat_ip_address`), формируя группу `yc_tf_vms`.

**Проверка парсинга и доступности хостов:**
```text
vladimir@vladimir-VirtualBox:~/ansible-dynamic-inv$ ansible-inventory -i ./tfstate_inventory.py --list
{
    "_meta": {
        "hostvars": {
            "dyn-node-1": {
                "ansible_host": "51.250.4.129",
                "ansible_user": "ubuntu"
            },
            "dyn-node-2": {
                "ansible_host": "84.201.134.56",
                "ansible_user": "ubuntu"
            }
        },
        "profile": "inventory_legacy"
    },
    "all": {
        "children": [
            "ungrouped",
            "yc_tf_vms"
        ]
    },
    "yc_tf_vms": {
        "hosts": [
            "dyn-node-1",
            "dyn-node-2"
        ]
    }
}
```

---

### 2.3. Плагин инвентори для интеграции с Yandex Cloud (`yc_compute`)

Реализован плагин `inventory_plugins/yc_compute.py` (на базе `BaseInventoryPlugin` и официального `yandexcloud` SDK), который напрямую обращается к gRPC API Yandex Compute по переменной окружения `YC_TOKEN`, фильтрует активные инстансы (`RUNNING`) в указанном каталоге `b1gi63p5vpc29cv73nqa` и динамически наполняет группу `yc_cloud`.

**Построение графа инвентори и проверка связи (`ping`):**
```text
vladimir@vladimir-VirtualBox:~/ansible-dynamic-inv\$ ansible-inventory -i ./yc.yc.yml --graph
@all:
  |--@ungrouped:
  |--@yc_cloud:

  |  |--dyn-node-1
  |  |--dyn-node-2

vladimir@vladimir-VirtualBox:~/ansible-dynamic-inv\$ ansible -i ./yc.yc.yml yc_cloud -m ping
dyn-node-2 | SUCCESS => {
    "ansible_facts": {
        "discovered_interpreter_python": "/usr/bin/python3.10"
    },
    "changed": false,
    "ping": "pong"
}
dyn-node-1 | SUCCESS => {
    "ansible_facts": {
        "discovered_interpreter_python": "/usr/bin/python3.10"
    },
    "changed": false,
    "ping": "pong"
}
```

---

## 3. Сравнение реализованных подходов

| Критерий | Скрипт (`simple_inventory.py`) | Парсер стейта (`tfstate_inventory.py`) | Облачный плагин (`yc_compute`) |
| :--- | :--- | :--- | :--- |
| **Источник данных** | Статический/программный код | Локальный или удалённый `terraform.tfstate` | Прямой запрос к API Yandex Cloud |
| **Актуальность IP** | Требует правки кода | Актуально до ручных изменений в облаке | Всегда 100% актуально в реальном времени |
| **Зависимости** | Стандартный Python 3 | Стандартный Python 3 | SDK `yandexcloud` + IAM-токен (`YC_TOKEN`) |
| **Применение** | Тесты и кастомные CMDB | Связка Terraform + Ansible без доступа к API | Продакшн-инфраструктура в облаке |

---

## 4. Выводы и очистка ресурсов

* Настроены и протестированы все три механизма динамической инвентаризации в Ansible.
* Использование кастомного плагина `yc_compute` исключает рассинхронизацию инвентори при перевыпуске IP-адресов или масштабировании инстансов в Yandex Cloud.
* После завершения проверок вся тестовая облачная инфраструктура полностью удалена командой `terraform destroy`.
