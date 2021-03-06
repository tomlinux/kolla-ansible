#!/bin/bash

set -o xtrace
set -o errexit

# Enable unbuffered output for Ansible in Jenkins.
export PYTHONUNBUFFERED=1


function test_openstack_logged {
    # Wait for service ready
    sleep 15

    . /etc/kolla/admin-openrc.sh

    openstack --debug compute service list
    openstack --debug network agent list

    if ! openstack image show cirros >/dev/null 2>&1; then
        echo "Initialising OpenStack resources via init-runonce"
        tools/init-runonce
    else
        echo "Not running init-runonce - resources exist"
    fi

    echo "TESTING: Server creation"
    openstack server create --wait --image cirros --flavor m1.tiny --key-name mykey --network demo-net kolla_boot_test
    openstack --debug server list
    # If the status is not ACTIVE, print info and exit 1
    if [[ $(openstack server show kolla_boot_test -f value -c status) != "ACTIVE" ]]; then
        echo "FAILED: Instance is not active"
        openstack --debug server show kolla_boot_test
        return 1
    fi
    echo "SUCCESS: Server creation"

    if echo $ACTION | grep -q "ceph"; then
        echo "TESTING: Cinder volume attachment"
        openstack volume create --size 2 test_volume
        openstack server add volume kolla_boot_test test_volume --device /dev/vdb
        openstack server remove volume kolla_boot_test test_volume
        echo "SUCCESS: Cinder volume attachment"
    fi

    echo "TESTING: Server deletion"
    openstack server delete --wait kolla_boot_test
    echo "SUCCESS: Server deletion"

    if echo $ACTION | grep -q "zun"; then
        echo "TESTING: Zun"
        openstack --debug appcontainer service list
        openstack --debug appcontainer host list
        # TODO(hongbin): Run a Zun container and assert the container becomes
        # Running
        echo "SUCCESS: Zun"
    fi
}

function test_openstack {
    echo "Testing OpenStack"
    test_openstack_logged > /tmp/logs/ansible/test-openstack 2>&1
    result=$?
    if [[ $result != 0 ]]; then
        echo "Testing OpenStack failed. See ansible/test-openstack for details"
    else
        echo "Successfully tested OpenStack. See ansible/test-openstack for details"
    fi
    return $result
}

test_openstack
