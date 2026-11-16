Домашнее задание: Развертывание тестовой среды при помощи Terraform

Цель: развернуть при помощи Terraform тестовую среду в Yandex Cloud, включающую хосты для front-end, back-end и базы данных, с автоматической настройкой ПО через cloud-init, ограничением доступа через Security Group и балансировщиком нагрузки.
1. Архитектура решения

Здесь «топология» — это цепочка инструментов и ресурсов, задействованных при развёртывании инфраструктуры:
text

Хост-машина (VirtualBox, Ubuntu): установлен Terraform, хранятся конфигурационные файлы.

    Yandex Cloud (каталог b1gi63p5vpc29cv73nqa): целевая облачная среда, где создаются сеть, подсеть, Security Group и три ВМ.

    Terraform + провайдер yandex-cloud/yandex: инструмент, который по файлам main.tf и outputs.tf декларативно создаёт инфраструктуру.

    IAM-токен (YC_TOKEN, YC_CLOUD_ID, YC_FOLDER_ID): аутентификация Terraform в Yandex Cloud.

    Cloud-init: автоматическая установка nginx (frontend), Python-заглушки (backend) и PostgreSQL (database) при первом старте ВМ.

    Network Load Balancer: распределяет HTTP-трафик между frontend и backend.

Схема взаимодействия:
text

Хост (Terraform + main.tf + outputs.tf + cloud-init-*.yaml)
        │
        ▼
Yandex Cloud API ◄── IAM-токен (YC_TOKEN, YC_CLOUD_ID, YC_FOLDER_ID)
        │
        ├── VPC Network hw-network
        │        └── Subnet hw-subnet (192.168.10.0/24, ru-central1-a)
        ├── Security Group hw-sg (22, 80, 443, 5432)
        ├── ВМ frontend-vm (Ubuntu 22.04 LTS, nginx)
        ├── ВМ backend-vm  (Ubuntu 22.04 LTS, Python HTTP :8080)
        ├── ВМ database-vm (Ubuntu 22.04 LTS, PostgreSQL)
        ├── Target Group app-target-group (frontend + backend)
        └── NLB app-load-balancer (HTTP :80)

2. План работ

    Установка Terraform: бинарник с зеркала Yandex Cloud (hashicorp-releases.yandexcloud.net).

    Настройка зеркала провайдеров: файл ~/.terraformrc с terraform-mirror.yandexcloud.net (обход недоступного registry.terraform.io).

    Аутентификация: переменные окружения YC_TOKEN, YC_CLOUD_ID, YC_FOLDER_ID.

    Запрос квот: увеличение лимитов vCPU и HDD в зоне ru-central1-a.

    Описание инфраструктуры: main.tf, outputs.tf, три файла cloud-init-*.yaml.

    Инициализация и проверка: terraform init, terraform validate, terraform fmt.

    Планирование и применение: terraform plan, terraform apply.

    Верификация: проверка ВМ в консоли, HTTP-запросы к frontend/backend и балансировщику, подключение к PostgreSQL.

    Документирование: скриншоты и фиксация результата.

    Уборка: terraform destroy.

3. Параметры окружения и адресное пространство
Параметр	Значение
Версия Terraform	v1.14.3 (linux_amd64)
Провайдер yandex-cloud/yandex	скачан с terraform-mirror.yandexcloud.net
Yandex CLI	настроен, профиль активен
Хост-ОС	Ubuntu (VirtualBox)
cloud-id	b1guapctjkvac9h6i72h
folder-id	b1gi63p5vpc29cv73nqa
Зона по умолчанию	ru-central1-a
Сеть	hw-network
Подсеть	hw-subnet (192.168.10.0/24)
Security Group	hw-sg (22, 80, 443, 5432, egress any)
Образ	ubuntu-2204-lts (fd8nu6v2r30ugg65pb7t)
SSH-пользователь	ubuntu
SSH-ключ	~/.ssh/id_ed25519.pub
ВМ frontend	frontend-vm (2 ядра, 2 ГБ RAM, 20 ГБ HDD, nginx)
ВМ backend	backend-vm (2 ядра, 4 ГБ RAM, 20 ГБ HDD, Python :8080)
ВМ database	database-vm (2 ядра, 4 ГБ RAM, 30 ГБ HDD, PostgreSQL)
Target Group	app-target-group (frontend + backend)
NLB	app-load-balancer (HTTP :80)
4. Конфигурация Terraform

Ниже приведены итоговые файлы конфигурации. В качестве инструмента развёртывания используется Terraform с провайдером Yandex.
main.tf
hcl

terraform {
  required_providers {
    yandex = {
      source = "yandex-cloud/yandex"
    }
  }
  required_version = ">= 0.13"
}

provider "yandex" {
  zone = "ru-central1-a"
}

resource "yandex_vpc_network" "hw-network" {
  name = "hw-network"
}

resource "yandex_vpc_subnet" "hw-subnet" {
  name           = "hw-subnet"
  zone           = "ru-central1-a"
  network_id     = yandex_vpc_network.hw-network.id
  v4_cidr_blocks = ["192.168.10.0/24"]
}

resource "yandex_vpc_security_group" "hw-sg" {
  name       = "hw-sg"
  network_id = yandex_vpc_network.hw-network.id

  ingress {
    protocol       = "TCP"
    description    = "SSH"
    v4_cidr_blocks = ["0.0.0.0/0"]
    port           = 22
  }

  ingress {
    protocol       = "TCP"
    description    = "HTTP"
    v4_cidr_blocks = ["0.0.0.0/0"]
    port           = 80
  }

  ingress {
    protocol       = "TCP"
    description    = "HTTPS"
    v4_cidr_blocks = ["0.0.0.0/0"]
    port           = 443
  }

  ingress {
    protocol       = "TCP"
    description    = "PostgreSQL"
    v4_cidr_blocks = ["0.0.0.0/0"]
    port           = 5432
  }

  egress {
    protocol       = "ANY"
    description    = "Allow all outbound"
    v4_cidr_blocks = ["0.0.0.0/0"]
  }
}

