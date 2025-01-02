#!/bin/bash

# Check user entered 3 arguments
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

# echo "Upload the raw img to S3 bucket please wait..."
# aws s3 cp "$imagename" s3://"$bucketname"

# Create IAM role to import VM
# aws iam create-role --role-name vmimport --assume-role-policy-document file://trust-policy.json

# Attach the policy to the role
# aws iam put-role-policy --role-name vmimport --policy-name vmimport2 --policy-document file://role-policy.json

# Create containers.json to use when importing the img
cat << EOF > containers.json
[
  {
    "Description": "My imported VM",
    "Format": "raw",
    "UserBucket": {
      "S3Bucket": "$bucketname",
      "S3Key": "$imagename"
    }
  }
]
EOF
# Inside the containers.json i specify where the image path.
echo "Importing  the image to AMI..."
IMPORT_TASK_ID=$(aws ec2 import-image --description "My imported VM" --disk-containers file://containers.json --region "$region" --query 'ImportTaskId' --output text)
echo "Import-task-id: " $IMPORT_TASK_ID
while true; do
    # Describe the import image task
    IMPORT_TASK_INFO=$(aws ec2 describe-import-image-tasks --import-task-ids $IMPORT_TASK_ID --region $region)
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
    
    if [[ "$IMPORT_STATUS" == "completed" ]]; then
        echo "Import completed but no AMI ID found."
        break
    elif [[ "$IMPORT_STATUS" == "deleted" ]]; then
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
echo "AMI ID: $AMI_ID"
MY_IP=$(curl -4 ifconfig.me)

# Create Terraform tfvars and pass variables
cat << EOF > terraform.tfvars
region = $region
ami = $AMI_ID
allowed_ssh_ips = $MY_IP
EOF

# Initialize and apply Terraform
terraform init
terraform apply -auto-approve

echo "EC2 instance created using imported image."


# import the image:
# https://docs.aws.amazon.com/vm-import/latest/userguide/import-vm-image.html








