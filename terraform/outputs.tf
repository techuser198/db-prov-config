output "instance_name" {
  description = "The name of the database instance"
  value       = google_compute_instance.db_instance.name
}

output "instance_hostname" {
  description = "The internal hostname of the database instance"
  value       = local.hostname
}

output "instance_external_ip" {
  description = "The external IP of the database instance"
  value       = google_compute_instance.db_instance.network_interface[0].access_config[0].nat_ip
}

output "instance_internal_ip" {
  description = "The internal IP of the database instance"
  value       = google_compute_instance.db_instance.network_interface[0].network_ip
}

output "instance_zone" {
  description = "The zone where the instance is deployed"
  value       = google_compute_instance.db_instance.zone
}

output "ansible_inventory_path" {
  description = "Path to the generated Ansible inventory file"
  value       = local_file.ansible_inventory.filename
}

output "ssh_command" {
  description = "SSH command to connect to the instance"
  value       = "ssh -i ${var.ssh_private_key_path} ${var.ssh_user}@${google_compute_instance.db_instance.network_interface[0].access_config[0].nat_ip}"
}

output "connection_info" {
  description = "Complete connection information"
  value = {
    instance_name    = local.instance_name
    hostname         = local.hostname
    external_ip      = google_compute_instance.db_instance.network_interface[0].access_config[0].nat_ip
    internal_ip      = google_compute_instance.db_instance.network_interface[0].network_ip
    zone             = google_compute_instance.db_instance.zone
    ssh_command      = "ssh -i ${var.ssh_private_key_path} ${var.ssh_user}@${google_compute_instance.db_instance.network_interface[0].access_config[0].nat_ip}"
    ansible_limit    = local.instance_name
    inventory_file   = "ansible/inventory/hosts_${var.environment}_${var.customer}.yml"
  }
}