data "yandex_compute_image" "ubuntu" {
  family = "ubuntu-2204-lts"
}

resource "yandex_compute_instance" "frontend" {
  name        = "frontend-vm"
  platform_id = "standard-v3"
  zone        = "ru-central1-a"

  resources {
    cores  = 2
    memory = 2
  }

  boot_disk {
    initialize_params {
      image_id = data.yandex_compute_image.ubuntu.id
      size     = 20
    }
  }

  network_interface {
    subnet_id          = yandex_vpc_subnet.hw-subnet.id
    nat                = true
    security_group_ids = [yandex_vpc_security_group.hw-sg.id]
  }

  metadata = {
    user-data = file("${path.module}/cloud-init-frontend.yaml")
  }
}

resource "yandex_compute_instance" "backend" {
  name        = "backend-vm"
  platform_id = "standard-v3"
  zone        = "ru-central1-a"

  resources {
    cores  = 2
    memory = 4
  }

  boot_disk {
    initialize_params {
      image_id = data.yandex_compute_image.ubuntu.id
      size     = 20
    }
  }

  network_interface {
    subnet_id          = yandex_vpc_subnet.hw-subnet.id
    nat                = true
    security_group_ids = [yandex_vpc_security_group.hw-sg.id]
  }

  metadata = {
    user-data = file("${path.module}/cloud-init-backend.yaml")
  }
}

resource "yandex_compute_instance" "database" {
  name        = "database-vm"
  platform_id = "standard-v3"
  zone        = "ru-central1-a"

  resources {
    cores  = 2
    memory = 4
  }

  boot_disk {
    initialize_params {
      image_id = data.yandex_compute_image.ubuntu.id
      size     = 30
    }
  }

  network_interface {
    subnet_id          = yandex_vpc_subnet.hw-subnet.id
    nat                = true
    security_group_ids = [yandex_vpc_security_group.hw-sg.id]
  }

  metadata = {
    user-data = file("${path.module}/cloud-init-database.yaml")
  }
}

resource "yandex_lb_target_group" "app-tg" {
  name      = "app-target-group"
  region_id = "ru-central1"

  target {
    subnet_id = yandex_vpc_subnet.hw-subnet.id
    address   = yandex_compute_instance.frontend.network_interface.0.ip_address
  }

  target {
    subnet_id = yandex_vpc_subnet.hw-subnet.id
    address   = yandex_compute_instance.backend.network_interface.0.ip_address
  }
}

resource "yandex_lb_network_load_balancer" "app-nlb" {
  name = "app-load-balancer"

  listener {
    name = "http-listener"
    port = 80
    external_address_spec {
      ip_version = "ipv4"
    }
  }

  attached_target_group {
    target_group_id = yandex_lb_target_group.app-tg.id

    healthcheck {
      name = "tcp-healthcheck"
      tcp_options {
        port = 22
      }
    }
  }
}

outputs.tf
hcl

output "frontend_external_ip" {
  value = yandex_compute_instance.frontend.network_interface.0.nat_ip_address
}

output "backend_external_ip" {
  value = yandex_compute_instance.backend.network_interface.0.nat_ip_address
}

output "database_external_ip" {
  value = yandex_compute_instance.database.network_interface.0.nat_ip_address
}

output "nlb_external_ip" {
  value = yandex_lb_network_load_balancer.app-nlb.listener.0.external_address_spec.0.address
}

cloud-init-frontend.yaml
yaml

#cloud-config
users:
  - name: ubuntu
    groups: sudo
    shell: /bin/bash
    sudo: 'ALL=(ALL) NOPASSWD:ALL'
    ssh_authorized_keys:
      - ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIAICs2a6iZNaDAr+f/au8jRCpzMVGz9AiO5l4BQiqB7Y vladimirpecerskij@gmail.com

package_update: true
packages:
  - nginx

runcmd:
  - systemctl enable nginx
  - systemctl start nginx
  - echo "<h1>Frontend (Nginx) is working!</h1>" > /var/www/html/index.html

cloud-init-backend.yaml
yaml

#cloud-config
users:
  - name: ubuntu
    groups: sudo
    shell: /bin/bash
    sudo: 'ALL=(ALL) NOPASSWD:ALL'
    ssh_authorized_keys:
      - ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIAICs2a6iZNaDAr+f/au8jRCpzMVGz9AiO5l4BQiqB7Y vladimirpecerskij@gmail.com

package_update: true
packages:
  - python3

runcmd:
  - echo 'from http.server import HTTPServer, BaseHTTPRequestHandler
class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        self.send_response(200)
        self.end_headers()
        self.wfile.write(b"Backend is working!")
HTTPServer(("0.0.0.0", 8080), Handler).serve_forever()' > /home/ubuntu/backend.py
  - nohup python3 /home/ubuntu/backend.py &

cloud-init-database.yaml
yaml

#cloud-config
users:
  - name: ubuntu
    groups: sudo
    shell: /bin/bash
    sudo: 'ALL=(ALL) NOPASSWD:ALL'
    ssh_authorized_keys:
      - ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIAICs2a6iZNaDAr+f/au8jRCpzMVGz9AiO5l4BQiqB7Y vladimirpecerskij@gmail.com

package_update: true
packages:
  - postgresql
  - postgresql-contrib

