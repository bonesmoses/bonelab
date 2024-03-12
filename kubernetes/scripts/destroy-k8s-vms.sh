#!/bin/bash

VM_COUNT=${VM_COUNT:-6}
VM_START=${VM_START:-501}

echo
echo "-= BoneLab Kubernetes VM Destruction Tool =-"
echo
echo "Destroying ${VM_COUNT} VMs starting at ${VM_START}"
echo

for x in $(seq 1 ${VM_COUNT}); do
  node=$[${VM_START} + ${x} - 1]

  echo -n "Destroying VM ${node} ... "

  {
    qm stop ${node}
    qm destroy ${node}
  } > vm-destruction.log 2>&1

  echo "Done!"
done

echo
echo "VM destruction process complete!"
echo
