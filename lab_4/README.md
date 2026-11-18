# Домашнее задание: Первичная настройка хостов и развёртывание WordPress с помощью ролей Ansible

**Цель работы:** выполнить первичную настройку облачных хостов `wp-app-1` и `wp-app-2`, развёрнутых с помощью Terraform в Yandex Cloud, используя модульный подход и роли Ansible; настроить подключение WordPress к управляемому кластеру базы данных MySQL и проверить работу сайта через сетевой балансировщик нагрузки (Network Load Balancer).

---

## 1. Архитектура решения

Инфраструктура состоит из двух веб-серверов приложений за сетевым балансировщиком нагрузки (L4 NLB) и общего управляемого кластера базы данных **Managed Service for MySQL**.

```text
                        [ Пользователь / Браузер ]
                                    │
                                    ▼  HTTP (порт 80)
                  [ Yandex Network Load Balancer ]
                          (37.230.169.189)
                         ┌──────────┴──────────┐
                         ▼                     ▼
                [ wp-app-1 (VM) ]     [ wp-app-2 (VM) ]
                 (51.250.3.213)        (62.84.119.208)
                 Nginx + PHP 8.1       Nginx + PHP 8.1
                    WordPress             WordPress
                         └──────────┬──────────┘
                                    │  MySQL + SSL (порт 3306)
                                    ▼
                 [ Yandex Managed Service for MySQL ]
             (rc1a-8u09348718qqi995.mdb.yandexcloud.net)
```

---

## 2. Структура проекта

Проект разделён на два независимых каталога: описание облачной инфраструктуры (`terraform-wp/`) и конфигурационное управление (`ansible-wp/`).

```text
.
├── terraform-wp/
│   ├── main.tf                         # VPC, подсеть, Security Group, 2 ВМ, Managed MySQL, NLB
│   └── outputs.tf                      # Вывод IP-адресов ВМ, балансировщика и FQDN кластера БД
└── ansible-wp/
    ├── ansible.cfg                     # Настройки подключения (inventory, remote_user, SSH-ключ)
    ├── inventory.ini                   # Список целевых хостов wp-app-1 и wp-app-2
    ├── site.yml                        # Главный плейбук развёртывания
    └── roles/
        ├── webserver/                  # Роль установки и настройки Nginx + PHP-FPM
        │   ├── handlers/
        │   │   └── main.yml            # Хэндлер перезагрузки Nginx
        │   ├── tasks/
        │   │   └── main.yml            # Установка пакетов, настройка виртуального хоста, рестарт служб
        │   └── templates/
        │       └── nginx-wp.conf.j2    # Шаблон конфигурации сайта Nginx
        └── wordpress/                  # Роль развёртывания и настройки WordPress
            ├── defaults/
            │   └── main.yml            # Путь установки и URL архива WordPress
            ├── tasks/
            │   └── main.yml            # Скачивание, распаковка, права доступа, генерация wp-config.php
            ├── templates/
            │   └── wp-config.php.j2    # Шаблон конфигурации подключения к Managed MySQL (с SSL)
            └── vars/
                └── main.yml            # Реквизиты подключения к БД (имя БД, пользователь, пароль, хост)
```

---

## 3. Параметры окружения и стенда

| Параметр | Значение |
| :--- | :--- |
| **Облачный провайдер** | Yandex Cloud (`ru-central1-a`) |
| **Хосты приложений** | `wp-app-1` (`51.250.3.213`), `wp-app-2` (`62.84.119.208`) — Ubuntu 22.04 LTS |
| **Кластер базы данных** | Yandex Managed MySQL 8.0 (`rc1a-8u09348718qqi995.mdb.yandexcloud.net`) |
| **Балансировщик нагрузки** | Network Load Balancer (`37.230.169.189`, TCP healthcheck на порт `80`) |
| **Веб-стек** | Nginx `1.18.0`, PHP `8.1-fpm`, `php-mysql`, WordPress (latest) |
| **Управляющий узел** | Ubuntu (VirtualBox), Fish shell, Terraform `v1.14.3`, Ansible Core |

---

## 4. Реализация конфигурации

### 4.1. Инфраструктура Terraform (`terraform-wp/main.tf` и `outputs.tf`)

