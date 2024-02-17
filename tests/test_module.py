import json
from os import path as osp
from pprint import pformat
from textwrap import dedent
from time import sleep

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


@pytest.mark.flaky(reruns=0, reruns_delay=30)
@pytest.mark.timeout(1800)
def test_module(ec2_client, route53_client, autoscaling_client):
    terraform_root_dir = "test_data"

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
    ) as tf_output_0:
        LOG.info(json.dumps(tf_output_0, indent=4))
        subzone_id = tf_output_0["subzone_id"]["value"]

        terraform_module_dir = osp.join(terraform_root_dir, "test_module")
        with open(osp.join(terraform_module_dir, "terraform.tfvars"), "w") as fp:
            fp.write(
                dedent(
                    f"""
                    role_arn = "{TEST_ROLE_ARN}"
                    region = "{REGION}"
                    elastic_zone_id = "{subzone_id}"
                    """
                )
            )
        with terraform_apply(
            terraform_module_dir,
            destroy_after=DESTROY_AFTER,
            json_output=True,
            enable_trace=TRACE_TERRAFORM,
        ) as tf_output_1:
            LOG.info(json.dumps(tf_output_1, indent=4))
