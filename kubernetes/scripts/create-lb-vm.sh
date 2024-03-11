#!/bin/bash

TEMPLATE=${TEMPLATE:-5000}
LB_NODE=${LB_NODE:510}
LB_IP=${LB_IP:-10.0.5.10}
NET_MASK=${NET_MASK:-16}
GATEWAY=${GATEWAY:-10.0.0.1}

echo
echo "-= BoneLab Kubernetes Load Balancer VM Creation Tool =-"
echo
echo "Creating Load Balancer from template ${TEMPLATE}"
echo

echo -n "Creating VM with IP ${LB_IP} ... "

{
  qm clone ${TEMPLATE} ${LB_NODE} --name kubernetes-lb --full 1
  qm resize ${LB_NODE} scsi0 +8G
  qm set ${LB_NODE} --ipconfig0 ip=${LB_IP}/${NET_MASK},gw=${GATEWAY}
  qm start ${LB_NODE}
} > vm-creation.log 2>&1

echo "Done!"

echo
echo "Load Balancer VM creation process complete!"
echo
