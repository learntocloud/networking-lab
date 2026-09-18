---
name: review-lab-maintenance
description: Review networking lab maintenance across AWS, Azure, and GCP. Use when asked to assess Terraform and provider compatibility, cloud CLI changes, dependencies, image lifecycle, or lab documentation drift. Produce an evidence-backed maintainer report without modifying files or cloud resources.
---

# Review Lab Maintenance

Review the lab for changes maintainers should investigate, not for ways to solve
the student exercises. Default to all three clouds unless the user narrows scope.

## Guardrails

- Report only. Do not edit files, upgrade or install dependencies, deploy or
  destroy infrastructure, change cloud resources, or create issues or PRs.
- Do not run setup, validation, destroy, bootstrap, or solution scripts. Inspect
  them as source; live verification requires a separately authorized task.
- Do not run Terraform init, plan, apply, or destroy, or authenticate to cloud
  accounts as part of this review. Keep checks local and non-mutating.
- Preserve intentional misconfigurations. Establish each incident's intended
  fault from the guides and implementation before flagging it as a problem.
  An unclear boundary is a question to investigate, not an instruction to fix it.
- Do not inspect or disclose credentials, private keys, Terraform state, or
  generated tokens. Use public documentation queries without repository secrets
  or private code.
- Do not recommend an upgrade merely because a newer version exists. Explain
  the concrete compatibility, support, reliability, or student-experience benefit.

## Review Process

1. Read the root `README.md`, `CONTRIBUTING.md`, and the selected providers'
   `README.md` files.
   Identify prerequisites, incident requirements, and the documented student
   journey. Use repository-relative paths, never machine-specific paths.
2. Inventory the selected providers' `terraform/` and `scripts/` directories,
   including modules, VM bootstrap templates, and shared helpers in `scripts/`.
   Record declared version constraints and dependency sources. Distinguish
   declared versions, unpinned dependencies, and versions that cannot be determined;
   do not assume an installed local tool represents a student's environment.
3. Review the areas below against the actual implementation. Follow shared
   helpers and callers so a finding is not based on an isolated line.
4. Verify time-sensitive claims against current official documentation, release
   notes, migration guides, or lifecycle notices. Check applicability to the
   repository's version constraints, cloud, and configuration. Cite source URLs,
   relevant release or retirement dates, and the date checked. If sources are
   unavailable or inconclusive, disclose the gap instead of asserting a change.
5. Return the report in the conversation. Do not create a report file unless
   requested. Separate static evidence from behavior requiring live verification.

## Review Areas

| Area | Inspect |
|------|---------|
| Terraform | Terraform/provider constraints, deprecated resources and arguments, breaking changes applicable to allowed versions, module wiring, deployment and teardown assumptions. |
| Cloud CLIs | Commands and flags used by scripts and guides, authentication prerequisites, output parsing, pagination, exit handling, and documented CLI changes that affect these uses. |
| Dependencies | Local tools, VM image and OS support, package repositories, bootstrap packages and downloads, architecture assumptions, and reproducibility of unpinned dependencies. |
| Lab behavior | Whether setup prepares the documented faults, validation tests the actual acceptance criteria, incidents interact as intended, and teardown accounts for resources created while solving the lab. |
| Documentation | Whether prerequisites, commands, paths, expected results, and cleanup guidance agree with implementation. Compare clouds for unintended drift without requiring identical provider-specific designs. |

For lab behavior, trace setup through Terraform and bootstrap to validation and
cleanup. Do not treat Terraform alone as the setup workflow when provider scripts
perform additional preparation. A successful static check does not prove that
deployment, connectivity, completion-token generation, or cleanup works.

## Report Format

Start with the review date, scope, and a short overall assessment. Then provide
only actionable findings, ordered by student impact and urgency:

| Priority | Evidence status | Cloud | Finding and student impact | Repository evidence | Official source | Suggested action |
|----------|-----------------|-------|----------------------------|---------------------|-----------------|------------------|

- **Priority:** High for likely blockers or imminent support deadlines; Medium
  for credible reliability or maintenance risks; Low for minor documentation or
  maintainability issues. Explain the priority rather than relying on the label.
- **Evidence status:** Confirmed problem, upcoming lifecycle risk, or needs live
  verification. Use confirmed only when the available evidence establishes it.
- **Evidence:** Cite repository `path:line` references and applicable official
  URLs with dates. For purely internal inconsistencies, mark the official source
  as not applicable. Separate observed facts from inferred impact.
- **Suggested action:** Give a bounded next step and how a maintainer could
  verify it. Do not silently turn the recommendation into an implementation.

Finish with coverage gaps: areas not reviewed, unavailable sources or tools, and
specific checks requiring an authorized live lab. If there are no actionable
findings, say so; do not invent recommendations to fill the table.