Развёрнуты 10 облачных ресурсов:
* Сеть `wp-network` и подсеть `wp-subnet` (`192.168.20.0/24`).
* Группа безопасности `wp-sg` с открытыми входящими портами `22` (SSH), `80` (HTTP) и `3306` (внутренний трафик MySQL внутри подсети).
* Две виртуальные машины `wp-app-1` и `wp-app-2` (`standard-v3`, 2 vCPU, 2 ГБ RAM, 10 ГБ диск).
* Кластер `yandex_mdb_mysql_cluster` с базой данных `wordpress_db` и пользователем `wp_user`.
* Целевая группа `wp-target-group` и балансировщик `wp-load-balancer` с TCP-проверкой доступности порта `80`.

Вывод `terraform apply`:
```text
Apply complete! Resources: 10 added, 0 changed, 0 destroyed.

Outputs:

load_balancer_ip = "37.230.169.189"
mysql_host_fqdn = "rc1a-8u09348718qqi995.mdb.yandexcloud.net"
wp_app_external_ips = [
  "51.250.3.213",
  "62.84.119.208",
]
```

---

### 4.2. Конфигурация Ansible (`ansible-wp/`)

#### `ansible.cfg`
```ini
[defaults]
inventory = ./inventory.ini
remote_user = ubuntu
private_key_file = ~/.ssh/id_ed25519
host_key_checking = False
```

#### `inventory.ini`
```ini
[wp_apps]
wp-app-1 ansible_host=51.250.3.213
wp-app-2 ansible_host=62.84.119.208
```

#### `site.yml`
```yaml
---
- name: Deploy WordPress cluster behind Load Balancer
  hosts: wp_apps
  become: true
  roles:
    - webserver
    - wordpress
```

#### Роль `webserver`

* **`roles/webserver/tasks/main.yml`**:
  ```yaml
  ---
  - name: Update apt cache and install Nginx and PHP packages
    apt:
      name:
        - nginx
        - php-fpm
        - php-mysql
        - php-curl
        - php-gd
        - php-mbstring
        - php-xml
        - php-zip
      state: present
      update_cache: true

  - name: Remove default Nginx site
    file:
      path: /etc/nginx/sites-enabled/default
      state: absent
    notify: Reload Nginx

  - name: Configure Nginx virtual host for WordPress
    template:
      src: nginx-wp.conf.j2
      dest: /etc/nginx/sites-available/wordpress
    notify: Reload Nginx

  - name: Enable WordPress site in Nginx
    file:
      src: /etc/nginx/sites-available/wordpress
      dest: /etc/nginx/sites-enabled/wordpress
      state: link
    notify: Reload Nginx

  - name: Ensure Nginx and PHP-FPM are restarted
    service:
      name: "{{ item }}"
      state: restarted
    loop:
      - php8.1-fpm
      - nginx
  ```

* **`roles/webserver/handlers/main.yml`**:
  ```yaml
  ---
  - name: Reload Nginx
    service:
      name: nginx
      state: reloaded
  ```

* **`roles/webserver/templates/nginx-wp.conf.j2`**:
  ```nginx
  server {
      listen 80 default_server;
      root /var/www/wordpress;
      index index.php index.html;
      server_name _;

      location / {
          try_files $uri $uri/ /index.php?$args;
      }

      location ~ \.php$ {
          include snippets/fastcgi-php.conf;
          fastcgi_pass unix:/run/php/php8.1-fpm.sock;
      }
  }
  ```

#### Роль `wordpress`

* **`roles/wordpress/defaults/main.yml`**:
  ```yaml
  ---
  wp_install_dir: "/var/www/wordpress"
  wp_download_url: "https://wordpress.org"
  ```

* **`roles/wordpress/vars/main.yml`**:
  ```yaml
  ---
  wp_db_name: "wordpress_db"
  wp_db_user: "wp_user"
  wp_db_password: "StrongPassword123!"
  wp_db_host: "rc1a-8u09348718qqi995.mdb.yandexcloud.net"
  ```

* **`roles/wordpress/tasks/main.yml`**:
  ```yaml
  ---
  - name: Download and extract latest WordPress
    unarchive:
      src: "{{ wp_download_url }}"
      dest: /var/www/
      remote_src: true
      creates: "{{ wp_install_dir }}/index.php"

  - name: Set ownership for WordPress directory
    file:
      path: "{{ wp_install_dir }}"
      owner: www-data
      group: www-data
      recurse: true

  - name: Deploy wp-config.php from template
    template:
      src: wp-config.php.j2
      dest: "{{ wp_install_dir }}/wp-config.php"
      owner: www-data
      group: www-data
      mode: "0640"
  ```

