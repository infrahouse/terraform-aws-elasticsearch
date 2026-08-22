# Task: enable `defer_inspector_findings_until_patched` on both ASGs + grant `ec2:DeleteTags`

**Status:** implemented in the working tree on 2026-08-22. Not committed, not released, not applied.

## Why

AWS Inspector reports findings against a freshly launched instance before `unattended-upgrades` has run.
The finding closes on the next upgrade, but it has already **reopened its vulnerability group** by then, and
a group old enough to be reopened that way breaks the remediation SLA.

```
launch  -> instance tagged InspectorEc2Exclusion   (website-pod, flag off by default)
boot    -> apt-get update && unattended-upgrade    (puppet-code, profile::boot_security_upgrade)
success -> aws ec2 delete-tags Key=InspectorEc2Exclusion   (needs IAM from THIS module)
        -> Inspector's first findings describe a patched host
```

Shipped this way already: `terraform-aws-jumphost` v6.1.0, `terraform-aws-openvpn` v10.2.0,
`terraform-aws-bookstack` v4.3.0.

## Prerequisites — both satisfied

1. **puppet-code #299** — `role::elastic_master` and `role::elastic_data` include
   `profile::boot_security_upgrade`. Must be **deployed to the instances**, not just merged. That is the only
   thing that removes the tag; the tag is fail-open and an instance that keeps it is permanently invisible to
   Inspector.
2. **website-pod v6.5.0** — adds `defer_inspector_findings_until_patched`. This module pins **6.4.0** in both
   places, so it needs a bump.

## ⚠️ Two instantiations. Both, or neither.

`main.tf` instantiates website-pod **twice**:

| block | line | `asg_name` |
|---|---|---|
| `module "elastic_cluster"` (master) | ~112 | `var.cluster_name` |
| `module "elastic_cluster_data"` (data) | ~193 | `"${var.cluster_name}-data"` |

Flipping only one leaves half the cluster untagged — no breakage, just silently incomplete coverage that
looks done. Bump `version` to `6.5.0` and add to **both**:

```hcl
  # Suppress Inspector findings until profile::boot_security_upgrade has applied
  # pending security updates and removed the tag. REQUIRES the ec2:DeleteTags
  # statement in iam.tf -- see .claude/plans/inspector-findings-deferral.md.
  defer_inspector_findings_until_patched = true
```

Do **not** route this through the `tags` argument instead. It would work, but website-pod merges `var.tags`
into `default_module_tags`, which is applied to the ALB, S3 access-log buckets, every security group, the
alarms, Glue, ACM and IAM — stamping `InspectorEc2Exclusion` on an S3 bucket.

## The IAM statement (`iam.tf`) — one statement covers both

Both instantiations pass the **same** `instance_profile_permissions =
data.aws_iam_policy_document.elastic_permissions.json` (`main.tf` lines ~133 and ~216), so a single statement
in `elastic_permissions` covers master and data:

```hcl
  # profile::boot_security_upgrade removes this tag once security updates are
  # applied, so Inspector's first findings describe a patched host. Scoped to this
  # tag key, to instances, and to instances in this cluster's two ASGs.
  statement {
    actions   = ["ec2:DeleteTags"]
    resources = ["arn:aws:ec2:*:${data.aws_caller_identity.current.account_id}:instance/*"]
    condition {
      test     = "ForAllValues:StringEquals"
      variable = "aws:TagKeys"
      values   = ["InspectorEc2Exclusion"]
    }
    condition {
      test     = "StringEquals"
      variable = "ec2:ResourceTag/aws:autoscaling:groupName"
      values   = [var.cluster_name, "${var.cluster_name}-data"]
    }
  }
```

**This module gets the cleanest scoping of any so far.** Both ASG names are passed explicitly as
`asg_name` and derive from `var.cluster_name` alone — pure variable interpolation, no resource references —
so the `aws:autoscaling:groupName` condition carries **no ordering hazard**. Contrast:

- openvpn had to use `local.asg_name` deliberately, because `aws_autoscaling_group.*.name` would order the
  grant after the ASG began launching tagged instances.
- bookstack could not use ASG-name scoping at all (website-pod generates the name from `name_prefix`) and
  fell back to `created_by_module`.

The existing `autoscaling:CompleteLifecycleAction` statement already builds ARNs from exactly these two
names, so the pattern is established in this file.

## Elastic-specific: the restart suppression is fine

`profile::elastic::service` keeps `unattended-upgrades` running but must never bounce the ES process. Two
carve-outs, both declarative and honoured no matter who invokes `unattended-upgrade`:

