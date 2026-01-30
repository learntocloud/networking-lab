# Networking Lab

Fix a deliberately broken Azure network infrastructure. Learn by troubleshooting.

➡️ Detailed guide: [azure/README.md](azure/README.md)

## Quick Start

```bash
cd azure/scripts
./setup.sh        # deploy broken lab
./validate.sh all # run all checks
./destroy.sh      # cleanup when done
```

**Cost**: ~$0.50–1.00/session. Destroy when done.

## Tasks Overview

1. **Routing & Gateways** — API server reaches internet (attach NAT to private subnet).
2. **DNS Resolution** — Private DNS zone linked; A records for web/api/db.
3. **Ports & Protocols** — NSGs allow web→API:8080 and API→DB:5432.
4. **Security Hardening** — SSH only from bastion subnet; DB only from API subnet; ICMP restricted.

Validate with:
```bash
cd azure/scripts
./validate.sh <task-1|task-2|task-3|task-4|all>
```

## Cleanup

```bash
cd azure/scripts
./destroy.sh
```

## Completion

```bash
cd azure/scripts
./validate.sh export
```

Submit token at https://learntocloud.guide/verify using your learntocloud.guide GitHub username.

## Resources

- [Azure VNet](https://learn.microsoft.com/en-us/azure/virtual-network/)
- [Azure NSG](https://learn.microsoft.com/en-us/azure/virtual-network/network-security-groups-overview)
- [Azure Private DNS](https://learn.microsoft.com/en-us/azure/dns/private-dns-overview)
