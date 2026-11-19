# Домашнее задание №6: Инфраструктурный пайплайн CI/CD (Terraform + Ansible) в GitHub Actions

**Цель работы:** реализовать автоматизированный инфраструктурный пайплайн для проверки, развёртывания, настройки и удаления облачной инфраструктуры в Yandex Cloud с последующей установкой веб-приложения WordPress с помощью ролей Ansible.

---

## 1. Архитектура CI/CD пайплайна

Пайплайн описан в файле `.github/workflows/deploy-wp.yml` и поддерживает два режима запуска:
* **Автоматический (`push` в ветку `main`):** выполняет инициализацию бэкенда, проверку форматирования/синтаксиса (`terraform validate`) и построение плана изменений (`terraform plan`).
* **Ручной параметризованный запуск (`workflow_dispatch`):** позволяет выбрать целевое действие с инфраструктурой (`plan`, `apply`, `destroy`).

```text
[ GitHub Repository (main) ]
            │
            ├─── push ───────────────► [ Init & Validate ] ──► [ Terraform Plan ]
            │
            └─── workflow_dispatch
                    ├── action: apply ───► [ Terraform Apply ] ──► [ Ansible Playbook ]
                    │                             │                        │
                    │                             ▼                        ▼
                    │                   [ Yandex Object Storage ]   [ wp-gha-1 / wp-gha-2 ]
                    │                    (Remote S3 tfstate)        (Nginx + PHP + WP)
                    │
                    └── action: destroy ─► [ Terraform Destroy ] ──► Очистка облака
```

---

## 2. Хранение состояния (Remote State) и управление секретами

### 2.1. Удалённый бэкенд в Yandex Object Storage (`terraform/backend.tf`)
Для сохранения состояния `terraform.tfstate` между изолированными запусками раннеров GitHub Actions настроен S3-совместимый бэкенд в **Yandex Object Storage** (`tf-state-vladimir-otus-2026`):
* Включён режим `use_path_style = true` и отключены специфичные для AWS проверки регионов и метаданных (`skip_region_validation`, `skip_credentials_validation`, `skip_requesting_account_id`, `skip_s3_checksum`).

### 2.2. Секреты репозитория (GitHub Actions Secrets)
Все чувствительные данные передаются в раннер через зашифрованные секреты репозитория:
* `YC_SERVICE_ACCOUNT_KEY` — JSON-ключ сервисного аккаунта `github-sa` (передаётся в кодировке Base64 и декодируется в `/tmp/yc-key.json` на этапе подготовки окружения).
* `YC_CLOUD_ID` и `YC_FOLDER_ID` — идентификаторы облака и рабочего каталога Yandex Cloud.
* `AWS_ACCESS_KEY_ID` и `AWS_SECRET_ACCESS_KEY` — статические ключи доступа к S3-бакету для работы бэкенда Terraform.
* `SSH_PUBLIC_KEY` и `SSH_PRIVATE_KEY` — ключевая пара для проброса в метаданные ВМ и подключения Ansible.
* `DB_PASSWORD` — пароль пользователя базы данных Managed MySQL (`TF_VAR_db_password`).

---

## 3. Структура проекта

```text
.
├── .github/
│   └── workflows/
│       └── deploy-wp.yml              # Описание стадий и шагов GitHub Actions
└── lab_6_gha/
    ├── README.md                      # Отчёт по лабораторной работе
    ├── terraform/
    │   ├── backend.tf                 # Конфигурация S3 Remote State в Yandex Cloud
    │   ├── main.tf                    # VPC, подсеть, SG, 2 ВМ, Managed MySQL 8.0, NLB
    │   ├── outputs.tf                 # Экспорт IP-адресов ВМ, балансировщика и FQDN БД
    │   └── variables.tf               # Входные переменные пайплайна
    └── ansible/
        ├── ansible.cfg                # Конфигурация Ansible
        ├── site.yml                   # Главный плейбук развёртывания
        └── roles/
            ├── webserver/             # Установка и настройка Nginx + PHP 8.1-FPM
            └── wordpress/             # Установка WordPress и настройка wp-config.php (SSL)
```

---

## 4. Этапы выполнения пайплайна

1. **Setup SSH keys & Yandex Cloud credentials:** восстановление SSH-ключей и JSON-ключа сервисного аккаунта из секретов GitHub.
2. **Terraform Init & Validate:** инициализация S3-бэкенда, проверка стиля (`terraform fmt`) и валидация манифестов (`terraform validate`).
3. **Terraform Plan:** расчёт плана изменений (создание 10 облачных ресурсов: сеть `wp-network-gha`, подсеть `192.168.40.0/24`, группа безопасности, 2 ВМ `wp-gha-1` и `wp-gha-2`, кластер `wp-mysql-gha`, целевая группа и балансировщик `wp-nlb-gha`).
4. **Terraform Apply:** развёртывание инфраструктуры в Yandex Cloud и сохранение выходных параметров в `tf_outputs.json`.
5. **Deploy WordPress with Ansible:** динамическая генерация `inventory.ini` и переменных подключения к БД на основе `tf_outputs.json`, после чего запуск `ansible-playbook site.yml` для настройки веб-серверов и WordPress.
6. **Terraform Destroy:** полное удаление созданных облачных ресурсов по завершении проверок.

---

## 5. Выводы

* Построен сквозной инфраструктурный пайплайн (IaC CI/CD), исключающий ручной запуск утилит с локальной рабочей станции.
* Использование удалённого S3-хранилища `terraform.tfstate` позволило безопасно разделять этапы планирования (`plan`), развёртывания (`apply`) и удаления (`destroy`) между независимыми запусками раннеров.
* Интеграция выводов Terraform (`terraform output -json`) с ролями Ansible обеспечила автоматическую настройку кластера WordPress без жёсткой привязки к IP-адресам.
