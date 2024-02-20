import json
from os import path as osp
from textwrap import dedent

import pytest
from infrahouse_toolkit.terraform import terraform_apply

from tests.conftest import (
    LOG,
    TRACE_TERRAFORM,
    DESTROY_AFTER,
    TEST_ZONE,
    TEST_ROLE_ARN,
    REGION,
)


def test_module(ec2_client, route53_client, autoscaling_client):
    terraform_root_dir = "test_data"

    # Create DNS zone
    terraform_module_dir = osp.join(terraform_root_dir, "dns")
    with open(osp.join(terraform_module_dir, "terraform.tfvars"), "w") as fp:
        fp.write(
            dedent(
                f"""
                parent_zone_name = "{TEST_ZONE}"
                role_arn = "{TEST_ROLE_ARN}"
                region = "{REGION}"
                """
            )
        )
    with terraform_apply(
        terraform_module_dir,
        destroy_after=DESTROY_AFTER,
        json_output=True,
        enable_trace=TRACE_TERRAFORM,
    ) as tf_output_dns:
        LOG.info(json.dumps(tf_output_dns, indent=4))
        subzone_id = tf_output_dns["subzone_id"]["value"]

        # Bootstrap ES cluster
        bootstrap_mode = True
        terraform_module_dir = osp.join(terraform_root_dir, "test_module")
        with open(osp.join(terraform_module_dir, "terraform.tfvars"), "w") as fp:
            fp.write(
                dedent(
                    f"""
                    role_arn = "{TEST_ROLE_ARN}"
                    region = "{REGION}"
                    elastic_zone_id = "{subzone_id}"
                    bootstrap_mode = {str(bootstrap_mode).lower()}
                    """
                )
            )
        with terraform_apply(
            terraform_module_dir,
            destroy_after=DESTROY_AFTER,
            json_output=True,
            enable_trace=TRACE_TERRAFORM,
        ) as tf_output:
            # Create remaining master & data nodes
            with open(osp.join(terraform_module_dir, "terraform.tfvars"), "w") as fp:
                fp.write(
                    dedent(
                        f"""
                        role_arn = "{TEST_ROLE_ARN}"
                        region = "{REGION}"
                        elastic_zone_id = "{subzone_id}"
                        bootstrap_mode = false
                        """
                    )
                )
            with terraform_apply(
                terraform_module_dir,
                destroy_after=DESTROY_AFTER,
                json_output=True,
                enable_trace=TRACE_TERRAFORM,
            ):
                LOG.info(json.dumps(tf_output, indent=4))
