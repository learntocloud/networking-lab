# AWS Networking Lab

A realistic network troubleshooting exercise. You're the on-call engineer—diagnose and fix.

```
┌───────────────────────────────────────────────────────────────┐
│                    VPC (10.0.0.0/16)                          │
│  ┌────────────────┐  ┌────────────────┐  ┌────────────────┐   │
│  │ Public Subnet  │  │ Private Subnet │  │    Database    │   │
│  │  10.0.1.0/24   │  │  10.0.2.0/24   │  │    Subnet      │   │
│  │   - Bastion    │  │   - Web App    │  │  10.0.3.0/24   │   │
│  │   - NAT GW     │  │   - API Server │  │   - Database   │   │
│  └────────────────┘  └────────────────┘  └────────────────┘   │
└───────────────────────────────────────────────────────────────┘
```

## Contents

- [Prerequisites](#prerequisites)
- [Getting Started](#getting-started)
- [Getting Help](#getting-help)
- [Incident Queue](#incident-queue)
- [Verify Your Fixes](#verify-your-fixes)
- [Clean Up](#clean-up)

---

## Prerequisites

- **AWS CLI** installed and authenticated (e.g., `aws configure`)
- **Terraform** installed (1.4+)
- **AWS credentials** available to Terraform/CLI (env vars or shared config)

---

## Getting Started

1. Navigate to the scripts directory:
   ```bash
   cd aws/scripts
   ```

2. Make scripts executable:
   ```bash
   chmod +x *.sh
   ```

3. Run the setup script:
   ```bash
   ./setup.sh
   ```

The setup script will display SSH connection instructions when complete.

**Cost**: ~$0.50-1.00/session. Destroy when done.

---

## Getting Help

If you run into issues (broken instructions, validation failures you can’t explain, or suspected bugs), please open a **GitHub Issue** in this repo:

- [Open an issue](../issues/new/choose)
- Include: incident ID (e.g., INC-4521), what you tried, and `./validate.sh` output (redact secrets/tokens).

---

## Incident Queue

You're on call. Four tickets just came in. Your job: diagnose and fix.

### 🎫 INC-4521: API service can't pull external data

**Priority:** High  
**Reported by:** Backend Team  
**Time:** 09:47 AM

> "Our API service that runs on the private subnet stopped being able to fetch data from external APIs this morning. We didn't change anything on our end. Requests to third-party services just hang and timeout. Internal calls between our services still work fine."

**Affected system:** API server (private subnet)

---

### 🎫 INC-4522: Service discovery broken

**Priority:** High  
**Reported by:** Platform Team  
**Time:** 10:15 AM

> "Our applications can't resolve internal hostnames anymore. We've been using `web.internal.local`, `api.internal.local`, and `db.internal.local` for service discovery but they stopped resolving. Public DNS works fine - we can resolve google.com. This is blocking deployments."

**Affected system:** All VMs

---

### 🎫 INC-4523: Web frontend can't reach backend

**Priority:** Critical  
**Reported by:** Web Team  
**Time:** 10:32 AM

> "The web frontend suddenly can't connect to the API backend. We're getting connection refused errors on port 8080. The API health endpoint works when we curl localhost on the API server itself, so the service is running. Also, the API team says they can't reach the database on port 5432."

**Affected systems:** Web server → API server, API server → Database

---

### 🎫 INC-4524: Security audit findings

**Priority:** Medium  
**Reported by:** Security Team  
**Time:** 11:00 AM

> "Our quarterly security scan flagged several issues with the network segmentation:
> 
> 1. SSH is accessible from the internet on some hosts (should only be via bastion)
> 2. Database accepts connections from too broad a range (should be API tier only; SG-scoped is preferred)
> 3. ICMP is open from anywhere
> 
> These need to be tightened up before our compliance review next week."

**Affected systems:** Security groups / NACLs

---

## Verify Your Fixes

The validation script tests actual connectivity—not just configuration. It SSHs into the VMs and runs the same checks a user would to confirm services are reachable. Sometimes, you may need to wait a minute or two for changes to propogate before validating.

**When to use it:**
- After fixing an incident to confirm it's resolved
- When you think you're done with all incidents
- To generate a completion token for submission

**Check incident status:**

1. Navigate to the scripts directory:
   ```bash
   cd aws/scripts
   ```

2. Run validation:
   ```bash
   ./validate.sh
   ```

**Generate completion token:**

1. Run export:
   ```bash
   ./validate.sh export
   ```

2. Enter your GitHub username when prompted

---

## Clean Up

When finished, destroy resources to avoid charges:

1. Navigate to the scripts directory:
   ```bash
   cd aws/scripts
   ```

2. Run the destroy script:
   ```bash
   ./destroy.sh
   ```
