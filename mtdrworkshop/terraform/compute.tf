# Compute instance for app deployment (alternative to OKE)

# Get latest Oracle Linux 8 image for the compute shape
data "oci_core_images" "oracle_linux" {
  compartment_id           = var.ociCompartmentOcid
  operating_system         = "Oracle Linux"
  operating_system_version = "8"
  shape                    = "VM.Standard.E2.1"
  sort_by                  = "TIMECREATED"
  sort_order               = "DESC"
}

# Security list for compute subnet
resource "oci_core_security_list" "compute_sl" {
  compartment_id = var.ociCompartmentOcid
  vcn_id         = oci_core_vcn.okevcn.id
  display_name   = "compute-security-list"

  egress_security_rules {
    destination = "0.0.0.0/0"
    protocol    = "all"
  }

  ingress_security_rules {
    source   = "0.0.0.0/0"
    protocol = "6"
    tcp_options {
      min = 22
      max = 22
    }
  }

  ingress_security_rules {
    source   = "0.0.0.0/0"
    protocol = "6"
    tcp_options {
      min = 80
      max = 80
    }
  }

  ingress_security_rules {
    source   = "0.0.0.0/0"
    protocol = "6"
    tcp_options {
      min = 8080
      max = 8080
    }
  }
}

# Public subnet for compute instance
resource "oci_core_subnet" "compute_subnet" {
  cidr_block     = "10.0.30.0/24"
  compartment_id = var.ociCompartmentOcid
  vcn_id         = oci_core_vcn.okevcn.id
  display_name   = "ComputeSubnet"
  dns_label      = "compute"

  security_list_ids          = [oci_core_security_list.compute_sl.id]
  route_table_id             = oci_core_vcn.okevcn.default_route_table_id
  prohibit_public_ip_on_vnic = false
}

# Compute instance
resource "oci_core_instance" "app_instance" {
  availability_domain = data.oci_identity_availability_domain.ad1.name
  compartment_id      = var.ociCompartmentOcid
  display_name        = "mtdr-app-server"
  shape               = "VM.Standard.E2.1"

  source_details {
    source_type = "image"
    source_id   = data.oci_core_images.oracle_linux.images.0.id
  }

  create_vnic_details {
    subnet_id        = oci_core_subnet.compute_subnet.id
    assign_public_ip = true
  }

  metadata = {
    ssh_authorized_keys = var.ssh_public_key
    user_data = base64encode(<<-USERDATA
      #!/bin/bash
      yum install -y yum-utils
      yum-config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo
      yum install -y docker-ce docker-ce-cli containerd.io
      systemctl enable docker
      systemctl start docker
      usermod -aG docker opc
      # Open firewall ports
      firewall-cmd --permanent --add-port=80/tcp
      firewall-cmd --permanent --add-port=8080/tcp
      firewall-cmd --reload
    USERDATA
    )
  }
}

output "app_instance_public_ip" {
  value = oci_core_instance.app_instance.public_ip
}

output "app_instance_id" {
  value = oci_core_instance.app_instance.id
}