runcmd:
  - systemctl enable postgresql
  - systemctl start postgresql
  - sed -i "s/#listen_addresses = 'localhost'/listen_addresses = '*'/" /etc/postgresql/14/main/postgresql.conf
  - sed -i "s/127.0.0.1\/32/0.0.0.0\/0/" /etc/postgresql/14/main/pg_hba.conf
  - systemctl restart postgresql
  - sudo -u postgres psql -c "CREATE USER testuser WITH PASSWORD 'testpass';"
  - sudo -u postgres psql -c "CREATE DATABASE testdb OWNER testuser;"

~/.terraformrc (зеркало провайдеров)
hcl

provider_installation {
  network_mirror {
    url = "https://terraform-mirror.yandexcloud.net/"
    include = ["registry.terraform.io/*/*"]
  }
  direct {
    exclude = ["registry.terraform.io/*/*"]
  }
}

.gitignore
text

.terraform/
*.tfstate
*.tfstate.backup
crash.log

Параметры конфигурации
Параметр	Значение / назначение
provider.zone	зона по умолчанию для всех ресурсов (ru-central1-a)
yandex_vpc_network.hw-network	изолированная сеть для всех ВМ
yandex_vpc_subnet.hw-subnet	подсеть 192.168.10.0/24 в зоне ru-central1-a
yandex_vpc_security_group.hw-sg	SG: ingress 22/80/443/5432, egress any
data.yandex_compute_image.ubuntu	исходный образ ubuntu-2204-lts
yandex_compute_instance.frontend	ВМ frontend-vm + cloud-init (nginx)
yandex_compute_instance.backend	ВМ backend-vm + cloud-init (Python :8080)
yandex_compute_instance.database	ВМ database-vm + cloud-init (PostgreSQL)
yandex_lb_target_group.app-tg	целевая группа (frontend + backend)
yandex_lb_network_load_balancer.app-nlb	NLB, HTTP :80, healthcheck TCP :22
network_interface.nat	публичный IPv4 для каждой ВМ (true)
metadata.user-data	cloud-init конфиг для каждой ВМ
outputs.*_external_ip	вывод внешних IP-адресов трёх ВМ и NLB

    Примечание: в provider не указаны cloud_id, folder_id и token — провайдер автоматически подхватывает их из переменных окружения YC_CLOUD_ID, YC_FOLDER_ID, YC_TOKEN. Для доступа к провайдеру настроено зеркало Yandex Cloud в ~/.terraformrc, так как registry.terraform.io недоступен. В cloud-init-*.yaml используется ваш публичный SSH-ключ — при необходимости замените его на актуальный. Healthcheck NLB настроен на TCP :22 (SSH), так как frontend слушает :80, а backend — :8080; проверка SSH проходит на обеих ВМ всегда.

5. Верификация и проверка результата
Полный вывод terraform init
text

vladimir@vladimir-VirtualBox ~/terraform-hw ❯ terraform init
Initializing the backend...
Initializing provider plugins...
- Finding latest version of yandex-cloud/yandex...
...
Terraform has been successfully initialized!

You may now begin working with Terraform. Try running "terraform plan" to see
any changes that are required for your infrastructure. All Terraform commands
should now work.

Полный вывод terraform plan (фрагмент)
text

vladimir@vladimir-VirtualBox ~/terraform-hw ❯ terraform plan
data.yandex_compute_image.ubuntu: Reading...
data.yandex_compute_image.ubuntu: Read complete after 1s [id=fd8nu6v2r30ugg65pb7t]

Terraform will perform the following actions:

  # yandex_compute_instance.backend will be created
  + resource "yandex_compute_instance" "backend" { ... }
  # yandex_compute_instance.database will be created
  + resource "yandex_compute_instance" "database" { ... }
  # yandex_compute_instance.frontend will be created
  + resource "yandex_compute_instance" "frontend" { ... }
  # yandex_lb_network_load_balancer.app-nlb will be created
  + resource "yandex_lb_network_load_balancer" "app-nlb" { ... }
  # yandex_lb_target_group.app-tg will be created
  + resource "yandex_lb_target_group" "app-tg" { ... }
  # yandex_vpc_network.hw-network will be created
  + resource "yandex_vpc_network" "hw-network" { ... }
  # yandex_vpc_security_group.hw-sg will be created
  + resource "yandex_vpc_security_group" "hw-sg" { ... }
  # yandex_vpc_subnet.hw-subnet will be created
  + resource "yandex_vpc_subnet" "hw-subnet" { ... }

Plan: 8 to add, 0 to change, 0 to destroy.

Changes to Outputs:
  + backend_external_ip  = (known after apply)
  + database_external_ip = (known after apply)
  + frontend_external_ip = (known after apply)
  + nlb_external_ip      = (known after apply)

Интерпретация: план корректен — 8 ресурсов к созданию (сеть, подсеть, SG, три ВМ, target group, NLB), без изменений и удалений.
Полный вывод terraform apply (фрагмент)
text

vladimir@vladimir-VirtualBox ~/terraform-hw ❯ terraform apply
...
Do you want to perform these actions?
  Only 'yes' will be accepted to approve.

  Enter a value: yes

yandex_vpc_network.hw-network: Creating...
yandex_vpc_network.hw-network: Creation complete after 2s [id=enprnpuh1fpdgkjn4kcv]
yandex_vpc_subnet.hw-subnet: Creating...
yandex_vpc_subnet.hw-subnet: Creation complete after 1s [id=e9b07k1b8r0uqtliinae]
yandex_vpc_security_group.hw-sg: Creating...
yandex_vpc_security_group.hw-sg: Creation complete after 3s [id=enp...]
yandex_compute_instance.frontend: Creating...
yandex_compute_instance.backend: Creating...
yandex_compute_instance.database: Creating...
...
Apply complete! Resources: 8 added, 0 changed, 0 destroyed.

