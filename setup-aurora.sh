#!/bin/bash

# Aurora Cluster Setup Script for AWS JDBC Wrapper Demo
# This script creates the Aurora cluster with proper tagging for resource management

set -e

# Load environment variables from .env file
if [ -f ".env" ]; then
    echo "Loading configuration from .env file..."
    set -a
    source <(grep -v '^#' .env | grep -v '^$' | sed 's/#.*$//')
    set +a
else
    echo "ERROR: .env file not found! Please create .env file with required variables."
    exit 1
fi

# Map environment variables to script variables
CLUSTER_ID="$AURORA_CLUSTER_ID"
DB_USERNAME="$AURORA_DB_USERNAME" 
DB_NAME="$AURORA_DB_NAME"

REGION="$AWS_REGION"
SELECTED_VPC="$AWS_VPC_ID"
SELECTED_SG="$AWS_SECURITY_GROUP_ID"
SUBNET_GROUP_NAME="$AWS_DB_SUBNET_GROUP_NAME"

# Define standard tags for all resources
DEMO_TAGS='[
    {
        "Key": "Project",
        "Value": "AWS-JDBC-Driver-Demo"
    },
    {
        "Key": "Environment",
        "Value": "Demo"
    },
    {
        "Key": "Purpose",
        "Value": "JDBC-Driver-Testing"
    },
    {
        "Key": "Owner",
        "Value": "Developer"
    },
    {
        "Key": "AutoDelete",
        "Value": "true"
    },
    {
        "Key": "CreatedBy",
        "Value": "setup-aurora-script"
    }
]'

# Prompt for database password securely
echo "Database Configuration:"
echo "   Cluster: ${CLUSTER_ID}"
echo "   Username: ${DB_USERNAME}"
echo "   Database: ${DB_NAME}"
echo ""
read -s -p "Enter database master password: " DB_PASSWORD
echo ""

# Validate password is not empty
if [ -z "${DB_PASSWORD}" ]; then
    echo "ERROR: Password cannot be empty!"
    exit 1
fi

echo "Password set successfully"

echo "Setting up Aurora PostgreSQL Cluster for JDBC Demo..."
echo "=================================================="

# Check if AWS CLI is configured
if ! aws sts get-caller-identity &>/dev/null; then
    echo "ERROR: AWS CLI not configured. Please run 'aws configure' first."
    exit 1
fi

# Disable AWS CLI pager to prevent prompts
export AWS_PAGER=""

# Region is already set in configuration variables above
# Convert to lowercase if needed
REGION=$(echo "${REGION}" | tr '[:upper:]' '[:lower:]')

echo "Using region: ${REGION}"

# Function to validate VPC exists
validate_vpc() {
    echo "Validating VPC: ${SELECTED_VPC}"
    if ! aws ec2 describe-vpcs --region "${REGION}" --vpc-ids "${SELECTED_VPC}" &>/dev/null; then
        echo "ERROR: VPC ${SELECTED_VPC} not found in region ${REGION}"
        exit 1
    fi
    echo "VPC ${SELECTED_VPC} validated"
}

# Function to validate security group exists and has port 5432 access
validate_security_group() {
    echo "Validating Security Group: ${SELECTED_SG}"
    
    # Check if security group exists
    if ! aws ec2 describe-security-groups --region "${REGION}" --group-ids "${SELECTED_SG}" &>/dev/null; then
        echo "ERROR: Security Group ${SELECTED_SG} not found in region ${REGION}"
        exit 1
    fi
    
    # Check if security group allows port 5432
    PORT_5432_RULES=$(aws ec2 describe-security-groups --region "${REGION}" --group-ids "${SELECTED_SG}" --query "SecurityGroups[0].IpPermissions[?FromPort<=\`5432\` && ToPort>=\`5432\`]" --output text 2>/dev/null || echo "")
    
    if [ -n "${PORT_5432_RULES}" ] && [ "${PORT_5432_RULES}" != "None" ]; then
        echo "Security Group ${SELECTED_SG} validated (allows port 5432)"
        
        # Show basic info about port 5432 access
        echo "Port 5432 is accessible from configured sources"
        echo "    (Security group has inbound rules allowing PostgreSQL connections)"
    else
        echo "ERROR: Security Group ${SELECTED_SG} does not allow inbound port 5432"
        echo "    Aurora PostgreSQL requires inbound access on port 5432"
        echo "    Please add a rule to allow port 5432 before proceeding"
        exit 1
    fi
}

# Function to validate DB subnet group exists
validate_subnet_group() {
    echo "Validating DB Subnet Group: ${SUBNET_GROUP_NAME}"
    
    if ! aws rds describe-db-subnet-groups --region "${REGION}" --db-subnet-group-name "${SUBNET_GROUP_NAME}" &>/dev/null; then
        echo "ERROR: DB Subnet Group ${SUBNET_GROUP_NAME} not found in region ${REGION}"
        echo "    Please create the DB subnet group first with subnets in at least 2 availability zones"
        exit 1
    fi
    
    echo "DB Subnet Group ${SUBNET_GROUP_NAME} validated"
}

# Validate hardcoded configuration
validate_vpc
validate_security_group
validate_subnet_group

echo ""
echo "Configuration Summary:"
echo "========================"
echo "Region: ${REGION}"
echo "VPC: ${SELECTED_VPC}"
echo "Security Group: ${SELECTED_SG}"
echo "DB Subnet Group: ${SUBNET_GROUP_NAME}"
echo "Tags: AWS-JDBC-Driver-Demo, Environment=Demo, AutoDelete=true"
echo ""

