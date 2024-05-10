#!/bin/bash

# Load Falcon Client credentials from a secure location (e.g., AWS Secrets Manager)
export FALCON_CLIENT_ID=$(aws secretsmanager get-secret-value --secret-id "falcon-client-id" --query SecretString --output text)
export FALCON_CLIENT_SECRET=$(aws secretsmanager get-secret-value --secret-id "falcon-client-secret" --query SecretString --output text)
export FALCON_CLOUD_API=api.crowdstrike.com

# Load role_name from deploy-iam-role-org.sh
export ROLE_NAME=<role_name>

# Load External ID
export EXTERNAL_ID_USED=<external_id>

# Configure AWS CLI (assuming AWS CLI is configured)

# Get all accounts in the organization
aws_accounts=$(aws organizations list-accounts --query 'Accounts[].Id' --output text)

# Loop through each AWS account ID
for aws_account_id in $aws_accounts; do

  # List all regions (replace with your specific list if needed)
  regions=( "us-east-1" "us-east-2" "us-west-1" "us-west-2" "ap-southeast-1" "ap-southeast-2" "ap-northeast-1" "eu-west-1" "eu-central-1" )

  for aws_region in "${regions[@]}"; do

    # Construct the ECR endpoint URL
    ecr_url="https://${aws_account_id}.dkr.ecr.${aws_region}.amazonaws.com"

    # Try to perform a HEAD request on the ECR endpoint
    # Success indicates the region is being used
    if curl -sSLf -o /dev/null -w "%{http_code}\n" "$ecr_url" | grep -q "200"; then

      # Region is being used, register the ECR registry
      post_data=$(cat <<EOF
      {
        "type": "ecr",
        "url": "$ecr_url",
        "user_defined_alias": "",
        "credential": {
          "details": {
            "aws_iam_role": "arn:aws:iam::${aws_account_id}:role/${ROLE_NAME}",
            "aws_external_id": "${EXTERNAL_ID_USED}"
          }
        }
      }
      EOF
      )

      curl --request POST \
        --url "https://${FALCON_CLOUD_API}/container-security/entities/registries/v1" \
        --header "Authorization: Bearer ${BEARER_API_TOKEN}" \
        --header 'Content-Type: application/json' \
        --data "$post_data"

      # Check for errors in the API call (implement error handling)
      if [[ $? -ne 0 ]]; then
        echo "Error registering ECR registry for account: ${aws_account_id}, region: ${aws_region}"
        exit 1
      fi
    fi
  done
done