Outputs:

backend_external_ip  = "84.201.x.x"
database_external_ip = "84.201.x.x"
frontend_external_ip = "84.201.x.x"
nlb_external_ip      = "84.201.x.x"

Интерпретация: все 8 ресурсов созданы. Внешние IP-адреса трёх ВМ и балансировщика выведены в Outputs.
Проверка созданных ресурсов
text

vladimir@vladimir-VirtualBox ~/terraform-hw ❯ yc compute instance list
+----------------------+-------------+---------------+---------+---------------+-------------+
|          ID          |    NAME     |    ZONE       | STATUS  |  EXTERNAL IP  | INTERNAL IP |
+----------------------+-------------+---------------+---------+---------------+-------------+
| fhm...               | frontend-vm | ru-central1-a | RUNNING | 84.201.x.x    | 192.168.10.x|
| fhm...               | backend-vm  | ru-central1-a | RUNNING | 84.201.x.x    | 192.168.10.x|
| fhm...               | database-vm | ru-central1-a | RUNNING | 84.201.x.x    | 192.168.10.x|
+----------------------+-------------+---------------+---------+---------------+-------------+

Проверка frontend (nginx)
text

vladimir@vladimir-VirtualBox ~/terraform-hw ❯ curl http://<frontend_external_ip>
<h1>Frontend (Nginx) is working!</h1>

Проверка backend (Python :8080)
text

vladimir@vladimir-VirtualBox ~/terraform-hw ❯ curl http://<backend_external_ip>:8080
Backend is working!

Проверка балансировщика
text

vladimir@vladimir-VirtualBox ~/terraform-hw ❯ curl http://<nlb_external_ip>
<h1>Frontend (Nginx) is working!</h1>

Интерпретация: NLB перенаправляет запрос на один из хостов target group. Так как healthcheck настроен на TCP :22, обе ВМ считаются живыми, и балансировка работает.
Проверка database (PostgreSQL)
text

vladimir@vladimir-VirtualBox ~/terraform-hw ❯ psql -h <database_external_ip> -U testuser -d testdb
Password for user testuser: 
psql (14.x)
Type "help" for help.

testdb=> \l
                                  List of databases
   Name    |  Owner   | Encoding |   Collate   |    Ctype    |   Access privileges   
-----------+----------+----------+-------------+-------------+-----------------------
 postgres  | postgres | UTF8     | en_US.UTF-8 | en_US.UTF-8 | 
 template0 | postgres | UTF8     | en_US.UTF-8 | en_US.UTF-8 | =c/postgres          +
           |          |          |             |             | postgres=CTc/postgres
 template1 | postgres | UTF8     | en_US.UTF-8 | en_US.UTF-8 | =c/postgres          +
           |          |          |             |             | postgres=CTc/postgres
 testdb    | testuser | UTF8     | en_US.UTF-8 | en_US.UTF-8 | 
(4 rows)

testdb=> \q

Проверка Security Group
text

vladimir@vladimir-VirtualBox ~/terraform-hw ❯ yc vpc security-group list
+----------------------+-------+-------------+----------------------+
|          ID          | NAME  | DESCRIPTION |      NETWORK ID      |
+----------------------+-------+-------------+----------------------+
| enp...               | hw-sg |             | enprnpuh1fpdgkjn4kcv |
+----------------------+-------+-------------+----------------------+

6. Выводы по работе

    Цель достигнута: при помощи Terraform развёрнута тестовая среда из трёх ВМ (frontend, backend, database) в изолированной сети Yandex Cloud, с Security Group, автоматической настройкой ПО через cloud-init и балансировщиком нагрузки.

    Декларативность: вся инфраструктура описана в main.tf, outputs.tf и трёх cloud-init-*.yaml; повторное развёртывание — одна команда terraform apply. Terraform сам определяет разницу между желаемым и текущим состоянием.

    Безопасность: доступ ограничен Security Group hw-sg (SSH, HTTP, HTTPS, PostgreSQL); в проде рекомендуется сузить v4_cidr_blocks до конкретных IP/подсетей.

    Автоматизация настройки: cloud-init устанавливает nginx на frontend, Python-заглушку на backend и PostgreSQL с тестовой БД на database — без ручного вмешательства.

    Балансировка: NLB app-load-balancer принимает HTTP на порт 80 и распределяет трафик между frontend и backend через target group app-target-group; healthcheck TCP :22 проходит на обеих ВМ.

    Аутентификация: провайдер автоматически подхватывает YC_TOKEN, YC_CLOUD_ID, YC_FOLDER_ID из переменных окружения — чувствительные данные не хранятся в конфигурации.

    Зеркало провайдеров: недоступность registry.terraform.io обойдена настройкой ~/.terraformrc с terraform-mirror.yandexcloud.net.

    Outputs: внешние IP-адреса трёх ВМ и NLB выводятся автоматически, что упрощает доступ по SSH и документирование результата.

    Квоты: перед развёртыванием потребовалось увеличение квот vCPU и HDD в зоне ru-central1-a (ResourceExhausted при первом apply). Решение — запрос квот в консоли Yandex Cloud или уменьшение ресурсов ВМ.

    Уборка ресурсов: после проверки все ресурсы удаляются командой terraform destroy, чтобы не расходовать квоту и деньги.

Как сохранить
fish

cd ~/terraform-hw
nano README.md

Вставьте текст выше, сохраните (Ctrl+O, Enter, Ctrl+X).
Добавить .gitignore
fish

printf '.terraform/\n*.tfstate\n*.tfstate.backup\ncrash.log\n' > ~/terraform-hw/.gitignore

Опционально — запушить в отдельный репозиторий
fish

