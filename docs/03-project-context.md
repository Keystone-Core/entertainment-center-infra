# 3. Project Context

This section restates the context established at the definition stage. The organization itself has not changed: same activities, same four employees, same establishment. However, a few technical choices have been clarified since the previous submission. The services are now hosted on a single physical server running Proxmox VE, whereas the internal servers were previously still to be determined. The firewall is a pfSense (or OPNsense) installed as a virtual machine, and not a Windows firewall. The split between Linux and Windows is no longer strictly equal: it is established according to the technical merit of each service. Finally, the instant messaging announced in the definition is not deployed in this planning, as hMailServer only offers email.

## 3.1 Organization Overview

The Centre de divertissement de l'Estrie is an entertainment centre located in Sherbrooke. It offers three main types of activities: screening films in dedicated rooms, hosting networked video game servers, and providing public computers for gaming and browsing. The organization has four employees who handle all day-to-day operations. As the company is small and concentrated on a single site, the infrastructure must remain simple to administer while covering services normally associated with larger organizations.

| Element                 | Description                                                                                                                   |
| ----------------------- | ----------------------------------------------------------------------------------------------------------------------------- |
| Company name            | Centre de divertissement de l'Estrie (provisional name)                                                                       |
| Type of business        | Entertainment centre                                                                                                          |
| Activities              | Film screenings, game server hosting, public workstations                                                                     |
| Products and services   | Screening sessions, access to networked game servers, access to public gaming and browsing workstations                       |
| Number of employees     | Four                                                                                                                          |
| Geographic distribution | A single establishment, in Sherbrooke                                                                                         |
| Infrastructure          | A single physical server running Proxmox VE; services deployed as virtual machines or containers (including the firewall/VPN) |

## 3.2 Workstations and Distribution

The computer fleet is divided between the staff workstations, the self-service public workstations and the technical workstations of the screening rooms. This baseline is used to size the services and remains the reference for the planning.

| Workstation type                  | Quantity | Role                                                                                                   |
| --------------------------------- | -------- | ------------------------------------------------------------------------------------------------------ |
| Staff workstations                | 4        | Management, reception/ticketing, technical support, multipurpose workstation (also web development)    |
| Self-service public workstations  | 12       | Network gaming and browsing for customers                                                              |
| Screening room workstations       | 2        | Control and projection in each of the two rooms                                                        |
| Internal server                   | 1        | Virtualization host consolidating all services (Linux and Windows)                                     |
