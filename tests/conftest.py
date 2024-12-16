from textwrap import dedent

import boto3
import pytest
import logging

from os import path as osp

from infrahouse_toolkit.logging import setup_logging
from infrahouse_toolkit.terraform import terraform_apply

# "303467602807" is our test account
TEST_ACCOUNT = "303467602807"
DEFAULT_PROGRESS_INTERVAL = 10
TRACE_TERRAFORM = False
UBUNTU_CODENAME = "jammy"
TERRAFORM_ROOT_DIR = "test_data"

LOG = logging.getLogger(__name__)

setup_logging(LOG, debug=True)


@pytest.fixture()
def dns(test_role_arn, aws_region, test_zone_name, keep_after):
    """
    Create DNS zone
    """
    terraform_module_dir = osp.join(TERRAFORM_ROOT_DIR, "dns")
    with open(osp.join(terraform_module_dir, "terraform.tfvars"), "w") as fp:
        fp.write(
            dedent(
                f"""
                parent_zone_name = "{test_zone_name}"
                region = "{aws_region}"
                """
            )
        )
        if test_role_arn:
            fp.write(
                dedent(
                    f"""
                    role_arn = "{test_role_arn}"
                    """
                )
            )
    with terraform_apply(
        terraform_module_dir,
        destroy_after=not keep_after,
        json_output=True,
        enable_trace=TRACE_TERRAFORM,
    ) as tf_output:
        yield tf_output
