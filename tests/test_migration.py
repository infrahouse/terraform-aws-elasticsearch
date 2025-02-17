import contextlib
import json
import os
from os import path as osp
from textwrap import dedent

from infrahouse_toolkit.terraform import terraform_apply

from tests.conftest import (
    LOG,
    TRACE_TERRAFORM,
    TERRAFORM_ROOT_DIR,
    bootstrap_cluster,
)


def test_migration(
    service_network,
    dns,
    aws_region,
    keep_after,
    test_role_arn,
):
    subzone_id = dns["subzone_id"]["value"]

    subnet_public_ids = service_network["subnet_public_ids"]["value"]
    subnet_private_ids = service_network["subnet_private_ids"]["value"]
    internet_gateway_id = service_network["internet_gateway_id"]["value"]
    environment = "sandbox"
    # Bootstrap ES cluster
    terraform_module_dir = osp.join(TERRAFORM_ROOT_DIR, "test_migration")
    with bootstrap_cluster(
        service_network,
        dns,
        keep_after,
        aws_region,
        test_role_arn,
        "test_migration",
        environment=environment,
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
                    environment     = "{environment}"

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
            enable_trace=TRACE_TERRAFORM,
        ) as tf_output:
            LOG.info(json.dumps(tf_output, indent=4))
