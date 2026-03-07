# Troubleshooting

## GC pressure and swap

### Symptoms

- `JvmGcMonitorService` logging GC overhead (e.g., "spent [5.2s] collecting in the last [5.4s]")
- `ConnectionTimeout` on local API calls (`_nodes/_local`)
- `ih-elastic cluster decommission-node` failing during instance refreshes
- Timer thread sleeping above the 5000ms warn threshold

### Diagnosis

SSH into the node and check:

```bash
# Is the node swapping?
free -h

# Is ES using swap?
cat /proc/$(pgrep -f 'elasticsearch.*java' | tail -1)/status | grep VmSwap

# Is memory_lock enabled?
ih-elastic api GET /_nodes/_local/process?pretty | grep mlockall

# Check systemd memory limit
systemctl show elasticsearch | grep LimitMEMLOCK

# Check ES config
grep memory_lock /etc/elasticsearch/elasticsearch.yml

# Check recent GC activity
tail -100 /var/log/elasticsearch/*.log | grep -E "gc|GC|overhead"
```

### Causes and fixes

**Cause 1: `memory_lock` not enabled (mlockall: false)**

The JVM heap is being swapped to disk. When GC touches swapped pages, 50ms pauses
become multi-second pauses.

Fix: upgrade to module >= 4.1.0 which sets `memory_lock = true` by default.
Verify with:

```bash
ih-elastic api GET /_nodes/_local/process?pretty | grep mlockall
# Should show: "mlockall": true
```

**Cause 2: Instance too small**

With `memory_lock = true`, the JVM heap is locked in RAM. If the instance doesn't
have enough memory for heap + OS + Lucene cache, the OOM killer will terminate ES.

Fix: use at least `t3.large` (8 GB). See the
[instance sizing table](index.md#instance-sizing).

Check current memory:

```bash
free -h
cat /etc/elasticsearch/jvm.options.d/*.options  # shows heap size
```

**Cause 3: `LimitMEMLOCK` not set to infinity**

ES config has `bootstrap.memory_lock: true` but the systemd limit is too low.
ES will fail to start or start without mlockall.

Fix: verify the systemd override exists:

```bash
systemctl show elasticsearch | grep LimitMEMLOCK
# Should show: LimitMEMLOCK=infinity
```

If not, the Puppet code needs updating (infrahouse/puppet-code#255).

## Node won't join the cluster

### Symptoms

- ASG instance refresh stuck / lifecycle hook timing out
- Node is running but not visible in `_cat/nodes`
- `ih-elastic cluster commission-node` failing

### Diagnosis

```bash
# Check cloud-init completed
tail -50 /var/log/cloud-init-output.log

# Check ES is running
systemctl status elasticsearch

# Check ES logs for join errors
tail -200 /var/log/elasticsearch/*.log | grep -E "join|master|discovery"

# Check the node can reach other nodes
ih-elastic api GET /_cluster/health?pretty
```

### Common causes

**Discovery failure**: the node can't find existing master nodes. Check security
groups allow port 9300 (transport) between all ES nodes. The module places all
nodes in the same backend security group with inter-SG traffic allowed.

**Certificate mismatch**: if the CA cert/key secrets were recreated (e.g., by
destroying and recreating the cluster without clearing secrets), existing nodes
have different CA certs than new nodes. Fix: ensure all nodes share the same
CA certificate from Secrets Manager.

**Bootstrap lock**: if `bootstrap_mode = true` is still set after initial bootstrap,
only 1 master node will be created. Set `bootstrap_mode = false` and re-apply.

## Lifecycle hook timeout

### Symptoms

- Instance stuck in `Pending:Wait` state
- ASG instance refresh shows `InProgress` for > 1 hour

### Diagnosis

SSH into the pending instance:

```bash
# Check if cloud-init is still running
cloud-init status

# Check if Puppet is still running
ps aux | grep puppet

# Check if ih-elastic is waiting for something
ps aux | grep ih-elastic

# Check cloud-init log for errors
tail -100 /var/log/cloud-init-output.log
```

The lifecycle hook has a 3600s (1 hour) timeout with `ABANDON` as the default action.
If the node doesn't complete the hook in time, the ASG terminates it and tries again.

### Common causes

- Puppet run failed (check `/var/log/cloud-init-output.log`)
- ES took too long to start (check `/var/log/elasticsearch/*.log`)
- The node couldn't reach the cluster (security group / network issue)

## CloudWatch logs missing

### Diagnosis

```bash
# Check if the CloudWatch agent or logging is configured
grep cloudwatch_log_group /etc/facter/facts.d/*.json

# Check instance IAM permissions
aws logs create-log-stream \
  --log-group-name "/elasticsearch/production/my-cluster" \
  --log-stream-name "test-stream" \
  --region us-west-2
```

### Common causes

- `enable_cloudwatch_logging = false` in the module
- Instance profile missing CloudWatch permissions (check IAM role in EC2 console)
- KMS key policy doesn't allow the instance role to encrypt logs

## Snapshot failures

### Diagnosis

```bash
# Check snapshot repository is registered
ih-elastic api GET /_snapshot/_all?pretty

# Check S3 bucket access
aws s3 ls s3://<snapshots-bucket-name>/
```

### Common causes

- Instance profile missing S3 permissions for the snapshots bucket
- S3 bucket policy doesn't allow the instance role
- Snapshot repository not registered in ES (Puppet should handle this)
