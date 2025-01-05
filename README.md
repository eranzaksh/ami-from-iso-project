# AMI from ISO Project

This project converts an Ubuntu ISO file into an AWS AMI.

## Overview

This tool fully automates the process of creating VM installing ubuntu os on it, exoporting ova file and then uploading and converting it (or other formats which fit AWS prerequisites) to an AMI that can be used to launch EC2 instances and launch one ec2 instance with this AMI.

## Prerequisites

- VirtualBox
- AWS CLI
- AWS credentials
- Terraform
- Ubuntu ISO file (version 22.04.1 recommended for the most updated ubuntu version *currently* supported)
- Use Ubuntu with kernel version 5.15.0 or earlier (Ubuntu 22.04.1)

> **Note**: The latest Ubuntu kernel supported for Linux VM to convert to AMI is 5.15.0. For more details, see [AWS VM Import/Export Prerequisites](https://docs.aws.amazon.com/vm-import/latest/userguide/prerequisites.html > Image formats supported by VM Import/Export).

## Steps

### 1. clone this repository
```bash
git clone https://github.com/eranzaksh/ami-from-iso-project.git
```

### 2. Install virtualbox 7zip xorriso
```bash
sudo apt install -y virtualbox 7zip xorriso
```

### 3. Modify user-data with your configuration
```bash
1. vim iso_install/user-data
```

### 4. Run Conversion Script
Execute `convert_iso_to_ami.sh` with the following arguments:

1. Bucket name
2. AWS region
3. image name (with no extension)
4. Format type
```bash
./convert_iso_to_ami.sh <bucket_name> <aws_region> <image_name> <format_type>
```
This script will:
- Let you choose if you also want to use the "create_autoinstaller_iso.sh" to create an ova.
- Create necessary IAM roles and policies
- Create an S3 bucket
- Upload the image
- Import the image and convert it to an AMI
- Use Terraform to launch an EC2 instance with the new AMI

### 5. Autoinstaller script
iso_install/create_autoinstaller_iso.sh script will do the following:

1. Extract the ubuntu iso file using 7zip
2. Configuring grub.cfg to work with autoinstall
3. Copying user-data configuration file to the extracted ubuntu iso
4. Creating a new iso with the user-data and grub.cfg new settings for autoinstaller
5. Creating a VM in virtualbox and installing the new autoinstaller iso inside in headless mode
6. Creating an ova file ready to be uploaded to s3 and converted to ami
7. Deleting the virtualbox VM for laters uses 

### 6. Terraform Configuration

Terraform will:
- Create an EC2 instance using the new AMI
- Configure a security group allowing SSH access from the user pc's IP

Credentials for EC2 login:
- username: eran-ubuntu
- password: 123

> **Note**: AMI ID, region, and your IP are passed using `terraform.tfvars`. You can also specify a `key_name` for the SSH key pair.
 ### Print screen from the created AMI terminal
 ![Terminal screenshot](Screenshot_from_terminal.png)