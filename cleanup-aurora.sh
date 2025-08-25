#!/bin/bash

# Aurora Cleanup Script for AWS JDBC Wrapper Demo
# This script safely deletes only tagged demo resources

set -e

# Load environment variables from .env file
if [ -f ".env" ]; then
    echo "📄 Loading configuration from .env file..."
    set -a
    source <(grep -v '^#' .env | grep -v '^$' | sed 's/#.*$//')
    set +a
else
    echo "❌ .env file not found! Using default values..."
    AURORA_CLUSTER_ID="aurora-jdbc-demo"
    AWS_REGION="us-east-1"
fi

CLUSTER_ID="$AURORA_CLUSTER_ID"
REGION="$AWS_REGION"

# Disable AWS CLI pager
export AWS_PAGER=""

echo "🧹 Cleaning up Aurora resources for JDBC Demo..."
echo "=================================================="
echo "Region: $REGION"
echo "Cluster: $CLUSTER_ID"
echo ""

# Function to check if resource has demo tags
check_demo_tags() {
    local resource_arn=$1
    local resource_type=$2
    
    echo "🔍 Checking tags for $resource_type: $resource_arn"
    
    # Get tags for the resource
    TAGS=$(aws rds list-tags-for-resource --region $REGION --resource-name "$resource_arn" --query 'TagList' --output json 2>/dev/null || echo '[]')
    
    # Check if required demo tags exist
    PROJECT_TAG=$(echo "$TAGS" | jq -r '.[] | select(.Key=="Project") | .Value' 2>/dev/null || echo "")
    AUTO_DELETE_TAG=$(echo "$TAGS" | jq -r '.[] | select(.Key=="AutoDelete") | .Value' 2>/dev/null || echo "")
    
    if [ "$PROJECT_TAG" = "AWS-JDBC-Driver-Demo" ] && [ "$AUTO_DELETE_TAG" = "true" ]; then
        echo "✅ Resource has demo tags - safe to delete"
        return 0
    else
        echo "❌ Resource missing demo tags - skipping for safety"
        echo "   Project tag: '$PROJECT_TAG' (expected: 'AWS-JDBC-Driver-Demo')"
        echo "   AutoDelete tag: '$AUTO_DELETE_TAG' (expected: 'true')"
        return 1
    fi
}

# Function to delete DB instances safely
delete_instances() {
    echo "🔍 Finding DB instances for cluster: $CLUSTER_ID"
    
    # Get all instances in the cluster
    INSTANCES=$(aws rds describe-db-instances --region $REGION --query "DBInstances[?DBClusterIdentifier=='$CLUSTER_ID'].DBInstanceIdentifier" --output text 2>/dev/null || echo "")
    
    if [ -z "$INSTANCES" ]; then
        echo "ℹ️  No instances found for cluster $CLUSTER_ID"
        return 0
    fi
    
    for instance in $INSTANCES; do
        echo ""
        echo "🔍 Processing instance: $instance"
        
        # Get instance ARN
        INSTANCE_ARN=$(aws rds describe-db-instances --region $REGION --db-instance-identifier "$instance" --query 'DBInstances[0].DBInstanceArn' --output text 2>/dev/null || echo "")
        
        if [ -n "$INSTANCE_ARN" ] && [ "$INSTANCE_ARN" != "None" ]; then
            if check_demo_tags "$INSTANCE_ARN" "DB Instance"; then
                echo "🗑️  Deleting instance: $instance"
                aws rds delete-db-instance \
                    --region $REGION \
                    --db-instance-identifier "$instance" \
                    --skip-final-snapshot \
                    --delete-automated-backups
                echo "✅ Instance deletion initiated: $instance"
            else
                echo "⚠️  Skipping instance (not tagged as demo resource): $instance"
            fi
        else
            echo "❌ Could not get ARN for instance: $instance"
        fi
    done
}

# Function to delete cluster safely
delete_cluster() {
    echo ""
    echo "🔍 Processing cluster: $CLUSTER_ID"
    
    # Check if cluster exists
    if ! aws rds describe-db-clusters --region $REGION --db-cluster-identifier $CLUSTER_ID &>/dev/null; then
        echo "ℹ️  Cluster $CLUSTER_ID not found - nothing to delete"
        return 0
    fi
    
    # Get cluster ARN
    CLUSTER_ARN=$(aws rds describe-db-clusters --region $REGION --db-cluster-identifier $CLUSTER_ID --query 'DBClusters[0].DBClusterArn' --output text 2>/dev/null || echo "")
    
    if [ -n "$CLUSTER_ARN" ] && [ "$CLUSTER_ARN" != "None" ]; then
        if check_demo_tags "$CLUSTER_ARN" "DB Cluster"; then
            echo "🗑️  Deleting cluster: $CLUSTER_ID"
            aws rds delete-db-cluster \
                --region $REGION \
                --db-cluster-identifier $CLUSTER_ID \
                --skip-final-snapshot \
                --delete-automated-backups
            echo "✅ Cluster deletion initiated: $CLUSTER_ID"
        else
            echo "⚠️  Skipping cluster (not tagged as demo resource): $CLUSTER_ID"
            return 1
        fi
    else
        echo "❌ Could not get ARN for cluster: $CLUSTER_ID"
        return 1
    fi
}

# Main cleanup process
echo "🚀 Starting tagged resource cleanup..."
echo ""

# First delete instances
delete_instances

# Wait a bit for instances to start deleting
if [ -n "$INSTANCES" ]; then
    echo ""
    echo "⏳ Waiting 30 seconds for instances to begin deletion..."
    sleep 30
fi

# Then delete cluster
delete_cluster

echo ""
echo "📊 Cleanup Summary:"
echo "=================================================="
echo "✅ Cleanup process completed"
echo "⚠️  Only resources tagged with Project=AWS-JDBC-Driver-Demo and AutoDelete=true were deleted"
echo "🔍 Resources without proper tags were skipped for safety"
echo ""
echo "📝 To monitor deletion progress:"
echo "   aws rds describe-db-clusters --db-cluster-identifier $CLUSTER_ID"
echo "   aws rds describe-db-instances --query \"DBInstances[?DBClusterIdentifier=='$CLUSTER_ID']\""
echo ""
echo "💰 Cost Note: Deletion may take 5-10 minutes. Billing stops when resources are fully deleted."