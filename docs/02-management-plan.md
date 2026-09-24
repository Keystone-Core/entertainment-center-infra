# 2. Management Plan

The management plan specifies the operating rules that govern the relationships between team members: the composition of the group, each member's responsibilities, the rotation of the project manager and the organization of communication. It constitutes the common reference to which the team refers throughout the implementation.

## 2.1 Team Composition and Responsibilities

The team is made up of four people, each considered a network manager in training. Each member is responsible for the design, execution and demonstration of their portion of the project, as well as its integration into the whole. The following table presents the main distribution of responsibilities, bearing in mind that several tasks are carried out collaboratively.

| Team member          | Main responsibilities                                                                                                                                                                                                          |
| -------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| Nicolas-André Anillo | Centralized automation (Ansible playbooks), IP addressing plan and VLAN segmentation, pfSense/OPNsense firewall and segmentation rules, MQTT broker (Mosquitto), multimedia streaming (Jellyfin), individual automation script |
| Alexy Després        | Terraform provisioning, container orchestration (Kubernetes/k3s), Linux services (Asterisk VoIP, LAMP web server, Netdata monitoring), individual automation script                                                            |
| Joshua Leclerc       | Windows services (hMailServer email, osTicket ticketing, Veeam backups), Microsoft Defender for Endpoint, Homarr dashboard, individual automation script                                                                       |
| Loucas Viens         | Infrastructure and network (Proxmox VE, physical network and VLANs), Active Directory, Tailscale VPN, Caddy reverse proxy, \*arr suite and qBittorrent, game server panel (AMP), individual automation script                  |

## 2.2 Project Manager Rotation and Duties

The acting project manager leads the weekly follow-up meeting, coordinates the work, ensures the flow of information, updates the FMECA table and the updated budget, and represents the team to the teachers. Grades remain individual. The table below presents the rotation adopted over the implementation weeks.

| Period            | Project manager      | Specific duties                                                   |
| ----------------- | -------------------- | ----------------------------------------------------------------- |
| Weeks 6 and 7     | Nicolas-André Anillo | Implementation kickoff, infrastructure setup                      |
| Weeks 8 and 9     | Alexy Després        | Security follow-up, services coordination                         |
| Weeks 10 and 11   | Joshua Leclerc       | Follow-up of the Linux/Windows services and MQTT                  |
| Weeks 12 and 13   | Loucas Viens         | Follow-up of automation and novelty elements                      |
| Weeks 14 and 15   | Nicolas-André Anillo | Testing, integration, preparation of the final presentation       |

## 2.3 Document Management (Teams / SharePoint / GitHub)

All working documents are stored in the team's Teams group (also accessible through SharePoint). The planning work relies on two files: the report Planification_du_projet.docx, which contains the management plan, the functional specification, the initial planning and the network log, and the workbook Planification_calculs.xlsx, which contains the risk analysis, the task list, the budgets and the planning calculations. Their current version is replaced with each update. These files are working versions used for sharing and review; the final version is submitted on LEA at the specified time. The documentation will also be published on GitHub in Markdown format.
