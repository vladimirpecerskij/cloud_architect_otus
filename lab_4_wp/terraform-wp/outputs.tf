output "wp_app_external_ips" {
  value = yandex_compute_instance.wp_app[*].network_interface[0].nat_ip_address
}

output "load_balancer_ip" {
  value = one(one(yandex_lb_network_load_balancer.wp-nlb.listener).external_address_spec).address
}

output "mysql_host_fqdn" {
  value = yandex_mdb_mysql_cluster.wp-mysql.host[0].fqdn
}