* **`roles/wordpress/templates/wp-config.php.j2`**:
  ```php
  <?php
  define( 'DB_NAME', '{{ wp_db_name }}' );
  define( 'DB_USER', '{{ wp_db_user }}' );
  define( 'DB_PASSWORD', '{{ wp_db_password }}' );
  define( 'DB_HOST', '{{ wp_db_host }}' );
  define( 'DB_CHARSET', 'utf8' );
  define( 'DB_COLLATE', '' );
  define( 'MYSQL_CLIENT_FLAGS', MYSQLI_CLIENT_SSL );

  $table_prefix = 'wp_';
  define( 'WP_DEBUG', false );

  if ( ! defined( 'ABSPATH' ) ) {
      define( 'ABSPATH', __DIR__ . '/' );
  }
  require_once ABSPATH . 'wp-settings.php';
  ```

---

## 5. Верификация и тестирование

### 5.1. Запуск плейбука Ansible

```text
vladimir@vladimir-VirtualBox ~/ansible-wp ❯ ansible-playbook site.yml

PLAY [Deploy WordPress cluster behind Load Balancer] ***************************
...
PLAY RECAP *********************************************************************
wp-app-1                   : ok=8    changed=1    unreachable=0    failed=0    skipped=1    rescued=0    ignored=0   
wp-app-2                   : ok=8    changed=1    unreachable=0    failed=0    skipped=1    rescued=0    ignored=0   
```

### 5.2. Проверка работы через Load Balancer и завершение установки

1. При обращении по внешнему IP балансировщика (`http://37.230.169.189`) веб-серверы выполнили редирект на мастер установки `/wp-admin/install.php`.
2. Через веб-интерфейс балансировщика выполнена первоначальная установка WordPress (создан сайт **`coolsitekrdtest`** и учётная запись администратора, таблицы успешно инициализированы в кластере Managed MySQL).
3. Контрольный HTTP-запрос через балансировщик подтвердил отдачу главной страницы установленного сайта:

```text
vladimir@vladimir-VirtualBox ~/terraform-wp ❯ curl -iL http://37.230.169.189 | head -n 20
HTTP/1.1 200 OK
Server: nginx/1.18.0 (Ubuntu)
Content-Type: text/html; charset=UTF-8
Link: <http://37.230.169>; rel="https://w.org"

<!DOCTYPE html>
<html lang="ru-RU">
<head>
	<meta charset="UTF-8" />
	<meta name="viewport" content="width=device-width, initial-scale=1" />
<meta name='robots' content='noindex, nofollow' />
<title>coolsitekrdtest</title>
```

---

## 6. Особенности и решённые задачи в ходе выполнения

Используйте код с осторожностью.

    Поддержка SSL для Managed MySQL: Управляемый кластер MySQL в Yandex Cloud требует защищённого соединения,
	поэтому в шаблон wp-config.php.j2 добавлена константа MYSQL_CLIENT_FLAGS со значением MYSQLI_CLIENT_SSL.
    Настройка Healthcheck в NLB: Свежеустановленный WordPress до завершения установки отвечает кодом 302 Found 
	(редирект на install.php),	из-за чего HTTP-проверка балансировщика переводила таргеты в состояние UNHEALTHY. 
	Переключение проверки здоровья балансировщика на tcp_options (порт 80) обеспечило корректную маршрутизацию 
	трафика на обе ноды. Перевыпуск внешних IP-адресов: При недоступности отдельных подсетей из-за маршрутизации 
	провайдера публичные IP-адреса 	инстансов были оперативно перевыпущены через 
	yc compute instance remove-one-to-one-nat / add-one-to-one-nat.

## 7. Выводы

    Конфигурационное управление разделено на переиспользуемые роли Ansible (webserver и wordpress), 
	что позволяет масштабировать количество веб-серверов добавлением хостов в inventory.ini.
    Оба инстанса (wp-app-1 и wp-app-2) работают в режиме Active-Active за балансировщиком нагрузки, 
	используя единый внешний кластер базы данных Managed MySQL.
    После завершения проверок и фиксации результатов все облачные ресурсы удалены командой 
	terraform destroy для оптимизации расхода средств.

