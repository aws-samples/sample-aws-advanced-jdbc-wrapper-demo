#!/bin/bash

# Aurora Cleanup Script for AWS JDBC Wrapper Demo
# This script safely deletes only tagged demo resources

set -e

# Load environment variables from .env file
if [ -f ".env" ]; then
    echo "Loading configuration from .env file..."
    set -a
    source <(grep -v '^#' .env | grep -v '^$' | sed 's/#.*$//')
    set +a
else
    echo "ERROR: .env file not found!"
    echo "Please refer to README for setup instructions."
    exit 1
fi

CLUSTER_ID="$AURORA_CLUSTER_ID"
REGION="$AWS_REGION"

# Disable AWS CLI pager
export AWS_PAGER=""

echo "Cleaning up Aurora resources for JDBC Demo..."
echo "=================================================="
echo "Region: ${REGION}"
echo "Cluster: ${CLUSTER_ID}"
echo ""

# Function to check if resource has demo tags
check_demo_tags() {
    local resource_arn="${1}"
    local resource_type="${2}"
    
    echo "Checking tags for ${resource_type}: ${resource_arn}"
    
    # Get tags for the resource
    TAGS=$(aws rds list-tags-for-resource --region "${REGION}" --resource-name "${resource_arn}" --query 'TagList' --output json 2>/dev/null || echo '[]')
    
    # Check if required demo tags exist
    PROJECT_TAG=$(echo "${TAGS}" | jq -r '.[] | select(.Key=="Project") | .Value' 2>/dev/null || echo "")
    AUTO_DELETE_TAG=$(echo "${TAGS}" | jq -r '.[] | select(.Key=="AutoDelete") | .Value' 2>/dev/null || echo "")
    
    if [ "${PROJECT_TAG}" = "AWS-JDBC-Driver-Demo" ] && [ "${AUTO_DELETE_TAG}" = "true" ]; then
        echo "Resource has demo tags - safe to delete"
        return 0
    else
        echo "Resource missing demo tags - skipping for safety"
        echo "   Project tag: '${PROJECT_TAG}' (expected: 'AWS-JDBC-Driver-Demo')"
        echo "   AutoDelete tag: '${AUTO_DELETE_TAG}' (expected: 'true')"
        return 1
    fi
}

# Function to delete all DB instances simultaneously
delete_instances() {
    echo "Finding DB instances for cluster: ${CLUSTER_ID}"
    
    # First check if cluster exists and has proper tags
    CLUSTER_ARN=$(aws rds describe-db-clusters --region "${REGION}" --db-cluster-identifier "${CLUSTER_ID}" --query 'DBClusters[0].DBClusterArn' --output text 2>/dev/null || echo "")
    
    if [ -z "${CLUSTER_ARN}" ] || [ "${CLUSTER_ARN}" = "None" ]; then
        echo "Cluster ${CLUSTER_ID} not found - no instances to delete"
        return 0
    fi
    
    # Verify cluster has demo tags before proceeding with instance deletion
    if ! check_demo_tags "${CLUSTER_ARN}" "DB Cluster"; then
        echo "WARNING: Cluster not tagged as demo resource - skipping instance deletion"
        return 1
    fi
    
    # Get all instances in the cluster
    INSTANCES=$(aws rds describe-db-instances --region "${REGION}" --query "DBInstances[?DBClusterIdentifier=='${CLUSTER_ID}'].DBInstanceIdentifier" --output text 2>/dev/null || echo "")
    
    if [ -z "${INSTANCES}" ]; then
        echo "No instances found for cluster ${CLUSTER_ID}"
        return 0
    fi
    
    echo "Deleting all instances simultaneously..."
    for instance in ${INSTANCES}; do
        echo ""
        echo "Processing instance: ${instance}"
        
        # Get instance ARN
        INSTANCE_ARN=$(aws rds describe-db-instances --region "${REGION}" --db-instance-identifier "${instance}" --query 'DBInstances[0].DBInstanceArn' --output text 2>/dev/null || echo "")
        
        if [ -n "${INSTANCE_ARN}" ] && [ "${INSTANCE_ARN}" != "None" ]; then
            if check_demo_tags "${INSTANCE_ARN}" "DB Instance"; then
                echo "Deleting instance: ${instance}"
                aws rds delete-db-instance \
                    --region "${REGION}" \
                    --db-instance-identifier "${instance}" \
                    --skip-final-snapshot \
                    --delete-automated-backups
                echo "Instance deletion initiated: ${instance}"
            else
                echo "WARNING: Skipping instance (not tagged as demo resource): ${instance}"
            fi
        else
            echo "ERROR: Could not get ARN for instance: ${instance}"
        fi
    done
}

# Function to delete cluster safely
delete_cluster() {
    echo ""
    echo "Processing cluster: ${CLUSTER_ID}"
    
    # Check if cluster exists and get ARN
    CLUSTER_ARN=$(aws rds describe-db-clusters --region "${REGION}" --db-cluster-identifier "${CLUSTER_ID}" --query 'DBClusters[0].DBClusterArn' --output text 2>/dev/null || echo "")
    
    if [ -z "${CLUSTER_ARN}" ] || [ "${CLUSTER_ARN}" = "None" ]; then
        echo "Cluster ${CLUSTER_ID} not found - nothing to delete"
        return 0
    fi
    
    # Check tags before proceeding
    if check_demo_tags "${CLUSTER_ARN}" "DB Cluster"; then
        echo "Deleting cluster: ${CLUSTER_ID}"
        aws rds delete-db-cluster \
            --region "${REGION}" \
            --db-cluster-identifier "${CLUSTER_ID}" \
            --skip-final-snapshot \
            --delete-automated-backups
        echo "Cluster deletion initiated: ${CLUSTER_ID}"
    else
        echo "WARNING: Skipping cluster (not tagged as demo resource): ${CLUSTER_ID}"
        return 1
    fi
}

# Main cleanup process
echo "Starting tagged resource cleanup..."
echo ""

# Delete all instances simultaneously
delete_instances

# Wait for instances to start deleting
echo ""
echo "Waiting for instances to begin deletion..."
sleep 30

# Then delete cluster
delete_cluster

echo ""
echo "Cleanup Summary:"
echo "=================================================="
echo "Cleanup process completed"
echo "WARNING: Only resources tagged with Project=AWS-JDBC-Driver-Demo and AutoDelete=true were deleted"
echo "Resources without proper tags were skipped for safety"
echo ""
echo "To monitor deletion progress:"
echo "   aws rds describe-db-clusters --db-cluster-identifier ${CLUSTER_ID}"
echo "   aws rds describe-db-instances --query \"DBInstances[?DBClusterIdentifier=='${CLUSTER_ID}']\""
echo ""
echo "Cost Note: Deletion may take 5-10 minutes. Billing stops when resources are fully deleted."