#!/bin/bash

IMAGENAME=$1
FORMAT=$2

AUTOINSTALLER_DIR="ubuntu-iso-sources"
ISO_IMG="https://releases.ubuntu.com/22.04.1/ubuntu-22.04.1-live-server-amd64.iso"

mkdir $AUTOINSTALLER_DIR

read -p "Do you want to also download the ubuntu 22.04.1 iso? (y/n): " choice

if [[ $choice == "y" ]]; then
    echo "Downloading ubuntu-22.04.1-live-server.iso"
    wget $ISO_IMG
fi
# Extract the official ubuntu iso
7z -y x ubuntu-22.04.1-live-server-amd64.iso -o$AUTOINSTALLER_DIR
# This is not needed in the final ISO
mv $AUTOINSTALLER_DIR/[BOOT] ./BOOT

GRUB_CFG="./$AUTOINSTALLER_DIR/boot/grub/grub.cfg"
MENU_ENTRY='menuentry "Autoinstall Ubuntu Server" {
    set gfxpayload=keep
    linux   /casper/vmlinuz quiet autoinstall ds=nocloud\\;s=/cdrom/server/  ---
    initrd  /casper/initrd
}'
if ! grep -q "Autoinstall Ubuntu Server" "$GRUB_CFG"; then
    # If autoinstall doesn't exist, use awk to insert the menu entry after line 7
    awk -v new_entry="$MENU_ENTRY" 'NR==7 {print; print new_entry; next} 1' "$GRUB_CFG" > temp.cfg && mv temp.cfg "$GRUB_CFG"
    echo "Menu entry added successfully."
else
    echo "Menu entry already exists."
fi

echo "moving user-data to $AUTOINSTALLER_DIR/server/"

mkdir -p $AUTOINSTALLER_DIR/server
cp user-data $AUTOINSTALLER_DIR/server/
touch $AUTOINSTALLER_DIR/server/meta-data

# Creating a new iso with autoinstall and user-data
cd $AUTOINSTALLER_DIR
echo "Creating an autoinstaller iso..."
xorriso -as mkisofs -r \
  -V 'Ubuntu 22.04 LTS (Auto Install)' \
  -o ../ubuntu-22.04-autoinstall.iso \
  --grub2-mbr ../BOOT/1-Boot-NoEmul.img \
  -partition_offset 16 \
  --mbr-force-bootable \
  -append_partition 2 28732ac11ff8d211ba4b00a0c93ec93b ../BOOT/2-Boot-NoEmul.img \
  -appended_part_as_gpt \
  -iso_mbr_part_type a2a0d0ebe5b9334487c068b6b72699c7 \
  -c '/boot.catalog' \
  -b '/boot/grub/i386-pc/eltorito.img' \
  -no-emul-boot -boot-load-size 4 -boot-info-table --grub2-boot-info \
  -eltorito-alt-boot \
  -e '--interval:appended_partition_2:::' \
  -no-emul-boot .
echo "Autoinstaller complete"
cd ..


echo "Creating VM and installing the ubuntu os..."
sleep 1
VBoxManage createvm --name "UbuntuServer" --register --ostype "Ubuntu_64"
VBoxManage modifyvm "UbuntuServer" --memory 4096 --cpus 4

VBoxManage createhd --filename ~/VirtualBox\ VMs/UbuntuServer/ubuntu-disk.vdi --size 10240 --format VDI

VBoxManage storagectl "UbuntuServer" --name "SATA Controller" --add sata --controller IntelAhci

VBoxManage storageattach "UbuntuServer" --storagectl "SATA Controller" --port 0 --device 0 --type hdd --medium ~/VirtualBox\ VMs/UbuntuServer/ubuntu-disk.vdi

VBoxManage storageattach "UbuntuServer" --storagectl "SATA Controller" --port 1 --device 0 --type dvddrive --medium ./ubuntu-22.04-autoinstall.iso
VBoxManage modifyvm "UbuntuServer" --boot1 dvd

VBoxManage startvm "UbuntuServer" --type headless

VM_NAME="UbuntuServer"
# Wait for the VM to power off according to the user-data config
is_powered_off() {
    status=$(VBoxManage showvminfo "$VM_NAME" --machinereadable | grep ^VMState=)
    [[ "$status" == *"poweroff"* ]]
}

while ! is_powered_off; do
    echo "Waiting for VM to finish installation and $VM_NAME to power off..."
    sleep 30
done

echo "VM $VM_NAME has powered off"
sleep 2
echo "Exporting ova file..."
VBoxManage export UbuntuServer -o $IMAGENAME.$FORMAT
echo "ova file exported successfully!"
sleep 2
echo "Deleting the $VM_NAME vm for later runs"
VBoxManage unregistervm $VM_NAME --delete
