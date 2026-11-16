Домашнее задание: Подготовка базового образа VM при помощи Packer

Цель: собрать готовый образ ВМ с установленным nginx при помощи Packer в Yandex Cloud. В ходе работы отрабатываются навыки работы с Packer и Yandex Compute Engine.
1. Топология / архитектура решения

Здесь «топология» — это цепочка инструментов и ресурсов, задействованных при сборке образа:

    Хост-машина (VirtualBox, Ubuntu): установлены Yandex CLI и Packer, хранится шаблон и ключ сервисного аккаунта.

    Yandex Cloud (каталог b1gi63p5vpc29cv73nqa): целевая облачная среда, где создаётся временная ВМ и итоговый образ.

    Сервисный аккаунт packer: от его имени Packer создаёт временную ВМ, диск и образ.

    Packer + плагин yandex v1.1.3: инструмент, который по шаблону json/template.json разворачивает временную ВМ, выполняет provisioner (установка nginx), затем создаёт образ и удаляет временные ресурсы.

Схема взаимодействия:
text

Хост (Packer + template.json + key.json)
        │
        ▼
Yandex Cloud API ◄── сервисный аккаунт packer (роль editor)
        │
        ├── временная ВМ (debian-12, subnet e9bjskqc8suuhs3v4dr6, зона ru-central1-a)
        │        └── provisioner: apt-get install nginx
        ├── образ nginx-image-<timestamp> (family nginx-family)
        └── удаление ВМ и boot-диска после сборки

2. План работ

    Установка инструментов: Yandex CLI и Packer.

    Настройка Yandex CLI: yc init, проверка yc config list (cloud-id, folder-id).

    Создание сервисного аккаунта packer, назначение роли editor на каталог, выпуск ключа key.json (пункт со звёздочкой *).

    Подготовка шаблона Packer json/template.json: использование service_account_key_file вместо token, вынос в переменные folder_id, subnet_id, service_account_key_file, image_description, zone.

    Сборка образа: packer init + packer build с передачей переменных.

    Верификация: проверка созданного образа в Yandex Cloud (yc compute image list/get).

    Документирование: фиксация конфигурации и результата сборки.

    Уборка: удаление созданного образа.

3. Параметры окружения и адресное пространство
Версии инструментов
Компонент	Версия / значение
Packer	v1.11.2
Плагин hashicorp/yandex	v1.1.3
Yandex CLI	настроен, профиль активен
Хост-ОС	Ubuntu (VirtualBox)
Параметры Yandex Cloud
Параметр	Значение
cloud-id	b1guapctjkvac9h6i72h
folder-id	b1gi63p5vpc29cv73nqa
subnet-id (зона ru-central1-a)	e9bjskqc8suuhs3v4dr6
Сервисный аккаунт	packer (aje6etnt6mobh1trcppp)
Роль на каталог	editor
Ключ сервисного аккаунта	key.json (RSA_2048, id aje6s1vmhb4hautp1jre)
Исходный образ	family debian-12 (debian-12-v20261110)
Итоговый образ	nginx-image-1794821920 (id fd8a7ti0qr81rk992kob), family nginx-family
4. Конфигурация (шаблон Packer)

Ниже приведён итоговый json/template.json. В качестве инструмента сборки используется Packer с плагином Yandex.
config.pkr.hcl
hcl

packer {
  required_plugins {
    yandex = {
      version = ">= 1.1.2"
      source  = "github.com/hashicorp/yandex"
    }
  }
}

json/template.json
json

{
  "variables": {
    "folder_id": null,
    "subnet_id": null,
    "service_account_key_file": null,
    "image_description": "My custom image with nginx (default description)",
    "zone": "ru-central1-a"
  },
  "builders": [
    {
      "type": "yandex",
      "service_account_key_file": "{{user `service_account_key_file`}}",
      "folder_id": "{{user `folder_id`}}",
      "zone": "{{user `zone`}}",
      "subnet_id": "{{user `subnet_id`}}",
      "image_name": "nginx-image-{{timestamp}}",
      "image_family": "nginx-family",
      "image_description": "{{user `image_description`}}",
      "source_image_family": "debian-12",
      "ssh_username": "debian",
      "use_ipv4_nat": true
    }
  ],
  "provisioners": [
    {
      "type": "shell",
      "inline": [
        "sudo apt-get update -y",
        "sudo apt-get install -y nginx",
        "sudo systemctl enable nginx"
      ]
    }
  ]
}

    Примечание: в блоке builders используется service_account_key_file (путь к key.json), параметр token удалён. Переменная image_description позволяет задавать описание образа при сборке, не редактируя шаблон. Исходный образ — debian-12, так как debian-11 достиг EOL и его репозитории безопасности отдают 404 при установке пакетов.

