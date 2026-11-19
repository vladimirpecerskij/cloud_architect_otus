terraform {
  backend "s3" {
    endpoints = {
      s3 = "https://yandexcloud.net"
    }
    bucket                      = "tf-state-vladimir-otus-2026"
    region                      = "ru-central1"
    key                         = "wordpress/terraform.tfstate"
    skip_region_validation      = true
    skip_credentials_validation = true
    skip_requesting_account_id  = true
    skip_s3_checksum            = true
  }
}
