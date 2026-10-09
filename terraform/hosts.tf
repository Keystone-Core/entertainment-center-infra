# Linux hosts from the network log (docs/10-network-log.md).
#
# Only the server network exists behind fw01 for now (10.10.20.0/24,
# untagged on vmbr1), so every host is placed there. Hosts planned for
# another VLAN use a temporary address; `planned` keeps their final one.
# To move a host once its VLAN exists, change `ip` and add the VLAN tag.
#
# The VM ID is the VLAN number followed by the last octet of the planned
# address (voip01, 10.10.20.20 -> 2020), so it never has to change.
locals {
  vms = {
    ts01 = {
      vm_id       = 1021
      description = "Tailscale subnet router"
      ip          = "10.10.20.51"
      planned     = "10.10.10.21 (VLAN 10)"
      cores       = 1
      memory      = 512
      disk        = 4
    }
    voip01 = {
      vm_id       = 2020
      description = "Asterisk IP telephony"
      ip          = "10.10.20.20"
      planned     = "10.10.20.20 (VLAN 20)"
      cores       = 1
      memory      = 1024
      disk        = 8
    }
    web01 = {
      vm_id       = 2021
      description = "LAMP web development server"
      ip          = "10.10.20.21"
      planned     = "10.10.20.21 (VLAN 20)"
      cores       = 2
      memory      = 2048
      disk        = 16
    }
    mon01 = {
      vm_id       = 2022
      description = "Netdata monitoring"
      ip          = "10.10.20.22"
      planned     = "10.10.20.22 (VLAN 20)"
      cores       = 2
      memory      = 2048
      disk        = 16
    }
    k3s01 = {
      vm_id       = 2031
      description = "Kubernetes (k3s)"
      ip          = "10.10.20.31"
      planned     = "10.10.20.31 (VLAN 20)"
      cores       = 4
      memory      = 8192
      disk        = 64
    }
    media01 = {
      vm_id       = 2040
      description = "Jellyfin, Radarr, Sonarr, Prowlarr, qBittorrent"
      ip          = "10.10.20.40"
      planned     = "10.10.20.40 (VLAN 20)"
      cores       = 4
      memory      = 4096
      disk        = 32
      media_disk  = 250
    }
    dash01 = {
      vm_id       = 2041
      description = "Homarr dashboard"
      ip          = "10.10.20.41"
      planned     = "10.10.20.41 (VLAN 20)"
      cores       = 1
      memory      = 1024
      disk        = 8
    }
    mqtt01 = {
      vm_id       = 6010
      description = "Mosquitto MQTT broker (TLS)"
      ip          = "10.10.20.61"
      planned     = "10.10.60.10 (VLAN 60)"
      cores       = 1
      memory      = 512
      disk        = 4
    }
    proxy01 = {
      vm_id       = 8010
      description = "Caddy reverse proxy (HTTPS)"
      ip          = "10.10.20.81"
      planned     = "10.10.80.10 (VLAN 80)"
      cores       = 1
      memory      = 512
      disk        = 4
    }
    game01 = {
      vm_id       = 8020
      description = "AMP game server panel"
      ip          = "10.10.20.82"
      planned     = "10.10.80.20 (VLAN 80)"
      cores       = 4
      memory      = 16384
      disk        = 100
    }
  }
}
