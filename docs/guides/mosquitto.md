# Mosquitto MQTT Broker

`mqtt01` runs Mosquitto, the broker the ESP32 modules talk to. The `mosquitto` Ansible role, called from [`ansible/site.yml`](../../ansible/site.yml), installs and configures it.

| Item      | Value                                                                       |
| --------- | --------------------------------------------------------------------------- |
| Host      | `mqtt01` (VM 6010), `10.10.60.10`, VLAN 60                                  |
| Listener  | `1883/TCP`, **without TLS** for now (see [Status](#status))                 |
| Clients   | The ESP32 modules in VLAN 60; `ctrl-iac` on 1883 and 8883 for tests         |
| Accounts  | Anonymous access is refused; see below                                      |
| Passwords | `ansible/inventory/group_vars/mqtt/vault.yml`, encrypted with Ansible Vault |

## Accounts and topics

| Account   | Topics                                                      | Use                  |
| --------- | ----------------------------------------------------------- | -------------------- |
| `admin`   | Read and write on everything                                | Administration, tests |
| `esp32`   | Writes `cde/capteurs/#`, reads `cde/commandes/#`            | ESP32 modules        |
| `tableau` | Reads `cde/capteurs/#`, writes `cde/commandes/#`            | Dashboard            |

The accounts are in `ansible/inventory/group_vars/mqtt/main.yml` and the access rules in the role's `acl.j2` template.

## Passwords

`vault.yml` is encrypted, so it can stay in the repository. The key that opens it, `~/.vault_pass_cde`, exists only on `ctrl-iac` and must never be committed. Ansible finds it through `ansible.cfg`.

To change a password, on `ctrl-iac`:

```bash
cd /root/entertainment-center-infra/ansible
ansible-vault edit inventory/group_vars/mqtt/vault.yml
ansible-playbook site.yml --limit mqtt01
```

## Applying the role

```bash
cd /root/entertainment-center-infra/ansible
ansible-playbook site.yml --limit mqtt01 --check --diff    # shows what would change
ansible-playbook site.yml --limit mqtt01
```

## Testing

From `ctrl-iac`, with the `admin` password:

```bash
mosquitto_sub -h 10.10.60.10 -p 1883 -u admin -P '<password>' -t 'cde/#' -v
```

## Status

As of November 9, 2026:

- **No TLS yet.** The broker listens on 1883 without encryption. The plan is TLS on 8883 with 1883 disabled (network log, section 10.2). It takes a certificate on `mqtt01` and a `listener 8883` block in `cde.conf.j2`, and `mosquitto_port` is the variable to change.
- **VLAN 20 can't reach the broker.** The firewall only allows 8883 from VLAN 20 (rule 3), and nothing listens on that port.
- **No ESP32 module can connect yet,** because `vmbr1` has no physical port.