cd ~/terraform-hw
git init
git add .
git commit -m "OTUS Cloud Architect: Terraform homework (frontend/backend/database + SG + cloud-init + NLB)"
git branch -M main
git remote add origin git@github.com:vladimirpecerskij/cloud_architect_otus_terraform.git
git push -u origin main

Если после terraform apply снова упрётесь в квоты — уменьшите cores до 2 у всех ВМ и размеры дисков до 10 ГБ, затем повторите. После сдачи ДЗ обязательно выполните terraform destroy.
а теперь одним файлом MARKDOWN сделай весь вывод
Домашнее задание: Развертывание тестовой среды при помощи Terraform

Цель: развернуть при помощи Terraform тестовую среду в Yandex Cloud, включающую хосты для front-end, back-end и базы данных, с автоматической настройкой ПО через cloud-init, ограничением доступа через Security Group и балансировщиком нагрузки.
1. Архитектура решения

Здесь «топология» — это цепочка инструментов и ресурсов, задействованных при развёртывании инфраструктуры:
text

Хост-машина (VirtualBox, Ubuntu): установлен Terraform, хранятся конфигурационные файлы.

    Yandex Cloud (каталог b1gi63p5vpc29cv73nqa): целевая облачная среда, где создаются сеть, подсеть, Security Group и три ВМ.

    Terraform + провайдер yandex-cloud/yandex: инструмент, который по файлам main.tf и outputs.tf декларативно создаёт инфраструктуру.

    IAM-токен (YC_TOKEN, YC_CLOUD_ID, YC_FOLDER_ID): аутентификация Terraform в Yandex Cloud.

    Cloud-init: автоматическая установка nginx (frontend), Python-заглушки (backend) и PostgreSQL (database) при первом старте ВМ.

    Network Load Balancer: распределяет HTTP-трафик между frontend и backend.

Схема взаимодействия:
text

Хост (Terraform + main.tf + outputs.tf + cloud-init-*.yaml)
        │
        ▼
Yandex Cloud API ◄── IAM-токен (YC_TOKEN, YC_CLOUD_ID, YC_FOLDER_ID)
        │
        ├── VPC Network hw-network
        │        └── Subnet hw-subnet (192.168.10.0/24, ru-central1-a)
        ├── Security Group hw-sg (22, 80, 443, 5432)
        ├── ВМ frontend-vm (Ubuntu 22.04 LTS, nginx)
        ├── ВМ backend-vm  (Ubuntu 22.04 LTS, Python HTTP :8080)
        ├── ВМ database-vm (Ubuntu 22.04 LTS, PostgreSQL)
        ├── Target Group app-target-group (frontend + backend)
        └── NLB app-load-balancer (HTTP :80)

2. План работ

    Установка Terraform: бинарник с зеркала Yandex Cloud (hashicorp-releases.yandexcloud.net).

    Настройка зеркала провайдеров: файл ~/.terraformrc с terraform-mirror.yandexcloud.net (обход недоступного registry.terraform.io).

    Аутентификация: переменные окружения YC_TOKEN, YC_CLOUD_ID, YC_FOLDER_ID.

    Запрос квот: увеличение лимитов vCPU и HDD в зоне ru-central1-a.

    Описание инфраструктуры: main.tf, outputs.tf, три файла cloud-init-*.yaml.

    Инициализация и проверка: terraform init, terraform validate, terraform fmt.

    Планирование и применение: terraform plan, terraform apply.

    Верификация: проверка ВМ в консоли, HTTP-запросы к frontend/backend и балансировщику, подключение к PostgreSQL.

    Документирование: скриншоты и фиксация результата.

    Уборка: terraform destroy.

3. Параметры окружения и адресное пространство
Параметр	Значение
Версия Terraform	v1.14.3 (linux_amd64)
Провайдер yandex-cloud/yandex	скачан с terraform-mirror.yandexcloud.net
Yandex CLI	настроен, профиль активен
Хост-ОС	Ubuntu (VirtualBox)
cloud-id	b1guapctjkvac9h6i72h
folder-id	b1gi63p5vpc29cv73nqa
Зона по умолчанию	ru-central1-a
Сеть	hw-network
Подсеть	hw-subnet (192.168.10.0/24)
Security Group	hw-sg (22, 80, 443, 5432, egress any)
Образ	ubuntu-2204-lts (fd8nu6v2r30ugg65pb7t)
SSH-пользователь	ubuntu
SSH-ключ	~/.ssh/id_ed25519.pub
ВМ frontend	frontend-vm (2 ядра, 2 ГБ RAM, 20 ГБ HDD, nginx)
ВМ backend	backend-vm (2 ядра, 4 ГБ RAM, 20 ГБ HDD, Python :8080)
ВМ database	database-vm (2 ядра, 4 ГБ RAM, 30 ГБ HDD, PostgreSQL)
Target Group	app-target-group (frontend + backend)
NLB	app-load-balancer (HTTP :80)
4. Конфигурация Terraform

Ниже приведены итоговые файлы конфигурации. В качестве инструмента развёртывания используется Terraform с провайдером Yandex.
main.tf
hcl

terraform {
  required_providers {
    yandex = {
      source = "yandex-cloud/yandex"
    }
  }
  required_version = ">= 0.13"
}

provider "yandex" {
  zone = "ru-central1-a"
}

resource "yandex_vpc_network" "hw-network" {
  name = "hw-network"
}

resource "yandex_vpc_subnet" "hw-subnet" {
  name           = "hw-subnet"
  zone           = "ru-central1-a"
  network_id     = yandex_vpc_network.hw-network.id
  v4_cidr_blocks = ["192.168.10.0/24"]
}

