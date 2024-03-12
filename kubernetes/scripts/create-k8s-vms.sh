#!/bin/bash

VM_COUNT=${VM_COUNT:-6}
VM_START=${VM_START:-501}
TEMPLATE=${TEMPLATE:-5000}
IP_START=${IP_START:-10.0.5.1}
NET_MASK=${NET_MASK:-16}
GATEWAY=${GATEWAY:-10.0.0.1}

echo
echo "-= BoneLab Kubernetes VM Creation Tool =-"
echo
echo "Creating ${VM_COUNT} VMs starting at ${VM_START} from template ${TEMPLATE}"
echo

IFS=. read -r i1 i2 i3 i4 <<< ${IP_START}

for x in $(seq 1 ${VM_COUNT}); do
  node=$[${VM_START} + ${x} - 1]
  ip=${i1}.${i2}.${i3}.$[${i4} + ${x} - 1]

  echo -n "Creating VM ${node} with IP ${ip} ... "

  {
    qm clone ${TEMPLATE} ${node} --name kubernetes-${x} --full 1
    qm resize ${node} scsi0 +18G
    qm set ${node} --ipconfig0 ip=${ip}/${NET_MASK},gw=${GATEWAY}
    qm start ${node}
  } > vm-creation.log 2>&1

  echo "Done!"
done

echo
echo "VM creation process complete!"
echo
