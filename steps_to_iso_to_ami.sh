#!/bin/bash

# ubuntu latest kernel supported for linnux VM to convert to ami is 5.15.0
# https://docs.aws.amazon.com/vm-import/latest/userguide/prerequisites.html



# 1. Creating virtual disk image of 10Gb
#       qemu-img create -f raw ubuntu-disk.img 10G
# 2. Creating a vm with ubuntu image and 2G of RAM and 1 cpu core (default) on the virtual disk image
#       qemu-system-x86_64 -boot d -cdrom ubuntu-24.04.1-live-server-amd64.iso -drive file=ubuntu-disk.img,format=raw -m 2048 # specify the format to raw
# 3. Install the OS on the VM
# the fs should be formatted to ext4 and the kernel last version is 5.15.0 (ubuntu 22.04.1-4 or ubuntu 23.04)
# 4. Install open-ssh and 
# 5. sudo systemctl enable ssh?
# 6. sudo systemctl start ssh?

# Check user entered 2 arguments
if [ "$#" -ne 3 ]; then
    echo "Usage with arguments: $0 <bucket-name> <region> <image-name>"
    exit 1
fi

# Assigning input arguments to variables
bucketname=$1
region=$2
imagename=$3

# Attempt to create the S3 bucket
aws s3 mb s3://"$bucketname" --region "$region"

# Check if last command return status exit of 0 which means it was successful.
if [ $? -eq 0 ]; then
    echo "Bucket '$bucketname' created successfully in region '$region'."
else
    # Check if the error is because the bucket already exists
    if aws s3api head-bucket --bucket "$bucketname" 2>/dev/null; then
        echo "Bucket '$bucketname' already exists in region '$region'."
    else
        echo "Failed to create bucket '$bucketname'."
        exit 1 
    fi
fi

echo "Upload the raw img to S3 bucket please wait..."
aws s3 cp "$imagename" s3://"$bucketname"

# Create IAM role to import VM
aws iam create-role --role-name vmimport --assume-role-policy-document file://trust-policy.json

# Attach the policy to the role
aws iam put-role-policy --role-name vmimport --policy-name vmimport --policy-document file://role-policy.json

# Create containers.json to use when importing the img
cat << EOF > containers.json
{
  "Description": "My imported VM",
  "Format": "raw",
  "UserBucket": {
    "S3Bucket": "$bucketname",
    "S3Key": "$imagename"
  }
}
EOF
# Inside the containers.json i specify where the image path.
echo "Importing  the image to AMI..."
IMPORT_TASK_ID=$(aws ec2 import-image --description "My imported VM" --disk-containers file://containers.json --region "$region" --query 'ImportTaskId' --output text)
aws ec2 wait import-image-completed --import-task-ids "$IMPORT_TASK_ID" --region "$region"
# aws ec2 import-image --description "My imported VM" --disk-containers file://containers.json
AMI_ID=$(aws ec2 describe-import-image-tasks --import-task-ids "$IMPORT_TASK_ID" --region "$region" --query 'ImportImageTasks[0].ImageId' --output text)
echo "AMI ID: $AMI_ID"

# Create Terraform configuration
cat << EOF > main.tf
provider "aws" {
  region = "$region"
}

resource "aws_instance" "example" {
  ami           = "$AMI_ID"
  instance_type = "t3.micro"

  tags = {
    Name = "Imported Instance"
  }
}
EOF

# Initialize and apply Terraform
terraform init
terraform apply -auto-approve

echo "EC2 instance created using imported image."


# import the image:
# https://docs.aws.amazon.com/vm-import/latest/userguide/import-vm-image.html

# role and policy:
# https://docs.aws.amazon.com/vm-import/latest/userguide/required-permissions.html#vmimport-role