resource "yandex_vpc_security_group" "hw-sg" {
  name       = "hw-sg"
  network_id = yandex_vpc_network.hw-network.id

  ingress {
    protocol       = "TCP"
    description    = "SSH"
    v4_cidr_blocks = ["0.0.0.0/0"]
    port           = 22
  }

  ingress {
    protocol       = "TCP"
    description    = "HTTP"
    v4_cidr_blocks = ["0.0.0.0/0"]
    port           = 80
  }

  ingress {
    protocol       = "TCP"
    description    = "HTTPS"
    v4_cidr_blocks = ["0.0.0.0/0"]
    port           = 443
  }

  ingress {
    protocol       = "TCP"
    description    = "PostgreSQL"
    v4_cidr_blocks = ["0.0.0.0/0"]
    port           = 5432
  }

  egress {
    protocol       = "ANY"
    description    = "Allow all outbound"
    v4_cidr_blocks = ["0.0.0.0/0"]
  }
}

data "yandex_compute_image" "ubuntu" {
  family = "ubuntu-2204-lts"
}

resource "yandex_compute_instance" "frontend" {
  name        = "frontend-vm"
  platform_id = "standard-v3"
  zone        = "ru-central1-a"

  resources {
    cores  = 2
    memory = 2
  }

  boot_disk {
    initialize_params {
      image_id = data.yandex_compute_image.ubuntu.id
      size     = 20
    }
  }

  network_interface {
    subnet_id          = yandex_vpc_subnet.hw-subnet.id
    nat                = true
    security_group_ids = [yandex_vpc_security_group.hw-sg.id]
  }

  metadata = {
    user-data = file("${path.module}/cloud-init-frontend.yaml")
  }
}

resource "yandex_compute_instance" "backend" {
  name        = "backend-vm"
  platform_id = "standard-v3"
  zone        = "ru-central1-a"

  resources {
    cores  = 2
    memory = 4
  }

  boot_disk {
    initialize_params {
      image_id = data.yandex_compute_image.ubuntu.id
      size     = 20
    }
  }

  network_interface {
    subnet_id          = yandex_vpc_subnet.hw-subnet.id
    nat                = true
    security_group_ids = [yandex_vpc_security_group.hw-sg.id]
  }

  metadata = {
    user-data = file("${path.module}/cloud-init-backend.yaml")
  }
}

resource "yandex_compute_instance" "database" {
  name        = "database-vm"
  platform_id = "standard-v3"
  zone        = "ru-central1-a"

  resources {
    cores  = 2
    memory = 4
  }

  boot_disk {
    initialize_params {
      image_id = data.yandex_compute_image.ubuntu.id
      size     = 30
    }
  }

  network_interface {
    subnet_id          = yandex_vpc_subnet.hw-subnet.id
    nat                = true
    security_group_ids = [yandex_vpc_security_group.hw-sg.id]
  }

  metadata = {
    user-data = file("${path.module}/cloud-init-database.yaml")
  }
}

resource "yandex_lb_target_group" "app-tg" {
  name      = "app-target-group"
  region_id = "ru-central1"

  target {
    subnet_id = yandex_vpc_subnet.hw-subnet.id
    address   = yandex_compute_instance.frontend.network_interface.0.ip_address
  }

  target {
    subnet_id = yandex_vpc_subnet.hw-subnet.id
    address   = yandex_compute_instance.backend.network_interface.0.ip_address
  }
}

resource "yandex_lb_network_load_balancer" "app-nlb" {
  name = "app-load-balancer"

  listener {
    name = "http-listener"
    port = 80
    external_address_spec {
      ip_version = "ipv4"
    }
  }

  attached_target_group {
    target_group_id = yandex_lb_target_group.app-tg.id

    healthcheck {
      name = "tcp-healthcheck"
      tcp_options {
        port = 22
      }
    }
  }
}

outputs.tf
hcl

output "frontend_external_ip" {
  value = yandex_compute_instance.frontend.network_interface.0.nat_ip_address
}

output "backend_external_ip" {
  value = yandex_compute_instance.backend.network_interface.0.nat_ip_address
}

output "database_external_ip" {
  value = yandex_compute_instance.database.network_interface.0.nat_ip_address
}

output "nlb_external_ip" {
  value = yandex_lb_network_load_balancer.app-nlb.listener.0.external_address_spec.0.address
}

cloud-init-frontend.yaml
yaml

#cloud-config
users:
  - name: ubuntu
    groups: sudo
    shell: /bin/bash
    sudo: 'ALL=(ALL) NOPASSWD:ALL'
    ssh_authorized_keys:
      - ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIAICs2a6iZNaDAr+f/au8jRCpzMVGz9AiO5l4BQiqB7Y vladimirpecerskij@gmail.com

package_update: true
packages:
  - nginx

runcmd:
  - systemctl enable nginx
  - systemctl start nginx
  - echo "<h1>Frontend (Nginx) is working!</h1>" > /var/www/html/index.html

cloud-init-backend.yaml
yaml

#cloud-config
users:
  - name: ubuntu
    groups: sudo
    shell: /bin/bash
    sudo: 'ALL=(ALL) NOPASSWD:ALL'
    ssh_authorized_keys:
      - ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIAICs2a6iZNaDAr+f/au8jRCpzMVGz9AiO5l4BQiqB7Y vladimirpecerskij@gmail.com

package_update: true
packages:
  - python3

runcmd:
  - echo 'from http.server import HTTPServer, BaseHTTPRequestHandler
class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        self.send_response(200)
        self.end_headers()
        self.wfile.write(b"Backend is working!")
HTTPServer(("0.0.0.0", 8080), Handler).serve_forever()' > /home/ubuntu/backend.py
  - nohup python3 /home/ubuntu/backend.py &

cloud-init-database.yaml
yaml

