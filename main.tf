terraform {
  required_providers {
    yandex = {
      source = "yandex-cloud/yandex"
    }
    local = {
      source  = "hashicorp/local"
      version = "~> 2.5"
    }
  }
  required_version = ">= 0.13"
}

provider "yandex" {
  zone = "ru-central1-a"
}

resource "yandex_vpc_network" "network" {
  name = "secinfo-net"
}

resource "yandex_vpc_subnet" "subnet" {
  name           = "secinfo-subnet"
  zone           = "ru-central1-a"
  network_id     = yandex_vpc_network.network.id
  v4_cidr_blocks = ["192.168.20.0/24"]
}

locals {
  image_id    = "fd83j4siasgfq4pi1qif" # Debian
  vm_user     = "debian"
  ssh_keyfile = "meta.txt"
}

resource "yandex_compute_instance" "app" {
  name = "bank-app"

  resources {
    cores  = 2
    memory = 4
  }

  boot_disk {
    initialize_params {
      image_id = local.image_id
      size     = 20
      type     = "network-hdd"
    }
  }

  network_interface {
    subnet_id = yandex_vpc_subnet.subnet.id
#    nat       = true
  }

  scheduling_policy {
    preemptible = true
  }

  metadata = {
    user-data = file(local.ssh_keyfile)
  }
}

resource "yandex_compute_instance" "proxy" {
  name = "bank-proxy"

  resources {
    cores  = 2
    memory = 4
  }

  boot_disk {
    initialize_params {
      image_id = local.image_id
      size     = 20
      type     = "network-hdd"
    }
  }

  network_interface {
    subnet_id = yandex_vpc_subnet.subnet.id
    nat       = true
  }

  scheduling_policy {
    preemptible = true
  }

  metadata = {
    user-data = file(local.ssh_keyfile)
  }
}

output "app_internal_ip" {
  value = yandex_compute_instance.app.network_interface[0].ip_address
}

output "proxy_internal_ip" {
  value = yandex_compute_instance.proxy.network_interface[0].ip_address
}

output "app_external_ip" {
  value = yandex_compute_instance.app.network_interface[0].nat_ip_address
}

output "proxy_external_ip" {
  value = yandex_compute_instance.proxy.network_interface[0].nat_ip_address
}

resource "local_file" "inventory" {
  filename = "ansible/hosts"
  content  = <<EOT
[app]
bank-app ansible_host=${yandex_compute_instance.app.network_interface[0].nat_ip_address} ansible_user=${local.vm_user} private_ip=${yandex_compute_instance.app.network_interface[0].ip_address}

[proxy]
bank-proxy ansible_host=${yandex_compute_instance.proxy.network_interface[0].nat_ip_address} ansible_user=${local.vm_user} private_ip=${yandex_compute_instance.proxy.network_interface[0].ip_address}
EOT
}
