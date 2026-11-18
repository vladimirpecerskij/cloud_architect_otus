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

resource "yandex_vpc_network" "inv-net" {
  name = "inv-net"
}

resource "yandex_vpc_subnet" "inv-subnet" {
  name           = "inv-subnet"
  zone           = "ru-central1-a"
  network_id     = yandex_vpc_network.inv-net.id
  v4_cidr_blocks = ["192.168.30.0/24"]
}

resource "yandex_vpc_security_group" "inv-sg" {
  name       = "inv-sg"
  network_id = yandex_vpc_network.inv-net.id

  ingress {
    protocol       = "TCP"
    description    = "SSH"
    v4_cidr_blocks = ["0.0.0.0/0"]
    port           = 22
  }

  egress {
    protocol       = "ANY"
    v4_cidr_blocks = ["0.0.0.0/0"]
  }
}

data "yandex_compute_image" "ubuntu" {
  family = "ubuntu-2204-lts"
}

resource "yandex_compute_instance" "node" {
  count       = 2
  name        = "dyn-node-${count.index + 1}"
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
    subnet_id          = yandex_vpc_subnet.inv-subnet.id
    nat                = true
    security_group_ids = [yandex_vpc_security_group.inv-sg.id]
  }

  metadata = {
    ssh-keys = "ubuntu:${file("~/.ssh/id_ed25519.pub")}"
  }
}
