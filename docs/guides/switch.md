# Physical Switch

The team's laptops join VLAN 10 (management) through the centre's managed switch, plugged into `pve`. The switch also carries `pve`'s link to the cégep network, so the VPN depends on it too.

| Item      | Value                                                                              |
| --------- | ---------------------------------------------------------------------------------- |
| Model     | Aruba 2930F 12G PoE+ (JL693A), ArubaOS-Switch WC.16.11.0001                         |
| Name      | `minion` (planned as `sw01` in the network log)                                    |
| Access    | Serial console only, 9600 baud, 8N1, no flow control                              |
| Management address | By DHCP on the cégep network (VLAN 1); the planned `10.10.10.2` in VLAN 10 isn't set |

## Ports

| Port | VLAN | Plugged into |
| ---- | ---- | ------------ |
| 1 | 1, untagged | The cégep network (LLDP neighbour `stk-541-2`, port 3:6) |
| 2 to 5 | 10, untagged | The team's laptops |
| 11 | 1, untagged | `pve`'s `nic3` (`vmbr0`): its cégep link, the VPN and `fw01`'s WAN |
| 12 | 10, tagged | `pve`'s `nic1` (`vmbr1`), which only accepts VLAN 10, tagged |
| 6 to 10, 13 to 16 | 1, untagged | Free, on the cégep network |

**Never move ports 1 or 11**: `pve` would lose the cégep network, and with it the VPN and `fw01`'s Internet access. Never put port 1 in VLAN 10, or the cégep network would reach the management VLAN.

Only VLAN 10 crosses port 12. On `pve`, `nic1` has VLAN 10 and no untagged VLAN (`bridge-vids 10`, `bridge-allow-untagged no`), and port 12 isn't untagged in any VLAN: even with a mistake on one side, VLAN 1 can't reach the centre's VLANs or the other way round.

The VLAN part of the configuration, saved with `write memory`:

```
vlan 1
   name "DEFAULT_VLAN"
   untagged 1,6-11,13-16
   ip address dhcp-bootp
   exit
vlan 10
   name "CDE-GESTION"
   untagged 2-5
   tagged 12
   exit
```

## Connecting a Laptop

1. Plug the laptop into port 2, 3, 4 or 5.
2. Give its Ethernet card a fixed address, in a **Terminal (administrator)** (one address per person):

   ```powershell
   New-NetIPAddress -InterfaceAlias Ethernet -IPAddress 10.10.10.31 -PrefixLength 24 -DefaultGateway 10.10.10.1; Set-DnsClientServerAddress -InterfaceAlias Ethernet -ServerAddresses 10.10.10.1
   ```

   | Person  | Address       |
   | ------- | ------------- |
   | Loucas  | `10.10.10.31` |
   | Nicolas | `10.10.10.32` |
   | Joshua  | `10.10.10.33` |
   | Alexy   | `10.10.10.34` |

3. **Quit Hiddify** (and Tailscale) while plugged in: the VPN would take over the traffic and the DNS.

The laptop then has the rights of VLAN 10: SSH, HTTPS, RDP and Proxmox towards every VLAN, `https://<name>.divertissementestrie.ca`, the `cde.lan` names through `fw01`, and the web (80 and 443) towards the Internet through `fw01`. `pve` itself answers on `10.10.10.10`.

To go back to the cégep network or the Wi-Fi only, unplug the cable, or remove the address: `Remove-NetIPAddress -InterfaceAlias Ethernet -IPAddress 10.10.10.31 -Confirm:$false; Remove-NetRoute -InterfaceAlias Ethernet -DestinationPrefix 0.0.0.0/0 -Confirm:$false; Set-DnsClientServerAddress -InterfaceAlias Ethernet -ResetServerAddresses`.

## Console Access

1. Plug the console cable (USB adapter, CH340) into a laptop. It shows up as a COM port (`Get-PnpDevice -Class Ports`).
2. PuTTY: *Connection type* **Serial**, the COM port, speed **9600**; *Connection → Serial*: 8 data bits, 1 stop bit, parity None, flow control None.
3. Log in with the `manager` account.

Read-only commands: `show vlans`, `show vlans 10`, `show interfaces brief`, `show lldp info remote-device`, `show mac-address <mac>`, `show running-config`. After a change: `write memory`, or it's lost at the next restart.

**The CH340 adapter locks up** after the program using it closes: the next program gets "Error 31". Unplug and plug the adapter back in before each new connection.
