#!/bin/bash

# Check user entered 3 arguments
if [ "$#" -ne 4 ]; then
    echo "Usage with arguments: $0 <bucket-name> <region> <image-name (Without extension)> <format-type>"
    exit 1
fi

BUCKETNAME=$1
REGION=$2
IMAGENAME=$3
FORMAT=$4
read -p "Do you want to first create an ova file from ubuntu iso? (y/n): " choice

if [[ $choice == "y" ]]; then
    cd iso_install
    ./create_autoinstaller_iso.sh $IMAGENAME $FORMAT
    sleep 2
    cd ..
    cp iso_install/$IMAGENAME.$FORMAT .
else
    echo "Autoinstaller script will not run."
fi

echo "Checking if bucket $BUCKETNAME exists..."
# Check if bucket already exists. this command returns bucket details or error if not exist.
if aws s3api head-bucket --bucket "$BUCKETNAME" &> /dev/null; then
    echo "Bucket '$BUCKETNAME' already exists."
else
    aws s3 mb s3://"$BUCKETNAME" --region "$REGION"
    echo "Bucket '$BUCKETNAME' created successfully."
fi

echo "Uploading the VM img to S3 bucket please wait..."
aws s3 cp "$IMAGENAME.$FORMAT" s3://"$BUCKETNAME"

# Check if the role already exists
if aws iam get-role --role-name vmimport &> /dev/null; then
    echo "Role 'vmimport' already exists. No changes made."
else
    aws iam create-role --role-name vmimport --assume-role-policy-document file://trust-policy.json
    echo "Role 'vmimport' created successfully."
fi

echo "Creating the IAM policy..."
cat << EOF > role-policy.json
{
   "Version": "2012-10-17",
   "Statement": [
     {
       "Effect": "Allow",
       "Action": [
         "s3:GetBucketLocation",
         "s3:GetObject",
         "s3:ListBucket",
         "s3:PutObject",
         "s3:GetBucketAcl"
       ],
       "Resource": [
         "arn:aws:s3:::$BUCKETNAME",
         "arn:aws:s3:::$BUCKETNAME/*"
       ]
     },
     {
       "Effect": "Allow",
       "Action": [
         "ec2:ModifySnapshotAttribute",
         "ec2:CopySnapshot",
         "ec2:RegisterImage",
         "ec2:Describe*"
       ],
       "Resource": "*"
     }
   ]
}
EOF
sleep 2
# Check if policy exists
if aws iam get-role-policy --role-name vmimport --policy-name vmimport-$BUCKETNAME &> /dev/null; then
    echo "Policy already exists. No changes made."
else
    aws iam put-role-policy --role-name vmimport --policy-name vmimport-$BUCKETNAME --policy-document file://role-policy.json
    echo "Policy attached successfully."
fi
# Give time for policy to be attached
sleep 5
# Create containers.json to use when importing the img
cat << EOF > containers.json
[
  {
    "Description": "My imported VM",
    "Format": "$FORMAT",
    "UserBucket": {
      "S3Bucket": "$BUCKETNAME",
      "S3Key": "$(basename $IMAGENAME.$FORMAT)"
    }
  }
]
EOF

echo "Importing the image and converting to AMI..."
IMPORT_TASK_ID=$(aws ec2 import-image --description "My imported VM" --disk-containers file://containers.json --region "$REGION" --query 'ImportTaskId' --output text)
echo "Import-task-id: " $IMPORT_TASK_ID

while true; do
    # Describe the import image task
    IMPORT_TASK_INFO=$(aws ec2 describe-import-image-tasks --import-task-ids $IMPORT_TASK_ID --region $REGION)
    IMPORT_TASK_PROGRESS=$(echo $IMPORT_TASK_INFO | jq '.ImportImageTasks[0].Progress')
    AMI_ID=$(echo $IMPORT_TASK_INFO | jq -r '.ImportImageTasks[0].ImageId')

    # Check if the AMI ID is available
    if [[ "$AMI_ID" != "null" && "$AMI_ID" != "" ]]; then
        echo "AMI ID is available: $AMI_ID"
        break
    fi

    # Check the status of the import task because if failed or deleted there could be a problem with the os version or kernel for ami for example
    IMPORT_STATUS=$(echo $IMPORT_TASK_INFO | jq -r '.ImportImageTasks[0].Status')
    
    if [[ "$IMPORT_STATUS" == "deleted" ]]; then
        echo "Import task has been deleted."
        echo $IMPORT_TASK_INFO
        exit 1
    elif [[ "$IMPORT_STATUS" == "failed" ]]; then
        echo "Import task failed."
        echo $IMPORT_TASK_INFO
        exit 1
    fi

    echo "Waiting for AMI ID to become available..."
    echo "Progress: "$IMPORT_TASK_PROGRESS
    sleep 10
done

MY_IP=$(curl -4 ifconfig.me)
echo "Create Terraform tfvars and pass variables"
cat << EOF > terraform.tfvars
region = "$REGION"
ami = "$AMI_ID"
allowed_ssh_ips = ["$MY_IP/32"]
EOF

# Initialize and apply Terraform
terraform init
terraform apply --auto-approve

echo "EC2 instance created using imported image."









