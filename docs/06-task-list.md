# 6. Task List — Work Breakdown Structure (WBS / OTP)

The work breakdown structure (*organigramme technique de projet*, OTP) breaks the project down into homogeneous work packages, each entrusted to a lead and grouping a coherent set of tasks. Each task is numbered and characterized by its assigned resource, its estimated duration, its start and end dates (expressed in implementation weeks) and its internal cost.

## 6.1 Breakdown into Work Packages

| Package   | Project component                                                                        | Main lead                  |
| --------- | ---------------------------------------------------------------------------------------- | -------------------------- |
| Package 0 | Project management (meetings, coordination, data entry)                                  | Acting project manager     |
| Package 1 | Base infrastructure (Proxmox, network, VLANs, Terraform, Kubernetes/k3s, Ansible)        | Nicolas-André Anillo       |
| Package 2 | Security (pfSense/OPNsense, Tailscale, firewall rules, Caddy)                            | Loucas Viens               |
| Package 3 | Linux services (Asterisk, LAMP, Netdata)                                                 | Alexy Després              |
| Package 4 | Windows services (Active Directory, hMailServer, osTicket, Veeam, Defender for Endpoint) | Joshua Leclerc             |
| Package 5 | Automation (individual scripts)                                                          | Team (1 each)              |
| Package 6 | MQTT and connected devices (Mosquitto, ESP32)                                            | Nicolas-André Anillo       |
| Package 7 | Novelty elements (Jellyfin and \*arr suite, Homarr, AMP)                                 | Team (1 each)              |
| Package 8 | Testing, integration and documentation                                                   | Team                       |

## 6.2 Task Table

The thirty-six tasks are distributed across eight execution packages and one management package, for a total of 338 hours. Each task is numbered, assigned to a resource, dated (start and end week, with week 6 beginning on September 28, 2026) and costed. The complete table, with the subtotals and the automatically calculated cost, is found in the Excel workbook.

The detailed task list (number, description, package, resource, type, duration, start and end dates, cost) is found in the “OTP” tab of the Planification_calculs.xlsx workbook, submitted with this report. The cost of each task is calculated there from its duration and the applicable hourly rate.

## 6.3 Resources and Assignment

The human resources are the four team members; the management role (Package 0) is assumed by the acting project manager. In the OTP tab, the workbook summarizes the execution workload assigned to each person (excluding management), for information purposes, in order to verify the balance of the distribution. The participation of all team members in the weekly meetings is counted in Package 0 (task T0.4), in addition to the project manager's management time.
