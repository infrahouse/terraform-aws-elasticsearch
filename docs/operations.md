# Operations

Day-to-day cluster management uses
[infrahouse-toolkit](https://github.com/infrahouse/infrahouse-toolkit),
specifically the `ih-elastic` command. It is pre-installed on every
cluster node by Puppet.

## ih-elastic overview

```bash
ih-elastic [OPTIONS] COMMAND [ARGS]...
```

| Option | Description |
|--------|-------------|
| `--debug` | Enable debug logging |
| `--quiet` | Suppress info messages, only show warnings and errors |
| `--username TEXT` | Elasticsearch username (default: `elastic`) |
| `--password TEXT` | Password (auto-read from Puppet facts / Secrets Manager) |
| `--password-secret TEXT` | AWS Secrets Manager secret id with the password |
| `--es-protocol TEXT` | Protocol (default: `http`) |
| `--es-host TEXT` | Elasticsearch host (default: `127.0.1.1`) |
| `--es-port INTEGER` | Port (default: `9200`) |
| `--format [text/json/cbor/yaml/smile]` | Output format |

All commands below are run **on a cluster node** (SSH in first).
The tool auto-discovers credentials from Puppet facts or Secrets Manager,
so you typically don't need to pass `--password`.

## Check cluster health

```bash
ih-elastic cluster-health
```

Example output:

```json
{
    "cluster_name": "elastic",
    "status": "green",
    "number_of_nodes": 6,
    "number_of_data_nodes": 3,
    "active_primary_shards": 167,
    "active_shards": 433,
    "relocating_shards": 0,
    "initializing_shards": 0,
    "unassigned_shards": 0,
    "active_shards_percent_as_number": 100.0
}
```

This is the first thing to run when diagnosing issues. A healthy cluster
shows `"status": "green"` and zero unassigned/relocating shards.

## Inspect shards

```bash
ih-elastic cat shards
```

Lists all shards and which nodes they're allocated to. Useful for spotting
unbalanced shard distribution or unassigned shards.

## Diagnose allocation problems

```bash
ih-elastic cluster allocation-explain \
  --index <index-name> \
  --shard <shard-id> \
  --primary
```

When shards are unassigned, this explains **why** Elasticsearch can't
allocate them. Use `ih-elastic cat shards` first to find the problematic
index and shard ID.

| Option | Description |
|--------|-------------|
| `--index TEXT` | Index name (from `ih-elastic cat shards`) |
| `--shard INTEGER` | Shard ID |
| `--primary / --replica` | Explain primary or replica shard |

## Connecting to the cluster

### Via ALB (external access)

The module creates HTTPS endpoints behind Application Load Balancers.
Use the `elastic` superuser password from Secrets Manager:

```bash
# Get the password
ELASTIC_PASSWORD=$(aws secretsmanager get-secret-value \
  --secret-id "$(terraform output -raw elastic_secret_id)" \
  --query SecretString --output text)

# Query the cluster
curl -u "elastic:${ELASTIC_PASSWORD}" \
  "https://my-cluster.example.com/_cluster/health?pretty"
```

| Endpoint | Points to |
|----------|-----------|
| `https://{cluster_name}.{zone}` | Master nodes (primary) |
| `https://{cluster_name}-master.{zone}` | Master nodes (explicit) |
| `https://{cluster_name}-data.{zone}` | Data nodes |

The ALB terminates TLS (Let's Encrypt certificates). Traffic from the
ALB to instances is HTTP on port 9200.

### Via SSH (on-node access)

SSH into any cluster node and use `ih-elastic` directly. No password
needed -- credentials are auto-discovered from Puppet facts:

```bash
ssh ubuntu@<instance-ip>
ih-elastic cluster-health
ih-elastic api GET /_cat/nodes?v
```

### Anonymous monitoring access

The cluster configures an `anonymous_monitor` role that allows
unauthenticated read access to monitoring endpoints. This enables
Prometheus exporters to scrape metrics without credentials.

## Node discovery and configuration

Nodes discover each other using the
[discovery-ec2](https://www.elastic.co/guide/en/elasticsearch/plugins/current/discovery-ec2.html)
plugin. Puppet installs it automatically. Discovery is based on EC2 tags:

- `cluster` tag matches `var.cluster_name`
- `environment` tag matches `var.environment`

Each node is **availability-zone aware** -- Elasticsearch uses the
`zone` node attribute for
[shard allocation awareness](https://www.elastic.co/guide/en/elasticsearch/reference/current/modules-cluster.html#shard-allocation-awareness),
distributing primary and replica shards across AZs.

### Key configuration (`/etc/elasticsearch/elasticsearch.yml`)

| Setting | Value |
|---------|-------|
| `network.host` | `_ec2_` (binds to the instance's private IP) |
| `discovery.seed_providers` | `ec2` |
| `cluster.routing.allocation.awareness.attributes` | `zone` |
| `xpack.security.enabled` | `true` |
| `xpack.security.transport.ssl.enabled` | `true` (inter-node TLS) |
| `xpack.security.http.ssl.enabled` | `false` (ALB handles HTTPS) |
| `xpack.security.audit.enabled` | `true` |
| `bootstrap.memory_lock` | `true` (when `var.memory_lock = true`) |

### JVM heap sizing

Puppet sets the JVM heap to **50% of instance RAM** automatically
(`/etc/elasticsearch/jvm.options.d/heap.options`). The other 50% is
left for Lucene filesystem cache and the OS. This is the Elasticsearch
recommended split.

## TLS certificates

Inter-node transport (port 9300) is encrypted with TLS. The certificate
chain is:

1. **CA cert/key** -- generated by Terraform (`tls_self_signed_cert`),
   stored in Secrets Manager, shared by all nodes.
2. **Node cert/key** -- generated on each instance by Puppet using
   `openssl`. The node cert is signed by the CA cert.

Puppet reads the CA cert and key from Secrets Manager and generates a
per-node certificate at `/etc/elasticsearch/tls/`. Certificates are
valid for 10 years.

HTTP (port 9200) does **not** use node-level TLS -- the ALB terminates
HTTPS with Let's Encrypt certificates instead.

## Node lifecycle

The module uses ASG lifecycle hooks to safely add and remove nodes.
These commands are called automatically by cloud-init / Puppet, but
you can also invoke them manually.

### Commission a node

```bash
ih-elastic cluster commission-node \
  --complete-lifecycle-action <hook-name>
```

Called automatically when a new instance launches. It:

1. Waits for shard relocation to finish (up to 48 hours by default).
2. Extends the ASG lifecycle heartbeat while waiting.
3. Completes the lifecycle hook so the ASG marks the instance as healthy.

| Option | Description |
|--------|-------------|
| `--wait-until-complete INTEGER` | Max wait seconds (default: 172800) |
| `--complete-lifecycle-action TEXT` | Lifecycle hook name to complete |

### Decommission a node

```bash
ih-elastic cluster decommission-node \
  --reason "instance refresh" \
  --complete-lifecycle-action \
  --only-if-terminating
```

Called automatically when the ASG terminates an instance. It:

1. Checks cluster health is green (aborts if not, to prevent data loss).
2. Registers a node shutdown with Elasticsearch so shards migrate away.
3. Waits for shard migration to complete (up to 1 hour by default).
4. Completes the terminating lifecycle hook.

| Option | Description |
|--------|-------------|
| `--reason TEXT` | Why the node is being decommissioned (required) |
| `--only-if-terminating` | Only act if instance is in `Terminating:Wait` |
| `--wait-until-complete INTEGER` | Max wait seconds (default: 3600) |
| `--complete-lifecycle-action` | Complete the lifecycle hook when done |

!!! warning
    If the cluster status is not green, decommission-node refuses to proceed
    and cancels the instance refresh. This prevents cascading failures.

## Snapshots and backups

The module creates an S3 bucket for snapshots and Puppet registers it as
a repository named `backups`. Backups are fully automated via
[Elasticsearch SLM](https://www.elastic.co/guide/en/elasticsearch/reference/current/snapshot-lifecycle-management.html)
(Snapshot Lifecycle Management) policies.

### Automated backup schedule

Puppet configures four SLM policies:

| Policy | Schedule | Retention | Max snapshots |
|--------|----------|-----------|---------------|
| `hourly-snapshots` | Every hour | 48 hours | 48 |
| `daily-snapshots` | Daily at 01:30 UTC | 14 days | 14 |
| `weekly-snapshots` | Monday at 01:30 UTC | 60 days | 8 |
| `monthly-snapshots` | 1st of month at 01:30 UTC | 365 days | 12 |

All snapshots include global state and are stored in the S3 `backups`
repository. Older snapshots are automatically deleted per the retention
rules.

### List snapshots

```bash
ih-elastic cat snapshots
```

Example output:

```
id                                 repository  status start_epoch start_time end_epoch  end_time duration indices
elastic-2024-02-20_19-19-54.544449 backups    SUCCESS 1708456794  19:19:54   1708456796 19:19:56     1.8s      33
elastic-2024-02-20_19-43-51.722634 backups    SUCCESS 1708458231  19:43:51   1708458233 19:43:53     1.6s      33
```

### Manual snapshots

```bash
ih-elastic snapshots <subcommand>
```

| Subcommand | Description |
|------------|-------------|
| `create` | Create a snapshot in a repository |
| `restore` | Restore a snapshot |
| `status` | Check snapshot progress |
| `create-repository` | Register a new snapshot repository |
| `delete-repository` | Remove a snapshot repository |

Take a manual snapshot:

```bash
ih-elastic snapshots create --repository backups
```

Restore from a snapshot:

```bash
ih-elastic snapshots restore --repository backups --snapshot <snapshot-id>
```

## Change passwords

```bash
ih-elastic passwd --user elastic
ih-elastic passwd --user kibana_system
```

Changes the password for an Elasticsearch user. The new password is
auto-generated and stored in Secrets Manager.

## Raw API calls

For any Elasticsearch API not covered by `ih-elastic` subcommands:

```bash
ih-elastic api GET /_cat/nodes?v
ih-elastic api GET /_cluster/settings?pretty
ih-elastic api PUT /_cluster/settings -d '{"persistent":{"cluster.routing.allocation.enable":"all"}}'
```

## Automatic decommission cron

Puppet installs a cron job on every node that runs every 5 minutes:

```
*/5 * * * * ih-elastic --quiet cluster decommission-node \
  --only-if-terminating --reason instance_refresh \
  --complete-lifecycle-action --wait-until-complete 172800
```

This ensures that when the ASG starts terminating an instance (e.g.,
during an instance refresh), the node gracefully drains its shards
before the instance is actually terminated. The `--only-if-terminating`
flag means the cron is a no-op on healthy running nodes.

## Prometheus monitoring

Each node runs two Prometheus exporters:

- **prometheus-node-exporter** (port 9100) -- system metrics
  (CPU, memory, disk, network)
- **prometheus-elasticsearch-exporter** (port 9114) -- Elasticsearch
  cluster and node metrics

The module creates a security group
(`var.monitoring_cidr_block`) that allows scraping from your monitoring
network. Configure your Prometheus to scrape:

```yaml
scrape_configs:
  - job_name: elasticsearch-nodes
    static_configs:
      - targets:
          - <node-ip>:9100  # node exporter
          - <node-ip>:9114  # elasticsearch exporter
```

The elasticsearch exporter authenticates to Elasticsearch using the
`elastic` superuser password (read from Secrets Manager) and connects
over the local loopback interface.

## Kibana

To add a web UI for your cluster, use the
[terraform-aws-kibana](https://github.com/infrahouse/terraform-aws-kibana)
module. It deploys Kibana on ECS with an ALB, auto-provisioned TLS, and
Route53 DNS -- pointing at your Elasticsearch cluster.

```hcl
module "kibana" {
  source  = "registry.infrahouse.com/infrahouse/kibana/aws"
  version = "2.0.0"

  providers = {
    aws     = aws
    aws.dns = aws
  }

  elasticsearch_cluster_name = "my-cluster"
  elasticsearch_url          = module.elasticsearch.cluster_master_url
  kibana_system_password     = module.elasticsearch.kibana_system_password

  environment   = "production"
  zone_id       = data.aws_route53_zone.main.zone_id
  subnet_ids    = module.service-network.subnet_private_ids
  key_pair_name = aws_key_pair.my_key.key_name
  alarm_emails  = ["ops-team@example.com"]
}
```

After deployment, Kibana is available at `https://kibana.{zone}`.

## Installing infrahouse-toolkit

`ih-elastic` is pre-installed on cluster nodes. To install it elsewhere
(e.g., a bastion host):

```bash
pip install infrahouse-toolkit
```

When running from a remote host, pass connection details:

```bash
ih-elastic \
  --es-protocol https \
  --es-host my-cluster.example.com \
  --es-port 443 \
  --password-secret <elastic_secret_id> \
  cluster-health
```