resource "random_id" "cluster_name" {
  byte_length = 6
}


resource "random_id" "username" {
  count    = var.enable_alibaba ? 1 : 0
  byte_length = 14
}


resource "random_id" "password" {
  count    = var.enable_alibaba ? 1 : 0
  byte_length = 18
}


data "alicloud_zones" main {
    count    = var.enable_alibaba ? 1 : 0
    available_resource_creation = "VSwitch"
}

resource "alicloud_key_pair" "publickey" {
  key_name   = var.ssh_key_pair_name
  public_key = file(var.ssh_public_key_path)
}


resource "alicloud_vpc" "vpc" {
  count    = var.enable_alibaba ? 1 : 0
  cidr_block = var.vpc_cidr
  name       = var.vpc_name
}


resource "alicloud_vswitch" "vswitches" {
  count    = var.enable_alibaba ? length(var.vswitch_cidrs) : 0
  vpc_id            = alicloud_vpc.vpc[count.index].id
  cidr_block        = element(var.vswitch_cidrs, count.index)
  availability_zone = lookup(data.alicloud_zones.main[count.index].zones[count.index%length(data.alicloud_zones.main[count.index].zones)], "id")
  name              = "${var.ali_name}-${random_id.cluster_name.hex}"

  depends_on = [alicloud_vpc.vpc]
}


resource "alicloud_nat_gateway" "default" {
  count    = var.enable_alibaba ? 1 : 0
  vpc_id = alicloud_vpc.vpc[count.index].id
  specification   = "Small"
  name   = "${var.ali_name}-${random_id.cluster_name.hex}"

  depends_on = [alicloud_vswitch.vswitches]
}


resource "alicloud_eip" "eip" {
  count    = var.enable_alibaba ? 1 : 0
  bandwidth = 10
}


resource "alicloud_eip_association" "eipassoc" {
  count    = var.enable_alibaba ? 1 : 0
  allocation_id = alicloud_eip.eip[count.index].id
  instance_id   = alicloud_nat_gateway.default[count.index].id
}


resource "alicloud_snat_entry" "default" {
  count    = var.enable_alibaba ? length(var.vswitch_cidrs) : 0
  snat_table_id     = alicloud_nat_gateway.default[count.index].snat_table_ids
  source_vswitch_id = element(split(",", join(",", alicloud_vswitch.vswitches.*.id)), count.index%length(split(",", join(",", alicloud_vswitch.vswitches.*.id))))
  snat_ip           = alicloud_eip.eip[count.index].ip_address
}


resource "alicloud_cs_managed_kubernetes" "ack" {
    count    = var.enable_alibaba ? 1 : 0

    name = "${var.ali_name}-${random_id.cluster_name.hex}"
    availability_zone = data.alicloud_zones.main[count.index].zones.0.id
    vswitch_ids           = [element(split(",", join(",", alicloud_vswitch.vswitches.*.id)), count.index%length(split(",", join(",", alicloud_vswitch.vswitches.*.id))))]
    new_nat_gateway = false
    worker_instance_types = [var.ali_node_type]
    worker_numbers = var.ali_node_count
    key_name = var.ssh_key_pair_name
    pod_cidr = var.ack_k8s_pod_cidr
    service_cidr = var.ack_k8s_service_cidr
    install_cloud_monitor = true
    slb_internet_enabled = true
    worker_disk_category  = var.ack_worker_system_disk_category
    worker_disk_size = var.ack_worker_system_disk_size
    worker_data_disk_size = var.ack_worker_data_disk_size
    worker_data_disk_category = var.ack_worker_data_disk_category
    cluster_network_type = var.ack_k8s_cni

    kube_config = "./kubeconfig_ack"
    
    depends_on = ["alicloud_snat_entry.default"]
}