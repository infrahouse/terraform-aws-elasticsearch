import json
import os
import shutil
import time
from os import path as osp
from textwrap import dedent

import boto3
import pytest
from infrahouse_core.aws.asg import ASG
from pytest_infrahouse import terraform_apply

from tests.conftest import (
    LOG,
    TERRAFORM_ROOT_DIR,
    bootstrap_cluster,
)


def wait_for_instance_refresh(
    asg_name, aws_region, test_role_arn, boto3_session, timeout=600
):
    """
    Wait for any in-progress ASG instance refreshes to complete.

    :param asg_name: Name of the Auto Scaling Group
    :param aws_region: AWS region
    :param test_role_arn: IAM role ARN to assume (optional)
    :param boto3_session: boto3 session with appropriate credentials
    :param timeout: Maximum time to wait in seconds (default 600 = 10 minutes)
    """
    LOG.info("=" * 80)
    LOG.info("Checking for in-progress ASG instance refreshes")
    LOG.info("=" * 80)

    # Create ASG client from boto3_session
    asg_client = boto3_session.client("autoscaling", region_name=aws_region)

    start_time = time.time()
    last_status = None

    while time.time() - start_time < timeout:
        try:
            # Check for instance refreshes
            response = asg_client.describe_instance_refreshes(
                AutoScalingGroupName=asg_name, MaxRecords=10
            )

            instance_refreshes = response.get("InstanceRefreshes", [])

            # Filter for in-progress refreshes
            in_progress = [
                ir
                for ir in instance_refreshes
                if ir["Status"]
                in ["Pending", "InProgress", "Cancelling", "RollbackInProgress"]
            ]

            if not in_progress:
                if last_status is not None:
                    LOG.info("All instance refreshes completed")
                else:
                    LOG.info("No in-progress instance refreshes found")
                LOG.info("=" * 80)
                return

            # Log status of in-progress refreshes
            for refresh in in_progress:
                refresh_id = refresh["InstanceRefreshId"]
                status = refresh["Status"]
                percentage = refresh.get("PercentageComplete", 0)

                status_msg = (
                    f"Instance refresh {refresh_id}: {status} ({percentage}% complete)"
                )
                if status_msg != last_status:
                    LOG.info(status_msg)
                    last_status = status_msg

            time.sleep(10)  # Check every 10 seconds

        except Exception as e:
            LOG.warning("Error checking instance refresh status: %s", e)
            LOG.warning("Continuing anyway...")
            break

    if time.time() - start_time >= timeout:
        LOG.warning("Timeout waiting for instance refresh to complete")
        LOG.warning("Continuing anyway...")

    LOG.info("=" * 80)


@pytest.mark.parametrize(
    "aws_provider_version", ["~> 5.11", "~> 6.0"], ids=["aws-5", "aws-6"]
)
def test_module(
    service_network,
    subzone,
    aws_region,
    keep_after,
    test_role_arn,
    aws_provider_version,
    boto3_session,
):
    subzone_id = subzone["subzone_id"]["value"]

    subnet_public_ids = service_network["subnet_public_ids"]["value"]
    subnet_private_ids = service_network["subnet_private_ids"]["value"]
    internet_gateway_id = service_network["internet_gateway_id"]["value"]

    # Bootstrap ES cluster
    terraform_module_dir = osp.join(TERRAFORM_ROOT_DIR, "test_module")

    # Clean up any existing Terraform state and lock files to ensure clean provider version switch
    try:
        shutil.rmtree(osp.join(terraform_module_dir, ".terraform"))
    except (FileNotFoundError, NotADirectoryError):
        pass

    try:
        os.remove(osp.join(terraform_module_dir, ".terraform.lock.hcl"))
    except FileNotFoundError:
        pass

    # Update terraform.tf with the specified AWS provider version
    terraform_tf_path = osp.join(terraform_module_dir, "terraform.tf")
    with open(terraform_tf_path, "w") as fp:
        fp.write(
            dedent(
                f"""
                terraform {{
                  //noinspection HILUnresolvedReference
                  required_providers {{
                    aws = {{
                      source  = "hashicorp/aws"
                      version = "{aws_provider_version}"
                    }}
                  }}
                }}
                """
            )
        )

    with bootstrap_cluster(
        service_network, subzone, keep_after, aws_region, test_role_arn, "test_module"
    ):
        # Create remaining master & data nodes
        bootstrap_mode = False
        with open(osp.join(terraform_module_dir, "terraform.tfvars"), "w") as fp:
            fp.write(
                dedent(
                    f"""
                    region          = "{aws_region}"
                    elastic_zone_id = "{subzone_id}"
                    bootstrap_mode  = {str(bootstrap_mode).lower()}

                    lb_subnet_ids       = {json.dumps(subnet_public_ids)}
                    backend_subnet_ids  = {json.dumps(subnet_private_ids)}
                    internet_gateway_id = "{internet_gateway_id}"
                    """
                )
            )
            if test_role_arn:
                fp.write(
                    dedent(
                        f"""
                        role_arn        = "{test_role_arn}"
                        """
                    )
                )

        with terraform_apply(
            terraform_module_dir,
            destroy_after=not keep_after,
            json_output=True,
        ) as tf_output:
            LOG.info(json.dumps(tf_output, indent=4))

            # Wait for any instance refreshes to complete
            master_asg_name = tf_output["master_asg_name"]["value"]
            data_asg_name = tf_output["data_asg_name"]["value"]

            assert master_asg_name, "Master ASG name must be present in outputs"
            assert data_asg_name, "Data ASG name must be present in outputs"

            wait_for_instance_refresh(
                master_asg_name, aws_region, test_role_arn, boto3_session, timeout=3600
            )
            wait_for_instance_refresh(
                data_asg_name, aws_region, test_role_arn, boto3_session, timeout=3600
            )

            # Test CloudWatch logging functionality
            _test_cloudwatch_logging(
                tf_output, aws_region, test_role_arn, boto3_session
            )


