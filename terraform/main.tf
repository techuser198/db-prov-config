locals {
  instance_name = "db-postgres-${var.region}-${lower(var.customer)}-${lower(var.environment)}"
  hostname      = "${local.instance_name}.c.${var.project_id}.internal"
}

resource "google_compute_firewall" "db_allow_ssh" {
  name    = "db-allow-ssh-postgres-${var.environment}-${lower(var.customer)}"
  network = "default"

  allow {
    protocol = "tcp"
    ports    = ["22"]
  }

  source_ranges = ["0.0.0.0/0"]
  target_tags   = ["database-${var.environment}"]
}

resource "google_compute_firewall" "db_allow_ports" {
  name    = "db-allow-ports-postgres-${var.environment}-${lower(var.customer)}"
  network = "default"

  allow {
    protocol = "tcp"
    ports    = ["5432"]
  }

  source_ranges = ["0.0.0.0/0"]
  target_tags   = ["database-${var.environment}"]
}

resource "google_compute_instance" "db_instance" {
  name         = local.instance_name
  machine_type = var.machine_type
  zone         = "${var.region}-a"

  hostname = local.hostname

  tags = ["database-${var.environment}", "postgres-db"]

  boot_disk {
    initialize_params {
      image = var.image
      size  = var.boot_disk_size
      type  = "pd-ssd"
    }
  }

  attached_disk {
    source      = google_compute_disk.db_data.id
    device_name = "database-data"
    mode        = "READ_WRITE"
  }

  network_interface {
    network = "default"
    access_config {
      # Ephemeral external IP
    }
  }

  metadata = {
    ssh-keys      = "${var.ssh_user}:${file(var.ssh_public_key_path)}"
    instance-name = local.instance_name
    environment   = var.environment
    customer      = var.customer
    db-type       = "postgres"
    role          = "database"
    startup-script = <<-EOF
      #!/bin/bash
      # Configure passwordless sudo for the SSH user
      if ! grep -q "^${var.ssh_user}" /etc/sudoers.d/${var.ssh_user} 2>/dev/null; then
        echo "${var.ssh_user} ALL=(ALL) NOPASSWD: ALL" > /etc/sudoers.d/${var.ssh_user}
        chmod 440 /etc/sudoers.d/${var.ssh_user}
      fi
      # Ensure user exists and is in wheel group (for RHEL/CentOS)
      if id "${var.ssh_user}" &>/dev/null; then
        usermod -aG wheel ${var.ssh_user} 2>/dev/null || true
      fi
      # Disable SELinux temporarily for database installation (can be re-enabled after)
      setenforce 0 2>/dev/null || true
      sed -i 's/^SELINUX=enforcing/SELINUX=permissive/' /etc/selinux/config 2>/dev/null || true
    EOF
  }

  labels = {
    environment = lower(var.environment)
    customer    = lower(var.customer)
    db-type     = "postgres"
    role        = "database"
    managed-by  = "terraform"
  }

  deletion_protection = var.environment == "prod" ? true : false

  provisioner "remote-exec" {
    inline = ["echo 'Instance is ready for configuration'"]

    connection {
      type        = "ssh"
      user        = var.ssh_user
      private_key = file(var.ssh_private_key_path)
      host        = self.network_interface[0].access_config[0].nat_ip
      timeout     = "5m"
    }
  }

  lifecycle {
    ignore_changes = [
      metadata["ssh-keys"],
    ]
  }
}

resource "google_compute_disk" "db_data" {
  name = "${local.instance_name}-data"
  type = "pd-ssd"
  zone = "${var.region}-a"
  size = var.data_disk_size

  labels = {
    environment = lower(var.environment)
    customer    = lower(var.customer)
    db-type     = "postgres"
    role        = "database-data"
    managed-by  = "terraform"
  }
}

resource "local_file" "ansible_inventory" {
  content = templatefile("${path.module}/templates/inventory.tpl", {
    instance_name        = local.instance_name
    hostname             = local.hostname
    instance_ip          = google_compute_instance.db_instance.network_interface[0].access_config[0].nat_ip
    instance_internal_ip = google_compute_instance.db_instance.network_interface[0].network_ip
    zone                 = google_compute_instance.db_instance.zone
    region               = var.region
    environment          = var.environment
    customer             = var.customer
    ssh_user             = var.ssh_user
    ssh_private_key_path = var.ssh_private_key_path
    project_id           = var.project_id
  })

  filename = "${path.module}/../ansible/inventory/hosts_${var.environment}_${var.customer}.yml"

  depends_on = [google_compute_instance.db_instance]
}
