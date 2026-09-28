#!/bin/bash

# AD FS domain controller setup (CDK)
# Discovers the VPC and subnets of the existing Aurora cluster, lets you override which
# subnet the domain controller goes in, then deploys the domain controller stack.
#
# Access to the domain controller is browser-based via AWS Systems Manager (Session
# Manager / Fleet Manager) - no RDP, no public subnet. Run setup-adfs.ps1 on it from there.
#
# Config comes from this module's .env: infrastructure/identity_providers/adfs/.env
# Required in .env: ADFS_KEY_NAME.

set -e

echo "AD FS domain controller setup (CDK)"
echo "===================================="

# --- Resolve paths (this script lives in identity_providers/adfs/scripts) ---
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MODULE_DIR="$(dirname "$SCRIPT_DIR")"       # identity_providers/adfs
CDK_DIR="$MODULE_DIR/cdk"
ENV_FILE="$MODULE_DIR/.env"

# --- Prerequisites ---
if ! aws sts get-caller-identity &>/dev/null; then
    echo "ERROR: AWS CLI not configured. Run 'aws configure' first."
    exit 1
fi
for tool in java mvn cdk; do
    if ! command -v "$tool" &>/dev/null; then
        echo "ERROR: $tool not found. Install it first (Java 8+, Maven, aws-cdk)."
        exit 1
    fi
done

# --- Load module .env ---
if [ -f "$ENV_FILE" ]; then
    echo "Using configuration from $ENV_FILE"
    set -a; source "$ENV_FILE"; set +a
else
    echo "ERROR: $ENV_FILE not found."
    echo "       Copy the template and fill it in:"
    echo "         cp \"$MODULE_DIR/.env.example\" \"$ENV_FILE\""
    exit 1
fi

# --- Region / account ---
export CDK_DEFAULT_ACCOUNT="$(aws sts get-caller-identity --query Account --output text)"
export CDK_DEFAULT_REGION="${AWS_REGION:-$(aws configure get region)}"
if [ -z "$CDK_DEFAULT_REGION" ]; then
    echo "ERROR: No AWS region. Set AWS_REGION in .env or run 'aws configure set region <region>'."
    exit 1
fi
REGION="$CDK_DEFAULT_REGION"
echo "Account: $CDK_DEFAULT_ACCOUNT   Region: $REGION"

# --- Required config ---
if [ -z "$ADFS_KEY_NAME" ]; then
    echo "ERROR: ADFS_KEY_NAME is required in $ENV_FILE (an existing EC2 key pair)."
    exit 1
fi
# The DSRM password is generated into Secrets Manager by the stack - nothing to set here.

# --- Discover the Aurora cluster's VPC and subnets (no hardcoded cluster name) ---
AURORA_STACK_NAME="${AURORA_STACK_NAME:-aws-jdbc-driver-stack}"

if [ -n "${ADFS_VPC_ID:-}" ] || [ -n "${ADFS_SUBNET_ID:-}" ]; then
    if [ -z "${ADFS_VPC_ID:-}" ] || [ -z "${ADFS_SUBNET_ID:-}" ]; then
        echo "ERROR: Set both ADFS_VPC_ID and ADFS_SUBNET_ID, or leave both unset to discover them from '$AURORA_STACK_NAME'."
        exit 1
    fi
    echo "Using ADFS_VPC_ID and ADFS_SUBNET_ID from .env (skipping discovery)."
else
    echo ""
    echo "Discovering the Aurora cluster's network from stack '$AURORA_STACK_NAME'..."

    CLUSTER_ID="$(aws cloudformation describe-stack-resources \
        --stack-name "$AURORA_STACK_NAME" --region "$REGION" \
        --query "StackResources[?ResourceType=='AWS::RDS::DBCluster'].PhysicalResourceId" \
        --output text 2>/dev/null || true)"

    if [ -z "$CLUSTER_ID" ] || [ "$CLUSTER_ID" = "None" ]; then
        echo "ERROR: Could not find an Aurora cluster in stack '$AURORA_STACK_NAME'."
        echo "       Deploy Aurora first (./setup-aurora-cdk.sh at the repo root), set"
        echo "       AURORA_STACK_NAME, or set both ADFS_VPC_ID and ADFS_SUBNET_ID in .env."
        exit 1
    fi
    echo "  Cluster: $CLUSTER_ID"

    SUBNET_GROUP="$(aws rds describe-db-clusters --db-cluster-identifier "$CLUSTER_ID" \
        --region "$REGION" --query 'DBClusters[0].DBSubnetGroup' --output text)"

    ADFS_VPC_ID="$(aws rds describe-db-subnet-groups --db-subnet-group-name "$SUBNET_GROUP" \
        --region "$REGION" --query 'DBSubnetGroups[0].VpcId' --output text)"

    SUBNET_IDS="$(aws rds describe-db-subnet-groups --db-subnet-group-name "$SUBNET_GROUP" \
        --region "$REGION" --query 'DBSubnetGroups[0].Subnets[].SubnetIdentifier' --output text)"

    echo "  VPC: $ADFS_VPC_ID"
    echo ""
    echo "  Subnets in the cluster's DB subnet group:"
    aws ec2 describe-subnets --subnet-ids $SUBNET_IDS --region "$REGION" \
        --query 'Subnets[].{Subnet:SubnetId,AZ:AvailabilityZone,Public:MapPublicIpOnLaunch}' \
        --output table

    ADFS_SUBNET_ID="$(echo $SUBNET_IDS | awk '{print $1}')"
    echo ""
    echo "  Using $ADFS_SUBNET_ID for the domain controller (first in the group)."
    echo "  To choose another listed subnet, set both ADFS_VPC_ID and ADFS_SUBNET_ID in $ENV_FILE."
fi

echo ""
echo "Domain controller will deploy into:"
echo "  VPC:    $ADFS_VPC_ID"
echo "  Subnet: $ADFS_SUBNET_ID"
echo ""

# Export everything the CDK app reads. The DSRM password is generated into Secrets Manager
# by the stack, so it is never set or exported here.
export ADFS_VPC_ID ADFS_SUBNET_ID ADFS_KEY_NAME
export ADFS_DOMAIN_DNS_NAME ADFS_DOMAIN_NETBIOS_NAME ADFS_INSTANCE_TYPE
export ADFS_DSRM_SECRET_NAME

# --- Deploy ---
cd "$CDK_DIR"
echo "Compiling CDK app..."
mvn -q compile

echo "Checking CDK bootstrap..."
if ! aws cloudformation describe-stacks --stack-name CDKToolkit --region "$REGION" &>/dev/null; then
    echo "  Bootstrapping CDK (first time)..."
    cdk bootstrap
fi

echo "Deploying the domain controller (this can take several minutes)..."
cdk deploy adfs-domain-controller --require-approval never

echo ""
echo "Done. Next:"
echo "  1. Open the domain controller through Systems Manager Fleet Manager Remote Desktop"
echo "     (see the DomainControllerInstanceId output), then run:"
echo "       C:\\setup-adfs.ps1 -AwsAccountId \"$CDK_DEFAULT_ACCOUNT\" -SamlProviderName \"${ADFS_SAML_PROVIDER_NAME:-ADFS}\""
echo "  2. Copy the generated FederationMetadata.xml back, set ADFS_FEDERATION_METADATA_PATH,"
echo "     then deploy the IAM identity provider:  cdk deploy adfs-iam-identity-provider"
