Домашнее задание: Тестирование инфраструктурного кода на Terraform

Цель: написать тесты для тестирования кода Terraform из ДЗ1 (развёртывание тестовой среды с frontend, backend и database в Yandex Cloud).
1. Архитектура тестирования

Тесты написаны на нативном terraform test (встроен в Terraform 1.6+). Используется command = plan — тесты не создают реальных ресурсов, а проверяют конфигурацию на этапе планирования. Это быстро и не расходует квоты Yandex Cloud.

Схема:
text

Terraform-код (main.tf)
        │
        ▼
tests/infra.tftest.hcl
        │
        ├── run "validate_network"          → проверка сети и подсети
        ├── run "validate_security_group"   → проверка правил SG (22, 80)
        ├── run "validate_vms"              → проверка имён ВМ и nat = true
        └── run "validate_nlb"              → проверка порта 80 у балансировщика

2. План работ

    Установка Terraform (уже выполнена в ДЗ1).

    Настройка зеркала провайдеров в ~/.terraformrc.

    Аутентификация через переменные окружения YC_TOKEN, YC_CLOUD_ID, YC_FOLDER_ID.

    Написание тестов в tests/infra.tftest.hcl (4 блока run с assert).

    Запуск тестов: terraform test.

    Верификация: все 4 теста проходят (Success! 4 passed, 0 failed).

3. Параметры окружения
Параметр	Значение
Версия Terraform	v1.14.3 (linux_amd64)
Провайдер yandex-cloud/yandex	скачан с terraform-mirror.yandexcloud.net
Хост-ОС	Ubuntu (VirtualBox)
cloud-id	b1guapctjkvac9h6i72h
folder-id	b1gi63p5vpc29cv73nqa
Зона по умолчанию	ru-central1-a
4. Конфигурация тестов
tests/infra.tftest.hcl
hcl

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

Параметры тестов
Тест	Что проверяет	Условие
validate_network	CIDR подсети и имя сети	v4_cidr_blocks[0] == "192.168.10.0/24", name == "hw-network"
validate_security_group	Наличие правил SSH (22) и HTTP (80) в SG	anytrue([for rule in ... : rule.port == 22/80])
validate_vms	Имена трёх ВМ и nat = true	name == "*-vm", network_interface[0].nat == true
validate_nlb	Порт балансировщика	anytrue([for l in listener : l.port == 80])

    Примечание: listener в NLB — это set, поэтому используется for-выражение с anytrue, а не индексация [0].

5. Верификация
Вывод terraform validate
text

vladimir@vladimir-VirtualBox ~/terraform-hw ❯ terraform validate
Success! The configuration is valid.

Вывод terraform test
text

vladimir@vladimir-VirtualBox ~/terraform-hw ❯ terraform test
tests/infra.tftest.hcl... in progress
  run "validate_network"... pass
  run "validate_security_group"... pass
  run "validate_vms"... pass
  run "validate_nlb"... pass
tests/infra.tftest.hcl... tearing down
tests/infra.tftest.hcl... pass

Success! 4 passed, 0 failed.

Интерпретация: все 4 теста прошли. Конфигурация Terraform из ДЗ1 корректна: сеть, подсеть, Security Group, три ВМ и балансировщик описаны правильно.
6. Выводы по работе

    Цель достигнута: написаны и успешно выполнены 4 теста для Terraform-кода из ДЗ1.

    Нативный terraform test: используется встроенный механизм Terraform 1.6+ с command = plan — тесты не создают реальных ресурсов и не расходуют квоты.

    Покрытие: тесты проверяют ключевые параметры инфраструктуры — CIDR подсети, правила Security Group, имена ВМ, nat = true, порт балансировщика.

    Аутентификация: провайдер подхватывает YC_TOKEN, YC_CLOUD_ID, YC_FOLDER_ID из переменных окружения — чувствительные данные не хранятся в тестах.

    Особенности HCL: listener в NLB — set, поэтому для проверки используется for-выражение с anytrue, а не индексация [0].

    Воспроизводимость: тесты запускаются одной командой terraform test и завершаются за секунды.