def _test_cloudwatch_logging(tf_output, aws_region, test_role_arn, boto3_session):
    """
    Test that instances can write to CloudWatch Logs.

    Uses the ASG class to get a master node instance and executes
    AWS CLI commands to verify CloudWatch logging permissions.
    """
    log_group_name = tf_output.get("cloudwatch_log_group_name", {}).get("value")
    master_asg_name = tf_output.get("master_asg_name", {}).get("value")

    assert log_group_name, "CloudWatch log group name must be present in outputs"
    assert master_asg_name, "Master ASG name must be present in outputs"

    LOG.info(f"Testing CloudWatch logging for ASG: {master_asg_name}")
    LOG.info(f"Log group: {log_group_name}")

    # Get an instance from the master ASG
    asg = ASG(master_asg_name, region=aws_region, role_arn=test_role_arn)
    test_instance = asg.instances[0]
    LOG.info(f"Testing on instance: {test_instance.instance_id}")

    # Create AWS clients from boto3_session fixture (ensures correct role)
    logs_client = boto3_session.client("logs", region_name=aws_region)

    # Generate unique log stream name
    timestamp = int(time.time())
    log_stream_name = f"integration-test-{test_instance.instance_id}-{timestamp}"

    # Test 1: Create log stream
    LOG.info("Creating test log stream...")
    command = f"""
    aws logs create-log-stream \
      --log-group-name '{log_group_name}' \
      --log-stream-name '{log_stream_name}' \
      --region {aws_region}
    """
    r_code, cout, cerr = test_instance.execute_command(command)
    assert r_code == 0, f"Failed to create log stream: {cerr}"
    LOG.info(f"✓ Created log stream: {log_stream_name}")

    # Test 2: Write log events
    LOG.info("Writing test log events...")
    test_message_1 = (
        f"Integration test event 1 from {test_instance.instance_id} at {timestamp}"
    )
    test_message_2 = (
        f"Integration test event 2 from {test_instance.instance_id} at {timestamp}"
    )

    # Write first log event
    command = f"""
    aws logs put-log-events \
      --log-group-name '{log_group_name}' \
      --log-stream-name '{log_stream_name}' \
      --log-events timestamp=$(date +%s000),message='{test_message_1}' \
      --region {aws_region}
    """
    r_code, cout, cerr = test_instance.execute_command(command)
    assert r_code == 0, f"Failed to write first log event: {cerr}"
    LOG.info("✓ Successfully wrote first log event")

    time.sleep(1)  # Ensure second event has a later timestamp

    # Write second log event
    command = f"""
    aws logs put-log-events \
      --log-group-name '{log_group_name}' \
      --log-stream-name '{log_stream_name}' \
      --log-events timestamp=$(date +%s000),message='{test_message_2}' \
      --region {aws_region}
    """
    r_code, cout, cerr = test_instance.execute_command(command)
    assert r_code == 0, f"Failed to write second log event: {cerr}"
    LOG.info("✓ Successfully wrote second log event")

    # Test 3: Verify log events
    LOG.info("Verifying log events...")
    time.sleep(3)  # Give CloudWatch time to process

    events_response = logs_client.get_log_events(
        logGroupName=log_group_name,
        logStreamName=log_stream_name,
        limit=10,
    )

    events = events_response.get("events", [])
    assert len(events) >= 2, f"Expected at least 2 log events, found {len(events)}"

    messages = [event["message"] for event in events]
    assert test_message_1 in messages, f"Test message 1 not found. Got: {messages}"
    assert test_message_2 in messages, f"Test message 2 not found. Got: {messages}"
    LOG.info(f"✓ Verified {len(events)} log events")
    LOG.info(f"  - Event 1: {test_message_1}")
    LOG.info(f"  - Event 2: {test_message_2}")

    # Test 4: Verify KMS encryption
    LOG.info("Verifying KMS encryption...")
    log_group_response = logs_client.describe_log_groups(
        logGroupNamePrefix=log_group_name,
        limit=1,
    )

    log_groups = log_group_response.get("logGroups", [])
    assert len(log_groups) > 0, "Log group not found"

    kms_key_id = log_groups[0].get("kmsKeyId")
    assert kms_key_id, "KMS encryption not enabled on log group"
    LOG.info(f"✓ Log group encrypted with KMS: {kms_key_id}")

    LOG.info("✓ All CloudWatch logging tests passed!")
