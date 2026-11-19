terraform {
  required_providers {
    yandex = {
      source = "yandex-cloud/yandex"
    }
  }
  required_version = ">= 1.6.0"
}

provider "yandex" {
  zone = "ru-central1-a"
}

resource "yandex_vpc_network" "wp-network" {
  name = "wp-network-gha"
}

resource "yandex_vpc_subnet" "wp-subnet" {
  name           = "wp-subnet-gha"
  zone           = "ru-central1-a"
  network_id     = yandex_vpc_network.wp-network.id
  v4_cidr_blocks = ["192.168.40.0/24"]
}

resource "yandex_vpc_security_group" "wp-sg" {
  name       = "wp-sg-gha"
  network_id = yandex_vpc_network.wp-network.id

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
    description    = "MySQL internal"
    v4_cidr_blocks = ["192.168.40.0/24"]
    port           = 3306
  }

  egress {
    protocol       = "ANY"
    v4_cidr_blocks = ["0.0.0.0/0"]
  }
}

data "yandex_compute_image" "ubuntu" {
  family = "ubuntu-2204-lts"
}

resource "yandex_compute_instance" "wp_app" {
  count       = 2
  name        = "wp-gha-${count.index + 1}"
  platform_id = "standard-v3"
  zone        = "ru-central1-a"

  resources {
    cores  = 2
    memory = 2
  }

  boot_disk {
    initialize_params {
      image_id = data.yandex_compute_image.ubuntu.id
      size     = 10
    }
  }

  network_interface {
    subnet_id          = yandex_vpc_subnet.wp-subnet.id
    nat                = true
    security_group_ids = [yandex_vpc_security_group.wp-sg.id]
  }

  metadata = {
    ssh-keys = "ubuntu:${file("~/.ssh/yc.pub")}"
  }
}

resource "yandex_mdb_mysql_cluster" "wp-mysql" {
  name               = "wp-mysql-gha"
  environment        = "PRESTABLE"
  network_id         = yandex_vpc_network.wp-network.id
  version            = "8.0"
  security_group_ids = [yandex_vpc_security_group.wp-sg.id]

  resources {
    resource_preset_id = "s2.micro"
    disk_type_id       = "network-hdd"
    disk_size          = 10
  }

  host {
    zone      = "ru-central1-a"
    subnet_id = yandex_vpc_subnet.wp-subnet.id
  }
}

resource "yandex_mdb_mysql_database" "wp-db" {
  cluster_id = yandex_mdb_mysql_cluster.wp-mysql.id
  name       = "wordpress_db"
}

resource "yandex_mdb_mysql_user" "wp-user" {
  cluster_id = yandex_mdb_mysql_cluster.wp-mysql.id
  name       = "wp_user"
  password   = var.db_password

  permission {
    database_name = yandex_mdb_mysql_database.wp-db.name
    roles         = ["ALL"]
  }
}

resource "yandex_lb_target_group" "wp-tg" {
  name      = "wp-tg-gha"
  region_id = "ru-central1"

  dynamic "target" {
    for_each = yandex_compute_instance.wp_app
    content {
      subnet_id = yandex_vpc_subnet.wp-subnet.id
      address   = target.value.network_interface[0].ip_address
    }
  }
}

resource "yandex_lb_network_load_balancer" "wp-nlb" {
  name = "wp-nlb-gha"

  listener {
    name = "http-listener"
    port = 80
    external_address_spec {
      ip_version = "ipv4"
    }
  }

  attached_target_group {
    target_group_id = yandex_lb_target_group.wp-tg.id

    healthcheck {
      name = "tcp-healthcheck"
      tcp_options {
        port = 80
      }
    }
  }
}
