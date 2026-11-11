# Demos

One file per team member: a full demo of their part of the project, with the explanations to give and the commands to run. Each file follows the same outline:

1. **What I built**: the tasks of the planning workbook and where each result lives.
2. **Before the demo**: tunnels, accounts and data to prepare.
3. **Demo script**: each part with what to say, what to show and the expected result.
4. **Questions to expect** and **problems solved along the way**.
5. **Limits and what's left**.

| Member | Demo | Tasks |
| ------ | ---- | ----- |
| Alexy Després | [alexy-despres.md](alexy-despres.md) | Terraform (T1.3), k3s (T1.5), FreePBX telephony (T3.1), LAMP web server and website (T3.2), Netdata (T3.3), website backup script (T5.2) |
| Loucas Viens | *to come* | |
| Nicolas-André Anillo | *to come* | |
| Joshua Leclerc | *to come* | |

## Reaching the infrastructure from a laptop

Every demo goes through the Xray VPN and `ctrl-iac`, the control station in VLAN 10. One SSH tunnel opens the web interfaces published by `proxy01`, and the names have to point to it in the browser (in Firefox or Zen, `about:config`, `network.dns.localDomains`):

```bash
ssh -N -L 8443:10.10.80.10:443 ctrl-iac
```

```
www.divertissementestrie.ca,phpmyadmin.divertissementestrie.ca,freepbx.divertissementestrie.ca,pfsense.divertissementestrie.ca
```

Then open `https://<name>.divertissementestrie.ca:8443`. The certificates are real (Let's Encrypt), so there's no warning.
