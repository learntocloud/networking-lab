# Contributing

This lab is a learning resource. Contributions must keep the exercises accurate,
reproducible, and useful for teaching good cloud networking practices.

## Repository File Guide

This guide focuses on lab-specific behavior rather than standard repository
files. In the tables below, `<cloud>` means `aws`, `azure`, or `gcp`; paths are
relative to the repository root.

### Lab Scripts and Infrastructure

| File | Purpose |
|------|---------|
| `scripts/dns-validation.sh` | Shared DNS checks used by provider validators; checks hostname resolution and expected addresses using the provider's VM execution helper. |
| `<cloud>/scripts/setup.sh` | Checks prerequisites, deploys Terraform, saves the lab SSH key, and prints connection information. Azure and GCP also check VM readiness and prepare incidents after deployment. |
| `<cloud>/scripts/validate.sh` | Checks incident resolution through connectivity and cloud configuration checks; reports progress and handles completion-token export and verification. |
| `<cloud>/scripts/destroy.sh` | Runs the provider's teardown workflow and removes the local lab SSH key. Provider-specific cleanup logic handles some resources outside Terraform. |
| `<cloud>/terraform/main.tf` | Declares Terraform/provider requirements, configures the provider, creates the deployment identifier, and connects the network, compute, and DNS modules. |
| `<cloud>/terraform/outputs.tf` | Exposes deployment details used by scripts and learners, including resource identifiers, host addresses, connection instructions, and the sensitive SSH key output. |
| `<cloud>/terraform/modules/network/main.tf` | Creates the virtual network, subnets, and egress infrastructure, with provider-specific routing and associations. |
| `<cloud>/terraform/modules/compute/main.tf` | Creates the bastion, web, API, and database hosts, their SSH key material, and provider-specific networking attachments; supplies bootstrap templates. |
| `<cloud>/terraform/modules/dns/main.tf` | Creates the lab's private DNS zone and its provider-specific configuration. |
| `<cloud>/terraform/modules/dns/records.tf` | Intentional placeholder for missing service records. Do not fill it in as routine cleanup; the missing records are part of the DNS exercise. |
| `<cloud>/terraform/modules/compute/templates/bastion-init.sh` | Bootstraps the jump host with SSH access, diagnostic tools, and learner-facing connection hints. |
| `<cloud>/terraform/modules/compute/templates/web-init.sh` | Configures the nginx web service, HTTP/HTTPS, a self-signed certificate, and diagnostic tools. |
| `<cloud>/terraform/modules/compute/templates/api-init.sh` | Creates the sample API application and its systemd service. The implementation differs by provider. |
| `<cloud>/terraform/modules/compute/templates/database-init.sh` | Configures the database-side service: PostgreSQL on Azure/GCP, and a lightweight database listener on AWS. |

### Provider-Specific Files

| File | Purpose |
|------|---------|
| `azure/scripts/common.sh`, `gcp/scripts/common.sh` | Shared helpers within each provider for prerequisites, Terraform outputs, SSH execution, connectivity probes, and hardening checks. AWS keeps its corresponding helpers in its scripts instead. |
| `azure/scripts/nsg-policy.py` | Evaluates effective IPv4 NSG inbound source restrictions for hardening validation. |
| `gcp/scripts/firewall-policy.py` | Evaluates effective ingress firewall policy, including rule priorities and implicit deny, for hardening validation. |
| `aws/terraform/modules/network/security_groups.tf` | Defines the hosts' security groups and initial traffic rules. |
| `azure/terraform/modules/network/nsg.tf` | Defines the hosts' network security groups and initial traffic rules. |
| `gcp/terraform/modules/network/firewall.tf` | Defines the lab's VPC firewall rules. |
| `azure/terraform/modules/network/routes.tf`, `gcp/terraform/modules/network/routes.tf` | Comment-only placeholders explaining that no custom routes are defined in these files. Inspect `network/main.tf` for the actual network resources. |

For a behavior change, follow the full path: provider guide, setup script,
Terraform and bootstrap templates, validation and its helpers, then teardown.
The intended faults may be introduced during setup rather than solely in
Terraform, so reviewing only the resource definitions is not sufficient.

## Preserve the Learning Experience

Preserve the **intentional misconfigurations** that make up the challenges.
Students diagnose problems through the bastion and resolve them using the cloud
provider CLI (`az`, `aws`, `gcloud`), not by editing Terraform.

Fix unintended infrastructure, setup, validation, or teardown bugs at their
source, including Terraform when appropriate. Keep the intended faults
reproducible and the lab deployable and removable. Do not weaken validation or
teach unsafe shortcuts just to make a check pass.

Keep changes focused and update the relevant provider guide when behavior,
prerequisites, commands, or expected results change. Explain provider-specific
differences rather than forcing all clouds to work identically.

## Manual Testing Is Required Before Opening a PR

**Every contribution must be manually tested before opening a pull request.**
Automated checks, static reviews, and AI-generated assessments can supplement
manual testing, but cannot replace it. Learners rely on these instructions;
we need to verify the experience we are teaching, not just that code looks right.

For changes to Terraform, scripts, dependencies, or documented lab commands and
procedures, test the affected student journey in a real lab for every affected
cloud:

1. Follow the provider's README from a clean deployment using its setup script.
   Confirm the prerequisites and instructions are sufficient without undocumented
   workarounds.
2. Run validation before applying fixes. Confirm the intended incidents are
   unresolved and that setup or service failures are not mistaken for intentional
   faults.
3. Diagnose and resolve the incidents as a learner would, using the documented
   workflow and cloud CLI. Run validation as you progress, check that unresolved
   faults are still detected, and confirm earlier fixes continue to pass.
4. Confirm all incidents pass after resolution and completion-token export works.
   Exercise any changed failure paths or edge cases, not only the successful path.
5. Run the documented cleanup workflow. Verify that lab resources, including
   resources created while solving incidents, are removed to avoid ongoing costs.

Changes to shared helpers or cross-cloud instructions must be tested on every
cloud they affect. Use a dedicated test environment and account for cloud costs.
If you cannot complete the required testing, open an issue describing the change
and the testing needed rather than an untested PR.

For prose-only changes that do not alter lab commands or behavior, manually
review the rendered documentation, check links and paths, and verify consistency
with the provider guides. A cloud deployment is not required for these changes.
For agent-skill changes, also invoke the skill with a representative request and
review whether its output and actions follow the documented scope and guardrails.

## What to Include in Your PR

- The problem, the change, and how it preserves or improves the learning experience.
- Affected clouds and relevant issue links.
- Manual testing evidence: OS, Terraform and cloud CLI versions, steps performed,
  expected versus actual results, and confirmation of cleanup where applicable.
- Relevant redacted output or screenshots and any remaining limitations.

Never include credentials, private keys, Terraform state, completion tokens, or
other sensitive information in commits, issues, screenshots, or test output.

## Reporting Problems

Use [GitHub Issues](https://github.com/learntocloud/networking-lab/issues/new/choose)
for bugs, broken instructions, or unclear steps. Include the cloud, incident or
step, reproduction steps, expected and actual behavior, and relevant validation
output with secrets and tokens removed.

## Maintenance Reviews

For a report-only maintenance review, ask a skill-capable agent to use
[`review-lab-maintenance`](.github/skills/review-lab-maintenance/SKILL.md).
It reviews Terraform, cloud CLI compatibility, dependencies, lab behavior, and
documentation across all three clouds without changing files or cloud resources.
Its report identifies follow-up work; it is not a substitute for the manual
testing required before a PR.
