#!/bin/bash

# Check user entered 3 arguments
if [ "$#" -ne 3 ]; then
    echo "Usage with arguments: $0 <bucket-name> <region> <image-name>"
    exit 1
fi

# Assigning input arguments to variables
BUCKETNAME=$1
REGION=$2
IMAGENAME=$3

# Check if bucket already exists.
if ! aws s3api head-bucket --bucket "$BUCKETNAME" 2>/dev/null; then
    # If the bucket does not exist, create it
    aws s3 mb s3://"$BUCKETNAME" --region "$REGION"
    echo "Bucket '$BUCKETNAME' created successfully."
else
    echo "Bucket '$BUCKETNAME' already exists."
fi

echo "Upload the raw img to S3 bucket please wait..."
aws s3 cp "$IMAGENAME" s3://"$BUCKETNAME"

# Create IAM role to import VM
aws iam create-role --role-name vmimport --assume-role-policy-document file://trust-policy.json
# Create the IAM policy
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

# Check if policy exists
if ! aws iam get-role-policy --role-name vmimport --policy-name vmimport-$BUCKETNAME &> /dev/null; then
    # Attach the policy to the role
    aws iam put-role-policy --role-name vmimport --policy-name vmimport-$BUCKETNAME --policy-document file://role-policy.json
    echo "Policy attached successfully."
else
    echo "Policy already exists. No changes made."
fi

# Create containers.json to use when importing the img
cat << EOF > containers.json
[
  {
    "Description": "My imported VM",
    "Format": "raw",
    "UserBucket": {
      "S3Bucket": "$BUCKETNAME",
      "S3Key": "$IMAGENAME"
    }
  }
]
EOF
# Inside the containers.json i specify where the image path.
echo "Importing  the image to AMI..."
IMPORT_TASK_ID=$(aws ec2 import-image --description "My imported VM" --disk-containers file://containers.json --region "$REGION" --query 'ImportTaskId' --output text)
echo "Import-task-id: " $IMPORT_TASK_ID
while true; do
    # Describe the import image task
    IMPORT_TASK_INFO=$(aws ec2 describe-import-image-tasks --import-task-ids $IMPORT_TASK_ID --region $REGION)
    IMPORT_TASK_PROGRESS=$(echo $IMPORT_TASK_INFO | jq '.ImportImageTasks[0].Progress')
    # Extract the AMI ID from the output
    AMI_ID=$(echo $IMPORT_TASK_INFO | jq -r '.ImportImageTasks[0].ImageId')

    # Check if the AMI ID is available
    if [[ "$AMI_ID" != "null" && "$AMI_ID" != "" ]]; then
        echo "AMI ID is available: $AMI_ID"
        break
    fi

    # Check the status of the import task
    IMPORT_STATUS=$(echo $IMPORT_TASK_INFO | jq -r '.ImportImageTasks[0].Status')
    
    if [[ "$IMPORT_STATUS" == "deleted" ]]; then
        echo "Import task has been deleted."
        exit 1
    elif [[ "$IMPORT_STATUS" == "failed" ]]; then
        echo "Import task failed."
        exit 1
    fi

    # Wait for a few seconds before checking again
    echo "Waiting for AMI ID to become available..."
    echo "Progress: "$IMPORT_TASK_PROGRESS
    sleep 10  # Adjust the sleep duration as needed
done

MY_IP=$(curl -4 ifconfig.me)
# Create Terraform tfvars and pass variables
cat << EOF > terraform.tfvars
region = "$REGION"
ami = "$AMI_ID"
allowed_ssh_ips = ["$MY_IP/32"]
EOF

# Initialize and apply Terraform
terraform init
terraform apply --auto-approve

echo "EC2 instance created using imported image."


# import the image:
# https://docs.aws.amazon.com/vm-import/latest/userguide/import-vm-image.html