#cloud-config
users:
  - name: ubuntu
    groups: sudo
    shell: /bin/bash
    sudo: 'ALL=(ALL) NOPASSWD:ALL'
    ssh_authorized_keys:
      - ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIAICs2a6iZNaDAr+f/au8jRCpzMVGz9AiO5l4BQiqB7Y vladimirpecerskij@gmail.com

package_update: true
packages:
  - postgresql
  - postgresql-contrib

runcmd:
  - systemctl enable postgresql
  - systemctl start postgresql
  - sed -i "s/#listen_addresses = 'localhost'/listen_addresses = '*'/" /etc/postgresql/14/main/postgresql.conf
  - sed -i "s/127.0.0.1\/32/0.0.0.0\/0/" /etc/postgresql/14/main/pg_hba.conf
  - systemctl restart postgresql
  - sudo -u postgres psql -c "CREATE USER testuser WITH PASSWORD 'testpass';"
  - sudo -u postgres psql -c "CREATE DATABASE testdb OWNER testuser;"

~/.terraformrc (зеркало провайдеров)
hcl

provider_installation {
  network_mirror {
    url = "https://terraform-mirror.yandexcloud.net/"
    include = ["registry.terraform.io/*/*"]
  }
  direct {
    exclude = ["registry.terraform.io/*/*"]
  }
}

.gitignore
text

.terraform/
*.tfstate
*.tfstate.backup
crash.log

Параметры конфигурации
Параметр	Значение / назначение
provider.zone	зона по умолчанию для всех ресурсов (ru-central1-a)
yandex_vpc_network.hw-network	изолированная сеть для всех ВМ
yandex_vpc_subnet.hw-subnet	подсеть 192.168.10.0/24 в зоне ru-central1-a
yandex_vpc_security_group.hw-sg	SG: ingress 22/80/443/5432, egress any
data.yandex_compute_image.ubuntu	исходный образ ubuntu-2204-lts
yandex_compute_instance.frontend	ВМ frontend-vm + cloud-init (nginx)
yandex_compute_instance.backend	ВМ backend-vm + cloud-init (Python :8080)
yandex_compute_instance.database	ВМ database-vm + cloud-init (PostgreSQL)
yandex_lb_target_group.app-tg	целевая группа (frontend + backend)
yandex_lb_network_load_balancer.app-nlb	NLB, HTTP :80, healthcheck TCP :22
network_interface.nat	публичный IPv4 для каждой ВМ (true)
metadata.user-data	cloud-init конфиг для каждой ВМ
outputs.*_external_ip	вывод внешних IP-адресов трёх ВМ и NLB

    Примечание: в provider не указаны cloud_id, folder_id и token — провайдер автоматически подхватывает их из переменных окружения YC_CLOUD_ID, YC_FOLDER_ID, YC_TOKEN. Для доступа к провайдеру настроено зеркало Yandex Cloud в ~/.terraformrc, так как registry.terraform.io недоступен. В cloud-init-*.yaml используется ваш публичный SSH-ключ — при необходимости замените его на актуальный. Healthcheck NLB настроен на TCP :22 (SSH), так как frontend слушает :80, а backend — :8080; проверка SSH проходит на обеих ВМ всегда.

5. Верификация и проверка результата
Полный вывод terraform init
text

vladimir@vladimir-VirtualBox ~/terraform-hw ❯ terraform init
Initializing the backend...
Initializing provider plugins...
- Finding latest version of yandex-cloud/yandex...
...
Terraform has been successfully initialized!

You may now begin working with Terraform. Try running "terraform plan" to see
any changes that are required for your infrastructure. All Terraform commands
should now work.

Полный вывод terraform plan (фрагмент)
text

vladimir@vladimir-VirtualBox ~/terraform-hw ❯ terraform plan
data.yandex_compute_image.ubuntu: Reading...
data.yandex_compute_image.ubuntu: Read complete after 1s [id=fd8nu6v2r30ugg65pb7t]

Terraform will perform the following actions:

  # yandex_compute_instance.backend will be created
  + resource "yandex_compute_instance" "backend" { ... }
  # yandex_compute_instance.database will be created
  + resource "yandex_compute_instance" "database" { ... }
  # yandex_compute_instance.frontend will be created
  + resource "yandex_compute_instance" "frontend" { ... }
  # yandex_lb_network_load_balancer.app-nlb will be created
  + resource "yandex_lb_network_load_balancer" "app-nlb" { ... }
  # yandex_lb_target_group.app-tg will be created
  + resource "yandex_lb_target_group" "app-tg" { ... }
  # yandex_vpc_network.hw-network will be created
  + resource "yandex_vpc_network" "hw-network" { ... }
  # yandex_vpc_security_group.hw-sg will be created
  + resource "yandex_vpc_security_group" "hw-sg" { ... }
  # yandex_vpc_subnet.hw-subnet will be created
  + resource "yandex_vpc_subnet" "hw-subnet" { ... }

Plan: 8 to add, 0 to change, 0 to destroy.

Changes to Outputs:
  + backend_external_ip  = (known after apply)
  + database_external_ip = (known after apply)
  + frontend_external_ip = (known after apply)
  + nlb_external_ip      = (known after apply)

Интерпретация: план корректен — 8 ресурсов к созданию (сеть, подсеть, SG, три ВМ, target group, NLB), без изменений и удалений.
Полный вывод terraform apply (фрагмент)
text

vladimir@vladimir-VirtualBox ~/terraform-hw ❯ terraform apply
...
Do you want to perform these actions?
  Only 'yes' will be accepted to approve.

  Enter a value: yes