# Check if cluster already exists - fail if it does
if aws rds describe-db-clusters --region "${REGION}" --db-cluster-identifier "${CLUSTER_ID}" &>/dev/null; then
    echo "ERROR: Cluster ${CLUSTER_ID} already exists!"
    echo "   Please use a different AURORA_CLUSTER_ID in .env file or delete the existing cluster first."
    echo "   To delete: ./cleanup-aurora.sh"
    exit 1
fi

echo "Creating Aurora PostgreSQL Serverless cluster with tags..."

# Create Aurora cluster with selected configuration and tags
echo "Creating Aurora cluster with configuration:"
echo "   Region: ${REGION}"
echo "   VPC: ${SELECTED_VPC}"
echo "   Security Group: ${SELECTED_SG}"
echo "   DB Subnet Group: ${SUBNET_GROUP_NAME}"
echo "   Tags: Project=AWS-JDBC-Driver-Demo, Environment=Demo"
echo ""

aws rds create-db-cluster \
    --region "${REGION}" \
    --db-cluster-identifier "${CLUSTER_ID}" \
    --engine aurora-postgresql \
    --engine-mode provisioned \
    --master-username "${DB_USERNAME}" \
    --master-user-password "${DB_PASSWORD}" \
    --serverless-v2-scaling-configuration MinCapacity=0.5,MaxCapacity=2 \
    --db-subnet-group-name "${SUBNET_GROUP_NAME}" \
    --vpc-security-group-ids "${SELECTED_SG}" \
    --no-deletion-protection \
    --tags "${DEMO_TAGS}"

echo "Aurora cluster creation initiated with tags..."

# Create writer instance with cluster-specific naming
WRITER_ID="${CLUSTER_ID}-writer"
echo "Creating writer instance: ${WRITER_ID}"
if aws rds describe-db-instances --region "${REGION}" --db-instance-identifier "${WRITER_ID}" &>/dev/null; then
    echo "ERROR: Writer instance ${WRITER_ID} already exists!"
    echo "   Please use a different AURORA_CLUSTER_ID or delete existing instances."
    exit 1
fi

aws rds create-db-instance \
    --region "${REGION}" \
    --db-instance-identifier "${WRITER_ID}" \
    --db-instance-class db.serverless \
    --engine aurora-postgresql \
    --db-cluster-identifier "${CLUSTER_ID}" \
    --tags "${DEMO_TAGS}"
echo "Writer instance creation initiated: ${WRITER_ID}"

# Create reader instances with cluster-specific naming
echo "Creating reader instances..."
for i in 1 2; do
    READER_ID="${CLUSTER_ID}-reader-${i}"
    echo "Creating reader instance: ${READER_ID}"
    if aws rds describe-db-instances --region "${REGION}" --db-instance-identifier "${READER_ID}" &>/dev/null; then
        echo "ERROR: Reader instance ${READER_ID} already exists!"
        echo "   Please use a different AURORA_CLUSTER_ID or delete existing instances."
        exit 1
    fi
    
    aws rds create-db-instance \
        --region "${REGION}" \
        --db-instance-identifier "${READER_ID}" \
        --db-instance-class db.serverless \
        --engine aurora-postgresql \
        --db-cluster-identifier "${CLUSTER_ID}" \
        --tags "${DEMO_TAGS}"
    echo "Reader instance ${i} creation initiated: ${READER_ID}"
done

echo ""
echo "Waiting for cluster to become available (this may take 10-15 minutes)..."
echo "   You can check status with: aws rds describe-db-clusters --db-cluster-identifier ${CLUSTER_ID}"

# Wait for cluster to be available
aws rds wait db-cluster-available --region "${REGION}" --db-cluster-identifier "${CLUSTER_ID}"

echo ""
echo "Aurora cluster setup complete with proper tagging!"
echo "================================================="=

# Get connection details
CLUSTER_INFO=$(aws rds describe-db-clusters --region "${REGION}" --db-cluster-identifier "${CLUSTER_ID}" --query 'DBClusters[0]')
WRITER_ENDPOINT=$(echo "${CLUSTER_INFO}" | jq -r '.Endpoint')
READER_ENDPOINT=$(echo "${CLUSTER_INFO}" | jq -r '.ReaderEndpoint')

echo ""
echo "Connection Details:"
echo "=================================================="
echo "Writer Endpoint: ${WRITER_ENDPOINT}"
echo "Reader Endpoint: ${READER_ENDPOINT}"
echo "Username: ${DB_USERNAME}"
echo "Database: ${DB_NAME}"
echo "Port: 5432"
echo "Region: ${REGION}"

echo ""
echo "Resource Tags Applied:"
echo "=================================================="
echo "Project: AWS-JDBC-Driver-Demo"
echo "Environment: Demo"
echo "Purpose: JDBC-Driver-Testing"
echo "AutoDelete: true"
echo "CreatedBy: setup-aurora-script"

echo ""
echo "Update your application.properties with:"
echo "=================================================="
echo "db.url=jdbc:postgresql://${WRITER_ENDPOINT}:5432/${DB_NAME}"
echo "db.username=${DB_USERNAME}"
echo "db.password=<Your DB password>"

echo ""
echo "Security Note:"
echo "=================================================="
echo "Resources are tagged for easy identification and cleanup."
echo "Use tag-based IAM policies to restrict deletion to tagged resources only."