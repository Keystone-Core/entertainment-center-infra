# 4. Functional Specification (CdCF)

The functional specification (*cahier des charges fonctionnel*, CdCF) expresses the organization's needs in the form of functions to be fulfilled, each characterized by an evaluation criterion, a level and a flexibility class (from F0, mandatory, to F3, highly negotiable). A distinction is made between the main functions (the service expected by the client), the secondary functions (complementary needs) and the constraints imposed by the environment, technologies and regulations. The functions are prioritized according to their importance: F0-class functions and constraints are non-negotiable.

## 4.1 Main Functions

| No.  | Description                                                                 | Evaluation criterion          | Level                      | Flexibility | Class |
| ---- | --------------------------------------------------------------------------- | ----------------------------- | -------------------------- | ----------- | ----- |
| Fp1  | Provide secure remote access to administrators and support                  | Service availability          | 99 %                       | ± 1 %       | F1    |
| Fp2  | Provide internal and external email                                         | Accounts served               | 4 employees                | 0           | F0    |
| Fp3  | Protect the network and workstations against threats                        | Protected workstations        | 100 % of workstations      | 0           | F0    |
| Fp4  | Offer IP telephony                                                          | Telephone stations            | 4 stations                 | ± 1         | F2    |
| Fp5  | Host a web development server                                               | Functional LAMP stack         | Yes                        | 0           | F1    |
| Fp6  | Manage support requests with a ticketing system                             | Request tracking              | Web interface              | 0           | F1    |
| Fp7  | Monitor server resource usage                                               | Data per host                 | CPU, RAM, disk             | 0           | F1    |
| Fp8  | Automate deployment and administration                                      | Scripts and playbooks         | 1 script per team member   | 0           | F0    |
| Fp9  | Manage backups                                                              | Copy type                     | Full and incremental       | 0           | F0    |
| Fp10 | Enable connected devices to communicate (MQTT broker)                       | Connected modules             | ≥ 1 per team member        | 0           | F1    |
| Fp11 | Provide a centralized account directory                                     | Managed accounts              | Centralized                | 0           | F0    |
| Fp12 | Offer self-service public workstations, isolated from the internal network | Isolated public workstations  | 12 workstations            | 0           | F0    |
| Fp13 | Screen films in the projection rooms                                        | Rooms served                  | 2 rooms                    | 0           | F1    |
| Fp14 | Host networked game servers for customers                                   | Single management panel       | Yes                        | 0           | F1    |

## 4.2 Secondary Functions

| No. | Description                                                           | Evaluation criterion | Level             | Flexibility | Class |
| --- | --------------------------------------------------------------------- | -------------------- | ----------------- | ----------- | ----- |
| Fs1 | Centralize the monitoring display                                     | Services displayed   | Internal services | tolerated   | F2    |
| Fs2 | Stream multimedia content to staff and automate its management        | Staff access         | Yes               | tolerated   | F3    |
| Fs3 | Orchestrate containers                                                | Functional cluster   | Yes               | tolerated   | F3    |

## 4.3 Constraint Functions

| No. | Description                                                                    | Evaluation criterion | Level                                                                       | Flexibility | Class |
| --- | ------------------------------------------------------------------------------ | -------------------- | --------------------------------------------------------------------------- | ----------- | ----- |
| Fc1 | Distribute the services between Linux and Windows according to technical merit | Services per system  | Windows: directory, email, ticketing and backups; Linux: the other services | tolerated   | F2    |
| Fc2 | Run on a single physical server                                                | Virtualization host  | 1 server (Proxmox)                                                          | 0           | F0    |
| Fc3 | Remain manageable by a small team                                              | Assigned staff       | 4 employees                                                                 | 0           | F1    |
| Fc4 | Ensure security and confidentiality                                            | Measures in place    | Encryption, access rights                                                   | 0           | F1    |
| Fc5 | Stay within the project budget                                                 | Budget variance      | Initial budget                                                              | ± 10 %      | F1    |
| Fc6 | Deliver within the session deadlines                                           | Final deadline       | December 11, 2026                                                           | 0           | F0    |
| Fc7 | Secure the web services with HTTPS                                             | Valid certificates   | 100 % of web services                                                       | 0           | F1    |