5. Верификация и проверка результата
Полный вывод packer build
text

vladimir@vladimir-VirtualBox ~/otus-packer ( (master) ❯ packer build -var "folder_id=b1gi63p5vpc29cv73nqa" -var "subnet_id=e9bjskqc8suuhs3v4dr6" -var "service_account_key_file=key.json" -var "image_description=My custom nginx image for OTUS homework" json/template.json
yandex: output will be in this color.

==> yandex: Creating temporary RSA SSH key for instance...
==> yandex: Using as source image: fd82sb0vftn4qu3lk9vi (name: "debian-12-v20261110", family: "debian-12")
==> yandex: Use provided subnet id e9bjskqc8suuhs3v4dr6
==> yandex: Creating disk...
==> yandex: Creating instance...
==> yandex: Waiting for instance with id fhmuk6gjfbck18bd92s5 to become active...
    yandex: Detected instance IP: 51.250.78.159
==> yandex: Using SSH communicator to connect: 51.250.78.159
==> yandex: Waiting for SSH to become available...
==> yandex: Connected to SSH!
==> yandex: Provisioning with shell script: /tmp/packer-shell1173336205
    yandex: Hit:1 http://mirror.yandex.ru/debian bookworm InRelease
    yandex: Get:2 http://mirror.yandex.ru/debian bookworm-updates InRelease [55.4 kB]
    yandex: Get:3 http://mirror.yandex.ru/debian bookworm-backports InRelease [59.4 kB]
    yandex: Get:4 http://security.debian.org bookworm-security InRelease [34.8 kB]
    yandex: Get:5 http://mirror.yandex.ru/debian bookworm-backports/main Sources.diff/Index [63.3 kB]
    yandex: Get:6 http://mirror.yandex.ru/debian bookworm-backports/main Sources T-2026-11-15-2016.10-F-2026-11-10-1406.06.pdiff [1,289 B]
    yandex: Get:7 http://security.debian.org bookworm-security/main Sources [294 kB]
    yandex: Get:8 http://security.debian.org bookworm-security/main amd64 Packages [373 kB]
    yandex: Get:9 http://security.debian.org bookworm-security/main Translation-en [233 kB]
    yandex: Fetched 1,114 kB in 1s (1,367 kB/s)
    yandex: Reading package lists...
    yandex: Reading package lists...
    yandex: Building dependency tree...
    yandex: Reading state information...
    yandex: The following additional packages will be installed:
    yandex:   nginx-common
    yandex: Suggested packages:
    yandex:   fcgiwrap nginx-doc ssl-cert
    yandex: The following NEW packages will be installed:
    yandex:   nginx nginx-common
    yandex: 0 upgraded, 2 newly installed, 0 to remove and 2 not upgraded.
    yandex: Need to get 646 kB of archives.
    yandex: After this operation, 1,707 kB of additional disk space will be used.
    yandex: Get:1 http://security.debian.org bookworm-security/main amd64 nginx-common all 1.22.1-9+deb12u10 [115 kB]
    yandex: Get:2 http://security.debian.org bookworm-security/main amd64 nginx amd64 1.22.1-9+deb12u10 [531 kB]
==> yandex: debconf: unable to initialize frontend: Dialog
==> yandex: debconf: (Dialog frontend will not work on a dumb terminal, an emacs shell buffer, or without a controlling terminal.)
==> yandex: debconf: falling back to frontend: Readline
==> yandex: debconf: unable to initialize frontend: Readline
==> yandex: (This frontend requires a controlling tty.)
==> yandex: falling back to frontend: Teletype
==> yandex: dpkg-preconfigure: unable to re-open stdin:
    yandex: Fetched 646 kB in 0s (3,612 kB/s)
    yandex: Selecting previously unselected package nginx-common.
    yandex: (Reading database ... 34808 files and directories currently installed.)
    yandex: Preparing to unpack .../nginx-common_1.22.1-9+deb12u10_all.deb ...
    yandex: Unpacking nginx-common (1.22.1-9+deb12u10) ...
    yandex: Selecting previously unselected package nginx.
    yandex: Preparing to unpack .../nginx_1.22.1-9+deb12u10_amd64.deb ...
    yandex: Unpacking nginx (1.22.1-9+deb12u10) ...
    yandex: Setting up nginx-common (1.22.1-9+deb12u10) ...
    yandex: debconf: unable to initialize frontend: Dialog
    yandex: (Dialog frontend will not work on a dumb terminal, an emacs shell buffer, or without a controlling terminal.)
    yandex: falling back to frontend: Readline
    yandex: debconf: unable to initialize frontend: Readline
    yandex: (This frontend requires a controlling tty.)
    yandex: falling back to frontend: Teletype
    yandex: Created symlink /etc/systemd/system/multi-user.target.wants/nginx.service → /lib/systemd/system/nginx.service.
    yandex: Setting up nginx (1.22.1-9+deb12u10) ...
    yandex: Upgrading binary: nginx.
==> yandex: Synchronizing state of nginx.service with SysV service script with /lib/systemd/systemd-sysv-install.
==> yandex: Executing: /lib/systemd/systemd-sysv-install enable nginx
==> yandex: Stopping instance...
==> yandex: Deleting instance...
    yandex: Instance has been deleted!
==> yandex: Creating image: nginx-image-1794821920
==> yandex: Waiting for image to complete...
==> yandex: Success image create...
==> yandex: Destroying boot disk...
    yandex: Disk has been deleted!
Build 'yandex' finished after 2 minutes 9 seconds.

==> Wait completed after 2 minutes 9 seconds

==> Builds finished. The artifacts of successful builds are:
--> yandex: A disk image was created: nginx-image-1794821920 (id: fd8a7ti0qr81rk992kob) with family name nginx-family

Интерпретация: Packer успешно создал временную ВМ из debian-12, установил nginx (пакет 1.22.1-9+deb12u10), создал образ с ID fd8a7ti0qr81rk992kob и семейством nginx-family, после чего удалил временную ВМ и boot-диск. Артефакт сборки — образ — создан.
Проверка созданного образа
bash

yc compute image list
yc compute image get fd8a7ti0qr81rk992kob

В выводе yc compute image get должно присутствовать описание My custom nginx image for OTUS homework, что подтверждает работу параметризации image_description.
Проверка прав сервисного аккаунта
bash

yc resource-manager folder list-access-bindings b1gi63p5vpc29cv73nqa

Ожидаемый результат:
text

+---------+----------------+----------------------+
| ROLE ID |  SUBJECT TYPE  |      SUBJECT ID      |
+---------+----------------+----------------------+
| editor  | serviceAccount | aje6etnt6mobh1trcppp |
+---------+----------------+----------------------+

Полный вывод packer init
text

vladimir@vladimir-VirtualBox ~/otus-packer ( (master) ❯ packer init config.pkr.hcl
Installed plugin github.com/hashicorp/yandex v1.1.3 in "/home/vladimir/.config/packer/plugins/github.com/hashicorp/yandex/packer-plugin-yandex_v1.1.3_x5.0_linux_amd64"

6. Выводы по работе

Цель достигнута: при помощи Packer собран готовый образ ВМ с установленным nginx в Yandex Compute Engine. Образ имеет ID fd8a7ti0qr81rk992kob и семейство nginx-family.

Автоматизация: сборка образа полностью воспроизводима одной командой packer build с передачей переменных. Ручное создание ВМ, установка ПО и создание образа через консоль больше не требуются.

Безопасность: вместо личного IAM-токена используется отдельный сервисный аккаунт packer с ролью editor на каталог и ключом key.json (параметр token из шаблона удалён). Это соответствует практике наименьших привилегий и позволяет отзывать доступ, не затрагивая личный аккаунт.

Параметризация: шаблон не требует редактирования под каждую сборку — folder_id, subnet_id, service_account_key_file, image_description и zone передаются через -var. Это упрощает повторное использование шаблона в разных каталогах и зонах.

Устойчивость к EOL: переход с debian-11 на debian-12 после ошибок 404 в репозиториях безопасности показал важность актуальности исходного образа при сборке.

Уборка ресурсов: после проверки образ удаляется командой yc compute image delete fd8a7ti0qr81rk992kob, чтобы не расходовать квоту облака.
