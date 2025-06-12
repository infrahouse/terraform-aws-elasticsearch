import contextlib
import json
import os
from textwrap import dedent

import pytest
import logging

from os import path as osp

from infrahouse_core.logging import setup_logging
from pytest_infrahouse import terraform_apply

# "303467602807" is our test account
TEST_ACCOUNT = "303467602807"
DEFAULT_PROGRESS_INTERVAL = 10
TRACE_TERRAFORM = False
UBUNTU_CODENAME = "jammy"
TERRAFORM_ROOT_DIR = "test_data"
# TEST_ROLE_ARN = "arn:aws:iam::303467602807:role/elasticsearch-tester"

LOG = logging.getLogger(__name__)

setup_logging(LOG, debug=True)


@contextlib.contextmanager
def bootstrap_cluster(
    service_network,
    dns,
    keep_after,
    aws_region,
    test_role_arn,
    module_path,
    environment="development",
):
    subzone_id = dns["subzone_id"]["value"]

    subnet_public_ids = service_network["subnet_public_ids"]["value"]
    subnet_private_ids = service_network["subnet_private_ids"]["value"]
    internet_gateway_id = service_network["internet_gateway_id"]["value"]

    # Bootstrap ES cluster
    bootstrap_mode = True
    bootstrap_flag_file = ".bootstrapped"
    terraform_module_dir = osp.join(TERRAFORM_ROOT_DIR, module_path)

    try:
        if osp.exists(osp.join(terraform_module_dir, bootstrap_flag_file)):
            yield
        else:
            with open(osp.join(terraform_module_dir, "terraform.tfvars"), "w") as fp:
                fp.write(
                    dedent(
                        f"""
                        region          = "{aws_region}"
                        environment     = "{environment}"
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
                enable_trace=TRACE_TERRAFORM,
            ):
                open(osp.join(terraform_module_dir, bootstrap_flag_file), "w").write("")
                yield
    finally:
        full_path = osp.join(terraform_module_dir, bootstrap_flag_file)
        if not keep_after:
            LOG.info(
                "Will delete %s file because we're destroying resources after the test.",
                full_path,
            )
            os.remove(full_path)
        else:
            LOG.info(
                "Will keep %s around because we're keeping resources after the test.",
                full_path,
            )


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
