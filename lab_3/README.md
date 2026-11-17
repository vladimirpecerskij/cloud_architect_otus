# Домашнее задание: Тестирование инфраструктурного кода на Terraform

**Цель:** написать и выполнить автоматизированные тесты для проверки инфраструктурного кода Terraform из ДЗ №1 (развёртывание тестовой среды с `frontend`, `backend`, `database`, сетью, группой безопасности и сетевым балансировщиком в Yandex Cloud).

---

## Структура проекта

```text
terraform-hw/
├── main.tf                  # Описание облачной инфраструктуры (VPC, SG, 3 ВМ, NLB)
├── outputs.tf               # Выходные параметры (IP-адреса инстансов и балансировщика)
├── README.md                # Отчёт о выполнении и тестировании
└── tests/
    └── infra.tftest.hcl     # Нативные модульные и интеграционные тесты Terraform
```

---

## 1. Архитектура тестирования

Тесты реализованы с помощью нативного фреймворка **`terraform test`** (встроен в Terraform 1.6+). Используется комбинированный подход:
1. **Модульные тесты (`command = plan`)** — проверяют корректность конфигурации, имена ресурсов, сетевые настройки, правила Security Group и выделяемые квоты (CPU/RAM/диски) без реального создания объектов в облаке.
2. **Интеграционный тест (`command = apply`)** — разворачивает реальную тестовую среду в Yandex Cloud, проверяет статус запуска ВМ (`running`), фактическую выдачу внутренних и публичных IP-адресов, инициализацию балансировщика NLB, а затем **автоматически удаляет** все созданные ресурсы на этапе `tearing down`.

### Схема тестирования

```text
Terraform-код (main.tf, outputs.tf)
        │
        ▼
tests/infra.tftest.hcl
        │
        ├── [plan]  run "validate_network"              → проверка имени сети и CIDR подсети
        ├── [plan]  run "validate_security_group"       → проверка правил SG (порты 22 и 80)
        ├── [plan]  run "validate_vms"                  → проверка имён ВМ и nat = true
        ├── [plan]  run "validate_nlb"                  → проверка порта 80 у балансировщика
        ├── [plan]  run "validate_resources_specs"      → проверка vCPU, RAM и размера дисков
        └── [apply] run "integration_deploy_and_verify" → реальное развёртывание, проверка IP/статусов и автоудаление
```

---

## 2. План работ и порядок запуска

1. Настройка зеркала провайдеров Yandex Cloud в `~/.terraformrc`.
2. Экспорт переменных аутентификации в окружение (без хранения токенов в коде):
   * Для **Bash / Zsh**:
     ```bash
     export YC_TOKEN=$(yc iam create-token)
     export YC_CLOUD_ID=$(yc config get cloud-id)
     export YC_FOLDER_ID=$(yc config get folder-id)
     ```
   * Для **Fish shell**:
     ```fish
     set -gx YC_TOKEN (yc iam create-token | tail -n 1 | string trim)
     set -gx YC_CLOUD_ID (yc config get cloud-id | string trim)
     set -gx YC_FOLDER_ID (yc config get folder-id | string trim)
     ```
3. Валидация синтаксиса конфигурации: `terraform validate`.
4. Написание 6 тестовых сценариев в `tests/infra.tftest.hcl`.
5. Запуск полного цикла тестирования: `terraform test`.
6. Контрольная проверка отсутствия оставшихся ресурсов в облаке: `yc compute instance list`.

---

## 3. Параметры окружения

| Параметр | Значение |
| :--- | :--- |
| **Версия Terraform** | `v1.14.3` (`linux_amd64`) |
| **Провайдер** | `yandex-cloud/yandex` (зеркало `terraform-mirror.yandexcloud.net`) |
| **Хост-ОС и оболочка** | Ubuntu (VirtualBox), Fish shell |
| **Cloud ID** | `b1guapctjkvac9h6i72h` |
| **Folder ID** | `b1gi63p5vpc29cv73nqa` |
| **Зона доступности** | `ru-central1-a` |

---

## 4. Конфигурация тестов

### Код файла `tests/infra.tftest.hcl`

