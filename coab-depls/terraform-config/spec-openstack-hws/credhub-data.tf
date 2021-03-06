# openstack coordinates

data "credhub_value" "openstack_auth_url" {
  name = "/secrets/openstack_auth_url"
}

data "credhub_value" "openstack_username" {
  name = "/secrets/openstack_username"
}

data "credhub_value" "openstack_password" {
  name = "/secrets/openstack_password"
}

data "credhub_value" "openstack_region" {
  name = "/secrets/openstack_region"
}

data "credhub_value" "openstack_domain" {
  name = "/secrets/openstack_domain"
}

data "credhub_value" "openstack_tenant" {
  name = "/secrets/openstack_region"
}

data "credhub_value" "openstack_router_id" {
  name = "/secrets/openstack_router_id"
}
