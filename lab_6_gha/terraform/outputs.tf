output "wp_app_external_ips" {
  value = yandex_compute_instance.wp_app[*].network_interface[0].nat_ip_address
}

output "mysql_host_fqdn" {
  value = yandex_mdb_mysql_cluster.wp-mysql.host[0].fqdn
}

output "load_balancer_ip" {
  value = one([for l in yandex_lb_network_load_balancer.wp-nlb.listener : one(l.external_address_spec).address])
}