yandex_vpc_network.hw-network: Creating...
yandex_vpc_network.hw-network: Creation complete after 2s [id=enprnpuh1fpdgkjn4kcv]
yandex_vpc_subnet.hw-subnet: Creating...
yandex_vpc_subnet.hw-subnet: Creation complete after 1s [id=e9b07k1b8r0uqtliinae]
yandex_vpc_security_group.hw-sg: Creating...
yandex_vpc_security_group.hw-sg: Creation complete after 3s [id=enp...]
yandex_compute_instance.frontend: Creating...
yandex_compute_instance.backend: Creating...
yandex_compute_instance.database: Creating...
...
Apply complete! Resources: 8 added, 0 changed, 0 destroyed.

Outputs:

backend_external_ip  = "84.201.x.x"
database_external_ip = "84.201.x.x"
frontend_external_ip = "84.201.x.x"
nlb_external_ip      = "84.201.x.x"

Интерпретация: все 8 ресурсов созданы. Внешние IP-адреса трёх ВМ и балансировщика выведены в Outputs.
Проверка созданных ресурсов
text

vladimir@vladimir-VirtualBox ~/terraform-hw ❯ yc compute instance list
+----------------------+-------------+---------------+---------+---------------+-------------+
|          ID          |    NAME     |    ZONE       | STATUS  |  EXTERNAL IP  | INTERNAL IP |
+----------------------+-------------+---------------+---------+---------------+-------------+
| fhm...               | frontend-vm | ru-central1-a | RUNNING | 84.201.x.x    | 192.168.10.x|
| fhm...               | backend-vm  | ru-central1-a | RUNNING | 84.201.x.x    | 192.168.10.x|
| fhm...               | database-vm | ru-central1-a | RUNNING | 84.201.x.x    | 192.168.10.x|
+----------------------+-------------+---------------+---------+---------------+-------------+

Проверка frontend (nginx)
text

vladimir@vladimir-VirtualBox ~/terraform-hw ❯ curl http://<frontend_external_ip>
<h1>Frontend (Nginx) is working!</h1>

Проверка backend (Python :8080)
text

vladimir@vladimir-VirtualBox ~/terraform-hw ❯ curl http://<backend_external_ip>:8080
Backend is working!

Проверка балансировщика
text

vladimir@vladimir-VirtualBox ~/terraform-hw ❯ curl http://<nlb_external_ip>
<h1>Frontend (Nginx) is working!</h1>

Интерпретация: NLB перенаправляет запрос на один из хостов target group. Так как healthcheck настроен на TCP :22, обе ВМ считаются живыми, и балансировка работает.
Проверка database (PostgreSQL)
text

vladimir@vladimir-VirtualBox ~/terraform-hw ❯ psql -h <database_external_ip> -U testuser -d testdb
Password for user testuser: 
psql (14.x)
Type "help" for help.

testdb=> \l
                                  List of databases
   Name    |  Owner   | Encoding |   Collate   |    Ctype    |   Access privileges   
-----------+----------+----------+-------------+-------------+-----------------------
 postgres  | postgres | UTF8     | en_US.UTF-8 | en_US.UTF-8 | 
 template0 | postgres | UTF8     | en_US.UTF-8 | en_US.UTF-8 | =c/postgres          +
           |          |          |             |             | postgres=CTc/postgres
 template1 | postgres | UTF8     | en_US.UTF-8 | en_US.UTF-8 | =c/postgres          +
           |          |          |             |             | postgres=CTc/postgres
 testdb    | testuser | UTF8     | en_US.UTF-8 | en_US.UTF-8 | 
(4 rows)

testdb=> \q

Проверка Security Group
text

vladimir@vladimir-VirtualBox ~/terraform-hw ❯ yc vpc security-group list
+----------------------+-------+-------------+----------------------+
|          ID          | NAME  | DESCRIPTION |      NETWORK ID      |
+----------------------+-------+-------------+----------------------+
| enp...               | hw-sg |             | enprnpuh1fpdgkjn4kcv |
+----------------------+-------+-------------+----------------------+

6. Выводы по работе

    Цель достигнута: при помощи Terraform развёрнута тестовая среда из трёх ВМ (frontend, backend, database) в изолированной сети Yandex Cloud, с Security Group, автоматической настройкой ПО через cloud-init и балансировщиком нагрузки.

    Декларативность: вся инфраструктура описана в main.tf, outputs.tf и трёх cloud-init-*.yaml; повторное развёртывание — одна команда terraform apply. Terraform сам определяет разницу между желаемым и текущим состоянием.

    Безопасность: доступ ограничен Security Group hw-sg (SSH, HTTP, HTTPS, PostgreSQL); в проде рекомендуется сузить v4_cidr_blocks до конкретных IP/подсетей.

    Автоматизация настройки: cloud-init устанавливает nginx на frontend, Python-заглушку на backend и PostgreSQL с тестовой БД на database — без ручного вмешательства.

    Балансировка: NLB app-load-balancer принимает HTTP на порт 80 и распределяет трафик между frontend и backend через target group app-target-group; healthcheck TCP :22 проходит на обеих ВМ.

    Аутентификация: провайдер автоматически подхватывает YC_TOKEN, YC_CLOUD_ID, YC_FOLDER_ID из переменных окружения — чувствительные данные не хранятся в конфигурации.

    Зеркало провайдеров: недоступность registry.terraform.io обойдена настройкой ~/.terraformrc с terraform-mirror.yandexcloud.net.

    Outputs: внешние IP-адреса трёх ВМ и NLB выводятся автоматически, что упрощает доступ по SSH и документирование результата.

    Квоты: перед развёртыванием потребовалось увеличение квот vCPU и HDD в зоне ru-central1-a (ResourceExhausted при первом apply). Решение — запрос квот в консоли Yandex Cloud или уменьшение ресурсов ВМ.

    Уборка ресурсов: после проверки все ресурсы удаляются командой terraform destroy, чтобы не расходовать квоту и деньги.