- `/etc/apt/apt.conf.d/53-elasticsearch-blacklist` blacklists the `elasticsearch` package
- a needrestart list-only drop-in prevents automatic service restarts after library upgrades

Boot-time patching does not need a special ordering edge against either — see puppet-code #299 for the
reasoning. The blacklist is belt-and-braces here anyway: nothing in puppet-code sets `Allowed-Origins` or
`Origins-Pattern`, so only Ubuntu's defaults apply and elastic.co is not among them.

## ⚠️ The gotcha that matters here: instance refresh moves shards

website-pod's ASG carries `instance_refresh { triggers = ["tag"] }`. Enabling the flag **triggers a rolling
instance refresh on both ASGs** — and on an Elasticsearch cluster that is not a cosmetic instance cycle, it
is a data-movement event. Every other module in this rollout got a plain roll; this one relocates shards.

`profile::elastic::service` has a `decommission-node` cron that runs `ih-elastic cluster decommission-node
--only-if-terminating` and completes the lifecycle hook once shards have moved off, so the machinery to do
this safely exists. Still:

- Plan the apply like a cluster roll, not a tag change.
- Do the **master** ASG and the **data** ASG as separate applies if you want to bound blast radius, rather
  than flipping both flags in one change. The end state is the same; only the rollout differs.
- A green cluster before starting is the precondition.

## Other notes

- **`data.aws_region.current.name` is used in `iam.tf`.** Deprecated in AWS provider v6 in favour of
  `.region`. Not introduced by this change, but if the module is on v6 it will warn.
- **Multi-instance, so the detector works here.** The cohort-relative check proposed in
  `loopproof/docs/inspector-exclusion-reconciliation-lag.md` needs a same-AMI sibling reporting findings > 0.
  With three masters and three data nodes this cluster is a good candidate — unlike BookStack or terraformer,
  which are singletons and structurally invisible to it.
- **`instance_metadata_tags = "enabled"`** is already set by website-pod, so a future puppet-code change
  could read `GET /latest/meta-data/tags/instance/InspectorEc2Exclusion` before deleting and log
  `removed` vs `was not set` distinctly — no extra IAM.

## Checklist

- [x] `main.tf` — bump both website-pod blocks to `6.5.0`
- [x] `main.tf` — `defer_inspector_findings_until_patched = true` on **both**
- [x] `iam.tf` — the `ec2:DeleteTags` statement (one, shared)
- [x] `make lint` (`terraform fmt --check -recursive`), `terraform validate` on `test_data/test_module`, and
      checkov are all clean. `make format` is deliberately NOT run wholesale: black 25.1.0 reflows the
      `dedent()` calls that the committed test files were formatted with by an older black, so it rewrites
      `tests/conftest.py` and unrelated hunks of `tests/test_module.py`. The new test code is black-clean on
      its own — pre-existing drift, not this change's to fix.
- [x] Tests — `verify_inspector_exclusion_tag_removed()` in `tests/test_module.py`, called for the master and
      the data ASG. Asserts both halves: `ASG.launch_tags` carries the tag, and the tag is gone from a
      bootstrapped instance. Polls on a 15s interval (longer than `EC2Instance`'s 10s describe cache) for up
      to 60s, and dumps the `InspectorEc2Exclusion` lines from `cloud-init-output.log` on failure.
      `requirements.txt` bumped to `infrahouse-core ~= 1.3` (`ASG.launch_tags`, `wait_for_bootstrap()`).
- [x] `terraform-docs` regen
- [x] Docs, beyond the original checklist — a "Patching and AWS Inspector" section and an `ec2:DeleteTags`
      bullet in `docs/architecture.md`, and a "Node missing from Inspector findings" entry in
      `docs/troubleshooting.md`.
- [ ] `bumpversion minor` + CHANGELOG — left for the release, along with the commit. Nothing is applied yet;
      see the instance-refresh warning above before planning the apply.

## Verification

Puppet log on a fresh node shows one of:

- `removed InspectorEc2Exclusion from i-...` — the API call succeeded
- `could not remove ... (no ec2:DeleteTags?)` — the IAM statement is wrong or missing

The first does not prove a tag was removed (`delete-tags` ignores a missing key). Confirm with
`aws ec2 describe-tags --filters Name=resource-id,Values=i-...` on a node from **each** ASG.

Then expect findings **~1.5–2h of running time** after removal, not immediately. Measure with
`firstObservedAt`, never `lastScannedAt` — the latter overstates the window badly.
