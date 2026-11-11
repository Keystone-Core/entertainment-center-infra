# Netdata Monitoring

Netdata watches the resources of the nine Linux servers (task T3.3). Each server measures itself every second and sends everything to `mon01`, the parent. `mon01` keeps the history, raises the alerts and serves the dashboard. The `netdata` Ansible role ([`ansible/netdata.yml`](../../ansible/netdata.yml)) installs and configures it.

| Item              | Value                                                                                         |
| ----------------- | --------------------------------------------------------------------------------------------- |
| Parent            | `mon01` (VM 2022), `10.10.20.22`, port 19999                                                   |
| Children          | dash01, game01, k3s01, media01, mqtt01, proxy01, voip01, web01                                 |
| Version           | Netdata 2.12, from the official repository: Debian 13 no longer packages it, and Debian 12 has 1.37 from 2022 |
| Dashboard         | `http://10.10.20.22:19999`, from VLAN 10 and VLAN 20                                           |
| One server        | `http://10.10.20.22:19999/host/<name>/`, for example `/host/voip01/`                           |
| History           | On `mon01` (dbengine, on disk). The children keep only an hour in memory                       |
| Alerts            | Raised by `mon01` for every server (more than 100 rules each: CPU, memory, disk, network, services) |
| Netdata Cloud     | Turned off, as are the anonymous statistics: nothing leaves the centre                        |

## Opening the dashboard

From a staff workstation (VLAN 20) or from VLAN 10, open `http://10.10.20.22:19999`. From a laptop, through `ctrl-iac`:

```bash
ssh -N -L 19999:10.10.20.22:19999 ctrl-iac
```

Then open `http://localhost:19999`.

Since version 2.0, the Netdata dashboard shows **at most five servers at a time** without a paid Netdata Cloud plan. Every server is still measured and kept on `mon01`, but the overview pages only show five of them. To see any server, open its own page on `mon01`, `http://10.10.20.22:19999/host/<name>/`, which has no limit:

| Server  | Page on `mon01`        |
| ------- | ---------------------- |
| voip01  | `/host/voip01/`        |
| web01   | `/host/web01/`         |
| k3s01   | `/host/k3s01/`         |
| media01 | `/host/media01/`       |
| dash01  | `/host/dash01/`        |
| mqtt01  | `/host/mqtt01/`        |
| proxy01 | `/host/proxy01/`       |
| game01  | `/host/game01/`        |
| mon01   | `/host/mon01/`         |

The same data is available as JSON, for scripts:

```bash
curl -s http://10.10.20.22:19999/api/v1/info \
  | python3 -c 'import json,sys; print(json.load(sys.stdin)["mirrored_hosts"])'   # servers seen by mon01
curl -s 'http://10.10.20.22:19999/host/voip01/api/v1/data?chart=system.cpu&after=-60&points=1&group=average'
curl -s http://10.10.20.22:19999/host/k3s01/api/v1/alarms                         # active alerts
```

## How it's set up

| | Parent (`mon01`) | Children |
| --- | --- | --- |
| Storage | `dbengine` on disk | In memory (an hour) |
| Web server | All addresses, port 19999 | Local only (`127.0.0.1:19999`) |
| Alerts and machine learning | On, for every server | Off: the parent does it |
| `stream.conf` | Accepts the shared key from the children's addresses | Sends to `10.10.20.22:19999` with the shared key |

The shared key is a UUID generated the first time the role runs and kept on `ctrl-iac` in `/root/.cde-secrets/netdata/cle-api`. The parent only accepts it from the children's addresses, and its dashboard only answers VLAN 10, VLAN 20 and `proxy01`.

The firewall already allows the children outside VLAN 20 to reach `mon01`: rule 6 for `mqtt01` (VLAN 60) and `proxy01` and `game01` (VLAN 80), rule 1 for VLAN 10. See the [network log](../10-network-log.md).

## Running the playbook

From `ctrl-iac`, after the base role:

```bash
cd /root/entertainment-center-infra/ansible
ansible-playbook netdata.yml
```

The playbook does `mon01` first, so it's ready when the children connect. A second run changes nothing. A new Linux server in the `linux` group of the inventory becomes a child at the next run.

## Troubleshooting

| Symptom | Likely cause and check |
| ------- | ---------------------- |
| A server is missing from `mirrored_hosts` | It can't reach `mon01:19999` (firewall rule 6 for VLANs 60 and 80), or its key doesn't match. On the server: `sudo journalctl -u netdata | grep -i stream` |
| The dashboard answers "access denied" | The browser's address isn't in VLAN 10, VLAN 20 or `proxy01`. Use the SSH tunnel |
| A server appears but grayed out in the overview | The five-server limit of the dashboard: open `/host/<name>/` |
