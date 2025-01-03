# ami-from-iso-project

This project convert iso ubuntu os file into an AWS AMI.

Steps:
1. Install qemu-utils and qemu system
      sudo apt install -y qemu-utils qemu-system-x86
2. Create virtual disk image of 10Gb
       qemu-img create -f raw ubuntu-disk.img 10G
3. Create a vm with ubuntu image and 2G of RAM and 1 cpu core (default) on the virtual disk image as a raw disk image.
       qemu-system-x86_64 -boot d -cdrom ubuntu-24.04.1-live-server-amd64.iso -drive file=ubuntu-disk.img,format=raw -m 2048
4. Install the OS on the VM
the fs should be formatted to ext4(or 3,2) and the ubuntu kernel last version supported is 5.15.0 (ubuntu 22.04.1-4 or ubuntu 23.04)

* ubuntu latest kernel supported for linux VM to convert to ami is 5.15.0 and this can be viewed here:
* https://docs.aws.amazon.com/vm-import/latest/userguide/prerequisites.html > Image formats supported by VM Import/Export

5. After creating the VM - the user can run the steps_iso_to_ami.sh script with 3 arguments which are
    1. bucket name
    2. aws region
    3. image name

6. The script will create a role and policy, create a bucket, upload the img, import the img to be converted to AMI, run an EC2 with that image using Terraform.

7. Terraform create ec2 with the AMI provided and add security group with ssh allowed from the user pc ip.
    * AMI, region and IP are passed using terraform.tfvars (can pass also key_name for ssh key pair name) 
 