```hcl
run "validate_network" {
  command = plan

  assert {
    condition     = yandex_vpc_subnet.hw-subnet.v4_cidr_blocks[0] == "192.168.10.0/24"
    error_message = "CIDR подсети не совпадает с ожидаемым 192.168.10.0/24"
  }

  assert {
    condition     = yandex_vpc_network.hw-network.name == "hw-network"
    error_message = "Имя сети не совпадает"
  }
}

run "validate_security_group" {
  command = plan

  assert {
    condition = anytrue([
      for rule in yandex_vpc_security_group.hw-sg.ingress :
      rule.port == 22
    ])
    error_message = "В Security Group отсутствует правило для SSH (порт 22)"
  }

  assert {
    condition = anytrue([
      for rule in yandex_vpc_security_group.hw-sg.ingress :
      rule.port == 80
    ])
    error_message = "В Security Group отсутствует правило для HTTP (порт 80)"
  }
}

run "validate_vms" {
  command = plan

  assert {
    condition     = yandex_compute_instance.frontend.name == "frontend-vm"
    error_message = "Имя frontend ВМ не совпадает"
  }

  assert {
    condition     = yandex_compute_instance.backend.name == "backend-vm"
    error_message = "Имя backend ВМ не совпадает"
  }

  assert {
    condition     = yandex_compute_instance.database.name == "database-vm"
    error_message = "Имя database ВМ не совпадает"
  }

  assert {
    condition     = yandex_compute_instance.frontend.network_interface[0].nat == true
    error_message = "У frontend ВМ не включён публичный IP"
  }

  assert {
    condition     = yandex_compute_instance.backend.network_interface[0].nat == true
    error_message = "У backend ВМ не включён публичный IP"
  }

  assert {
    condition     = yandex_compute_instance.database.network_interface[0].nat == true
    error_message = "У database ВМ не включён публичный IP"
  }
}

run "validate_nlb" {
  command = plan

  assert {
    condition = anytrue([
      for l in yandex_lb_network_load_balancer.app-nlb.listener :
      l.port == 80
    ])
    error_message = "Балансировщик не слушает порт 80"
  }
}

run "validate_resources_specs" {
  command = plan

  assert {
    condition     = yandex_compute_instance.frontend.resources[0].cores == 2 && yandex_compute_instance.frontend.resources[0].memory == 2
    error_message = "Характеристики frontend-vm не соответствуют 2 vCPU / 2 ГБ RAM"
  }

  assert {
    condition     = yandex_compute_instance.backend.resources[0].cores == 2 && yandex_compute_instance.backend.resources[0].memory == 2
    error_message = "Характеристики backend-vm не соответствуют 2 vCPU / 2 ГБ RAM"
  }

  assert {
    condition     = yandex_compute_instance.database.boot_disk[0].initialize_params[0].size == 10
    error_message = "Размер загрузочного диска database-vm должен быть 10 ГБ"
  }
}

run "integration_deploy_and_verify" {
  command = apply

  assert {
    condition     = yandex_compute_instance.frontend.status == "running"
    error_message = "Frontend ВМ не перешла в статус running"
  }

  assert {
    condition     = yandex_compute_instance.frontend.network_interface[0].nat_ip_address != ""
    error_message = "Frontend ВМ не получила внешний IP-адрес"
  }

  assert {
    condition     = yandex_compute_instance.backend.network_interface[0].ip_address != ""
    error_message = "Backend ВМ не получила внутренний IP-адрес"
  }

  assert {
    condition     = yandex_compute_instance.database.network_interface[0].ip_address != ""
    error_message = "Database ВМ не получила внутренний IP-адрес"
  }

  assert {
    condition     = length(yandex_lb_network_load_balancer.app-nlb.listener) > 0
    error_message = "Сетевой балансировщик не создал активный listener"
  }
}
```

### Сводная таблица тестов

| Тест | Режим | Что проверяет | Ключевое условие |
| :--- | :--- | :--- | :--- |
| `validate_network` | `plan` | CIDR подсети и имя VPC-сети | `v4_cidr_blocks[0] == "192.168.10.0/24"`, `name == "hw-network"` |
| `validate_security_group` | `plan` | Наличие правил SSH (22) и HTTP (80) в SG | `anytrue([for rule in ... : rule.port == 22/80])` |
| `validate_vms` | `plan` | Имена трёх ВМ и включённый NAT | `name == "*-vm"`, `network_interface[0].nat == true` |
| `validate_nlb` | `plan` | Прослушиваемый порт балансировщика | `anytrue([for l in listener : l.port == 80])` |
| `validate_resources_specs` | `plan` | Вычислительные ресурсы и размер диска | `cores == 2`, `memory == 2`, `size == 10` |
| `integration_deploy_and_verify` | `apply` | Реальное создание, статусы ВМ, выдача IP и NLB | `status == "running"`, `nat_ip_address != ""`, `ip_address != ""` |

---

## 5. Верификация и результаты

### Вывод `terraform validate`

```text
vladimir@vladimir-VirtualBox ~/terraform-hw ❯ terraform validate
Success! The configuration is valid.
```

### Вывод `terraform test`

```text
vladimir@vladimir-VirtualBox ~/terraform-hw ❯ terraform test
tests/infra.tftest.hcl... in progress
  run "validate_network"... pass
  run "validate_security_group"... pass
  run "validate_vms"... pass
  run "validate_nlb"... pass
  run "validate_resources_specs"... pass
  run "integration_deploy_and_verify"... pass
tests/infra.tftest.hcl... tearing down
tests/infra.tftest.hcl... pass

Success! 6 passed, 0 failed.
```

### Проверка очистки ресурсов после `tearing down`

```text
vladimir@vladimir-VirtualBox ~/terraform-hw ❯ yc compute instance list
+----+------+---------+--------+-------------+-------------+

| ID | NAME | ZONE ID | STATUS | EXTERNAL IP | INTERNAL IP |
+----+------+---------+--------+-------------+-------------+
```

**Интерпретация:** все 6 тестов (5 модульных и 1 интеграционный) завершились успешно. Инфраструктура корректно разворачивается в Yandex Cloud, получает сетевые адреса, проходит функциональные проверки и полностью удаляется после завершения тестирования.

---

## 6. Выводы по работе

1. **Цель достигнута:** написаны и успешно выполнены 6 тестов (модульные и интеграционный) для проверки Terraform-кода из ДЗ №1.
2. **Комбинированная стратегия тестирования:** использование `command = plan` позволяет за секунды отловить ошибки в конфигурации без затрат, а финальный блок `command = apply` подтверждает реальную работоспособность кода в API Yandex Cloud с автоматической очисткой (`tearing down`).
