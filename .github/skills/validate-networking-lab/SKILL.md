---
name: validate-networking-lab
description: Validates the networking lab infrastructure by testing actual connectivity through SSH. Runs connectivity tests for NAT gateway, DNS resolution, NSG rules, and security hardening.
---

# Validate Networking Lab

Test the networking lab infrastructure by SSHing through the bastion and running connectivity checks.

## Prerequisites

- Terraform deployed in `azure/terraform/`
- SSH key saved at `~/.ssh/netlab-key`
- Environment variables set: `RESOURCE_GROUP`, `DEPLOYMENT_ID`, `VNET_NAME`

## Workflow

1. **Get Terraform outputs** for IP addresses:
   ```bash
   cd azure/terraform
   BASTION_IP=$(terraform output -raw bastion_public_ip)
   API_IP=$(terraform output -raw api_server_private_ip)
   WEB_IP=$(terraform output -raw web_server_private_ip)
   DB_IP=$(terraform output -raw database_server_private_ip)
   ```

2. **Test Task 1 (NAT Gateway)** - API server internet access:
   ```bash
   ssh -i ~/.ssh/netlab-key labadmin@$BASTION_IP \
     "ssh labadmin@$API_IP 'curl -s --max-time 10 -o /dev/null -w \"%{http_code}\" https://example.com'"
   ```
   Expected: `200`

3. **Test Task 2 (DNS)** - Internal hostname resolution:
   ```bash
   ssh -i ~/.ssh/netlab-key labadmin@$BASTION_IP \
     "ssh labadmin@$WEB_IP 'nslookup api.internal.local 168.63.129.16'"
   ```
   Expected: Returns 10.x.x.x address

4. **Test Task 3 (Ports)** - Service connectivity:
   ```bash
   # Web -> API on 8080
   ssh -i ~/.ssh/netlab-key labadmin@$BASTION_IP \
     "ssh labadmin@$WEB_IP 'nc -zw3 $API_IP 8080 && echo 1 || echo 0'"

   # API -> DB on 5432
   ssh -i ~/.ssh/netlab-key labadmin@$BASTION_IP \
     "ssh labadmin@$API_IP 'nc -zw3 $DB_IP 5432 && echo 1 || echo 0'"
   ```
   Expected: `1` for both

5. **Test Task 4 (Security)** - Bastion should NOT reach database:
   ```bash
   ssh -i ~/.ssh/netlab-key labadmin@$BASTION_IP \
     "nc -zw3 $DB_IP 5432 && echo 1 || echo 0"
   ```
   Expected: `0` (blocked)

## Run Full Validation

```bash
cd azure/terraform && ../scripts/validate.sh all
```

## Common Issues

- **DNS caching**: Use `168.63.129.16` directly to bypass systemd-resolved
- **Nested SSH parsing**: Keep inner SSH options simple, avoid complex quoting
- **Integer comparison errors**: Strip newlines with `tr -d '\n\r'`
