---
name: review-lab-maintenance
description: Check the networking lab for version and deprecation drift across AWS, Azure, and GCP. Use when asked whether Terraform, providers, cloud CLI commands, base VM images, instance types, or Python/package assumptions need upgrading. Produce a short evidence-backed drift report without modifying files or cloud resources.
---

# Review Lab Maintenance

Answer one question: **does anything pinned or assumed in this repository need to
be upgraded or changed?** Cover Terraform and providers, cloud CLI usage, base VM
images, instance types, and Python and package assumptions. Default to all three
clouds unless the user narrows scope.

This is a drift check, not an audit. Whether the lab's intentional
misconfigurations are correct, whether validation tests the right acceptance
criteria, and whether the guides match the implementation are out of scope —
those need a live, separately authorized run of the lab.

## Guardrails

- Report only. Do not edit files, upgrade dependencies, run Terraform
  (`init`/`plan`/`apply`/`destroy`), authenticate to any cloud, or run the
  setup, validate, or destroy scripts. Read them as source.
- Do not recommend an upgrade merely because a newer version exists. Every
  recommendation needs a concrete reason: a breaking change already admitted by
  the version constraint, a removed or deprecated CLI command or flag, an
  end-of-support date, or a fixed bug that affects this lab.
- The lab ships deliberate network faults. Never flag a misconfiguration as
  drift, and do not reproduce fixes or solution commands from the `scripts/`
  directories.
- Do not inspect or disclose credentials, private keys, Terraform state, or
  generated completion tokens.

## Step 1 — Read the current pins

Read every surface below and record the literal pin you find. This table is a map
of where pins live, not a record of their values; read the current value each
time. Line numbers drift, so search for the field rather than jumping to a line.

A surface that turns out to be unpinned, or a provider used by a resource but
never declared in `required_providers`, is itself worth reporting.

| Surface | What to read |
|---------|--------------|
| Terraform core | `required_version` in the `terraform` block of `aws/`, `azure/`, and `gcp/terraform/main.tf` — note that the three clouds pin different floors |
| Providers | every entry in `required_providers` in each `terraform/main.tf` (`aws`, `azurerm`, `google`, plus `random` and `tls`), and any provider referenced by a resource but not declared |
| Base image (AWS) | the `name` filter and `owners` on the `aws_ami` data source in `aws/terraform/main.tf` |
| Base image (Azure) | `source_image_reference` publisher, offer, sku, and version on every VM in `azure/terraform/modules/compute/main.tf` |
| Base image (GCP) | the image family in `gcp/terraform/modules/compute/main.tf` |
| Instance types | `instance_type` (AWS), `size` (Azure), and `machine_type` (GCP) in each compute module, including whether they are still current-generation and free-tier eligible |
| Bootstrap packages | every `apt-get install` package list in `*/terraform/modules/compute/templates/*-init.sh`, plus anything downloaded or installed from outside the distro repositories |
| Python assumptions | the `python3` version floor stated in each provider `README.md`, and whether `*/scripts/*-policy.py` uses only the standard library |
| Local tool prerequisites | the tools asserted by `require_commands` in `*/scripts/setup.sh`, `validate.sh`, and `common.sh`, compared against what each `README.md` lists under Prerequisites |
| CI | `uses:` refs in `.github/workflows/*.yml` if any workflows exist, and whether they are SHA-pinned |

Also collect every `aws`, `az`, and `gcloud` invocation from the provider
`README.md` files, `*/scripts/*.sh`, and `*/scripts/*-policy.py`. These are the
commands a student or the validator actually runs.

## Step 2 — Look up current versions

Use deterministic sources, not recollection. Record the date checked.

```bash
# Terraform core
gh api repos/hashicorp/terraform/releases/latest --jq .tag_name

# Providers (substitute each provider source found in Step 1)
curl -s https://registry.terraform.io/v1/providers/hashicorp/aws | jq -r .version
```

For anything without an API, use the official changelog or lifecycle page: the
provider `CHANGELOG.md` on GitHub, the Ubuntu release cycle page for whichever
LTS the images pin, and the AWS CLI, Azure CLI, and gcloud release notes for
removed or deprecated commands, flags, and output fields.

## Step 3 — Decide whether the gap matters

For each surface where the pin trails current, check whether the delta actually
affects this lab:

- **Terraform and providers:** does the allowed range already admit the new
  version? A `~>` or `>=` constraint that silently picks up a release with
  breaking changes is more urgent than a trailing lower bound. Check the provider
  changelog for breaking changes, removed arguments, and deprecations touching
  the resources this repo declares — VPCs and VNets, subnets, route tables,
  security groups, NSGs, firewall rules, private DNS zones, and VM resources.
- **Cloud CLIs:** has a command, subcommand, flag, or JSON output field used by
  the scripts or READMEs been removed, renamed, or deprecated? The policy scripts
  parse CLI JSON, so a changed output shape breaks validation silently. An
  unchanged command is a non-finding.
- **Base images and instance types:** is the pinned Ubuntu LTS still in standard
  support, do the image name filters and families still resolve, and are the
  instance types still offered in the default regions? Note upcoming
  end-of-support and retirement dates.
- **Bootstrap packages:** do the installed packages still exist under those names
  in the pinned Ubuntu release, and does anything fetched from outside the distro
  repositories still resolve?
- **Python:** is the documented `python3` floor still supported upstream, and do
  the policy scripts still rely only on the standard library?

Anything you cannot determine is a coverage gap, not a finding.

## Report Format

Open with the date checked and a one-line verdict. **If nothing needs changing,
say so and stop** — do not pad the table.

Then one row per surface that needs action:

| Priority | Cloud | Surface | Current pin | Current release | Why it matters | Evidence | Suggested action |
|----------|-------|---------|-------------|-----------------|----------------|----------|------------------|

- **Priority:** High for a breaking change already admitted by the constraint, a
  removed CLI command or changed output field, or a support deadline inside 6
  months. Medium for a trailing pin with a concrete benefit. Low for cosmetic or
  maintainability drift.
- **Evidence:** repository `path:line` plus the official URL and its date.
  Separate observed facts from inferred impact.
- **Suggested action:** the bounded edit, and how to verify it — typically a
  `terraform plan` or a full deploy-and-validate run, neither of which this skill
  performs.

Close with anything you could not check and why.
