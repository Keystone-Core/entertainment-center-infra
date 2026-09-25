# Contributing

## Commit messages

Every commit in this repository follows the [Conventional Commits 1.0.0](https://www.conventionalcommits.org/en/v1.0.0/) specification. A consistent format keeps the history easy to read, makes it clear which part of the infrastructure a commit touches and lets us generate changelogs later.

## Format

```text
<type>(<scope>): <description>

[optional body]

[optional footer(s)]
```

Only the first line is required. The scope is optional, but it is recommended to use it whenever the change touches a single area.

## Types

| Type       | Use it for                                              | Example                                            |
| ---------- | ------------------------------------------------------- | -------------------------------------------------- |
| `feat`     | A new service, host, playbook, script or capability     | `feat(terraform): provision voip01 LXC container`  |
| `fix`      | A correction to something that was broken               | `fix(firewall): allow VLAN 40 DNS to fw01`         |
| `docs`     | Documentation only                                      | `docs(network-log): add mqtt01 port 8883`          |
| `refactor` | Restructuring code without changing its behaviour       | `refactor(ansible): split common role into tasks`  |
| `perf`     | A change that improves performance                      | `perf(media01): enable hardware transcoding`       |
| `test`     | Adding or changing tests and validation checks          | `test(ansible): add molecule scenario for mail01`  |
| `ci`       | CI workflows and automation around the repository       | `ci: run terraform validate on pull requests`      |
| `style`    | Formatting only (whitespace, linting), no logic change  | `style(terraform): run terraform fmt`              |
| `chore`    | Maintenance that fits none of the above                 | `chore: add .env to gitignore`                     |
| `revert`   | Reverting an earlier commit                             | `revert: feat(k3s01): enable traefik ingress`      |

## Scopes

Use the area the commit touches, in lowercase, with one scope per commit:

- **A tool or code area:** `terraform`, `ansible`, `k3s`, `scripts`, `esp32`, `firewall`, `tailscale`.
- **A host** from the [hosts table](README.md#hosts-and-services): `dc01`, `proxy01`, `mqtt01`, `game01`…
- **A document:** `readme`, `network-log`, `contributing`.

If a change really spans several areas, leave the scope out rather than listing several.

## Description

- Use the imperative mood: "add", not "added" or "adds".
- Start in lowercase and don't end with a period.
- Keep the whole first line at 72 characters or fewer.
- Write in English, like the rest of the repository.

## Body and footers

Add a body when the reason for the change isn't obvious from the diff. Explain *why*, not *how*, and wrap lines at 72 characters. Leave a blank line between the description, the body and the footers.

Footers reference issues and credit collaborators:

```text
fix(dc01): renew DHCP scope for VLAN 30

The scope ran out of leases after the staff PCs were reimaged
because the lease time was 8 days.

Closes #14
Co-authored-by: Name <name@example.com>
```

## Breaking changes

A breaking change is one that forces other parts of the infrastructure to change too, such as a new VLAN subnet or a renamed host that playbooks depend on. Mark it with `!` after the type or scope, and describe it in a `BREAKING CHANGE:` footer:

```text
feat(ansible)!: rename web01 inventory group to lamp

BREAKING CHANGE: playbooks targeting the web01 group must now
target lamp.
```

## Good and bad examples

| Bad                         | Good                                                  | Why                                  |
| --------------------------- | ----------------------------------------------------- | ------------------------------------ |
| `update`                    | `feat(mon01): add netdata alert for disk usage`       | Says what changed and where          |
| `Fixed firewall rules.`     | `fix(firewall): block VLAN 60 access to the internet` | Type, imperative, no period          |
| `feat: stuff for terraform` | `feat(terraform): add proxmox provider config`        | Specific description, scope used     |
| `docs(Network Log): ports`  | `docs(network-log): document caddy ports 80 and 443`  | Lowercase scope, useful description  |

## Tips

- Make one logical change per commit. If the description needs "and", consider splitting it.
- Any network change (address, VLAN, port or firewall rule) must also update the [network log](docs/10-network-log.md) in the same commit.
