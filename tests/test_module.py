import json
import os
import shutil
from os import path as osp
from textwrap import dedent

import pytest
from pytest_infrahouse import terraform_apply

from tests.conftest import (
    LOG,
    TERRAFORM_ROOT_DIR,
    bootstrap_cluster,
)


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
