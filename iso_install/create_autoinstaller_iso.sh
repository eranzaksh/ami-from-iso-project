#!/bin/bash

sudo apt update && sudo apt install -y 7zip wget xorriso whois
AUTOINSTALLER_DIR="ubuntu-iso-sources"
mkdir ubuntu-iso-sources

7z -y x ubuntu-22.04.1-live-server-amd64.iso -oubuntu-iso-sources

cd ubuntu-iso-sources

mv \[BOOT\] ../BOOT
cd ..
GRUB_CFG="./ubuntu-iso-sources/boot/grub/grub.cfg"
MENU_ENTRY='menuentry "Autoinstall Ubuntu Server" {
    set gfxpayload=keep
    linux   /casper/vmlinuz quiet autoinstall ds=nocloud\\;s=/cdrom/server/  ---
    initrd  /casper/initrd
}'
if ! grep -q "Autoinstall Ubuntu Server" "$GRUB_CFG"; then
    # If it doesn't exist, use awk to insert the menu entry after line 7
    awk -v new_entry="$MENU_ENTRY" 'NR==7 {print; print new_entry; next} 1' "$GRUB_CFG" > temp.cfg && mv temp.cfg "$GRUB_CFG"
    echo "Menu entry added successfully."
else
    echo "Menu entry already exists."
fi

echo "moving user-data to ubuntu-iso-sources/server/"

mkdir -p ubuntu-iso-sources/server
cp user-data ubuntu-iso-sources/server/
touch ubuntu-iso-sources/server/meta-data

cd ubuntu-iso-sources
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

# Create a virtual hard disk in VDI format
VBoxManage createhd --filename ~/VirtualBox\ VMs/UbuntuServer/ubuntu-disk.vdi --size 10240 --format VDI

# Create a SATA controller if it doesn't exist (recommended)
VBoxManage storagectl "UbuntuServer" --name "SATA Controller" --add sata --controller IntelAhci

# Attach the hard disk to the SATA controller
VBoxManage storageattach "UbuntuServer" --storagectl "SATA Controller" --port 0 --device 0 --type hdd --medium ~/VirtualBox\ VMs/UbuntuServer/ubuntu-disk.vdi

# Attach the autoinstall ISO to the VM's CD/DVD drive (using SATA)
VBoxManage storageattach "UbuntuServer" --storagectl "SATA Controller" --port 1 --device 0 --type dvddrive --medium ./ubuntu-22.04-autoinstall.iso
VBoxManage modifyvm "UbuntuServer" --boot1 dvd

VBoxManage startvm "UbuntuServer" --type headless

VM_NAME="UbuntuServer"

is_powered_off() {
    status=$(VBoxManage showvminfo "$VM_NAME" --machinereadable | grep ^VMState=)
    [[ "$status" == *"poweroff"* ]]
}

while ! is_powered_off; do
    echo "Waiting for VM to finish installation and $VM_NAME to power off..."
    sleep 30
done

echo "VM $VM_NAME has powered off"
sleep 1
echo "Exporting ova file..."
VBoxManage export UbuntuServer -o ubuntu-2204.ova
echo "ova file exported successfully!"