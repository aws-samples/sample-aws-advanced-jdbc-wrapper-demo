#!/bin/bash

# Aurora CDK Java Setup Script for AWS JDBC Driver Demo
# This script sets up the CDK environment and deploys Aurora cluster using Java CDK

set -e

echo "🚀 Setting up Aurora cluster using AWS CDK (Java)..."
echo "=================================================="


# Check prerequisites
echo "📋 Checking prerequisites..."

# Check if AWS CLI is configured
if ! aws sts get-caller-identity &>/dev/null; then
    echo "❌ ERROR: AWS CLI not configured. Please run 'aws configure' first."
    exit 1
fi

# Check if Java is installed
if ! command -v java &> /dev/null; then
    echo "❌ ERROR: Java not found. Please install Java 8+ first."
    exit 1
fi

# Check if Maven is installed
if ! command -v mvn &> /dev/null; then
    echo "❌ ERROR: Maven not found. Please install Maven first."
    echo "   Example installation commands:"
    echo "   Amazon Linux/RHEL/CentOS: sudo yum install -y maven"
    echo "   Ubuntu/Debian: sudo apt-get install -y maven"
    exit 1
fi

# Check if CDK is installed
if ! command -v cdk &> /dev/null; then
    echo "📦 Installing AWS CDK CLI..."
    npm install -g aws-cdk
fi

# Navigate to CDK directory
cd infrastructure/cdk

echo "✅ Prerequisites checked"

# Set up CDK environment variables
echo "🔧 Setting up CDK environment..."
export CDK_DEFAULT_ACCOUNT=$(aws sts get-caller-identity --query Account --output text)
export CDK_DEFAULT_REGION=$(aws configure get region)

# Check if region is configured
if [ -z "$CDK_DEFAULT_REGION" ]; then
    echo "⚠️  No AWS region configured!"
    echo ""
    echo "Please either:"
    echo "1. Configure AWS CLI: Example:  aws configure set region us-east-1"
    echo "2. Or create a .env file with AWS_REGION. Example: AWS_REGION=us-east-1"
    echo ""
    echo "After setting up region, run this script again."
    exit 1
fi

echo "   Account: $CDK_DEFAULT_ACCOUNT"
echo "   Region: $CDK_DEFAULT_REGION"

# Check if .env file exists (optional)
if [ -f "../../.env" ]; then
    echo "✅ Found .env configuration file - using custom settings"
    # Source the .env file to override CDK_DEFAULT_REGION if AWS_REGION is set
    source ../../.env
    if [ -n "$AWS_REGION" ]; then
        export CDK_DEFAULT_REGION="$AWS_REGION"
        echo "   Using region from .env: $CDK_DEFAULT_REGION"
    fi
else
    echo "ℹ️  No .env file found - using CDK defaults"
    echo "   - Stack: aws-jdbc-driver-stack"
    echo "   - Cluster: demo-app"
    echo "   - Creates new VPC, security group, and subnet group"
fi

# Install dependencies
echo "📦 Installing Java dependencies..."
mvn compile

# Bootstrap CDK (if needed)
echo "🔄 Checking CDK bootstrap status..."
if ! aws cloudformation describe-stacks --stack-name CDKToolkit --region "$CDK_DEFAULT_REGION" &>/dev/null; then
    echo "   🚀 Bootstrapping CDK (first time setup)..."
    cdk bootstrap
else
    echo "   ✅ CDK already bootstrapped"
fi



# Deploy the stack
echo "🚀 Deploying Aurora cluster..."
echo "   This may take 10-15 minutes..."
cdk deploy --require-approval never

echo ""
echo "🎉 Aurora cluster deployment completed!"
echo "=================================================="

# Wait for stack to be fully available
echo "⏳ Waiting for stack to be fully available..."
STACK_NAME="aws-jdbc-driver-stack"

# Ensure region is set for wait command
if [ -z "$CDK_DEFAULT_REGION" ]; then
    CDK_DEFAULT_REGION=$(aws configure get region)
fi

echo "Waiting for stack completion in region: $CDK_DEFAULT_REGION"
aws cloudformation wait stack-create-complete --stack-name "$STACK_NAME" --region "$CDK_DEFAULT_REGION" 2>/dev/null || \
aws cloudformation wait stack-update-complete --stack-name "$STACK_NAME" --region "$CDK_DEFAULT_REGION" 2>/dev/null

# Extract CDK outputs for user-friendly display
echo "📋 Extracting connection details from CDK outputs..."

# Ensure region is set
if [ -z "$CDK_DEFAULT_REGION" ]; then
    CDK_DEFAULT_REGION=$(aws configure get region)
    if [ -z "$CDK_DEFAULT_REGION" ]; then
        CDK_DEFAULT_REGION="us-east-1"
    fi
fi

echo "Checking CloudFormation stack outputs in region: $CDK_DEFAULT_REGION"

# Debug: Check if stack exists
if ! aws cloudformation describe-stacks --stack-name "$STACK_NAME" --region "$CDK_DEFAULT_REGION" &>/dev/null; then
    echo "❌ ERROR: Stack '$STACK_NAME' not found in region '$CDK_DEFAULT_REGION'"
    echo "Available stacks:"
    aws cloudformation list-stacks --region "$CDK_DEFAULT_REGION" --query "StackSummaries[?StackStatus!='DELETE_COMPLETE'].StackName" --output table
    exit 1
fi

# Get CDK outputs
USERNAME=$(aws cloudformation describe-stacks --stack-name "$STACK_NAME" --region "$CDK_DEFAULT_REGION" --query "Stacks[0].Outputs[?OutputKey=='Username'].OutputValue" --output text 2>/dev/null || echo "postgres")
WRITER_ENDPOINT=$(aws cloudformation describe-stacks --stack-name "$STACK_NAME" --region "$CDK_DEFAULT_REGION" --query "Stacks[0].Outputs[?OutputKey=='WriterEndpoint'].OutputValue" --output text 2>/dev/null || echo "")
SECRET_ARN=$(aws cloudformation describe-stacks --stack-name "$STACK_NAME" --region "$CDK_DEFAULT_REGION" --query "Stacks[0].Outputs[?OutputKey=='SecretArn'].OutputValue" --output text 2>/dev/null || echo "")
DATABASE_NAME=$(aws cloudformation describe-stacks --stack-name "$STACK_NAME" --region "$CDK_DEFAULT_REGION" --query "Stacks[0].Outputs[?OutputKey=='DatabaseName'].OutputValue" --output text 2>/dev/null || echo "postgres")

# Check if outputs were retrieved successfully
if [ -z "$WRITER_ENDPOINT" ] || [ "$WRITER_ENDPOINT" = "None" ]; then
    echo "❌ ERROR: Could not retrieve CDK outputs. Stack may still be deploying or outputs not available."
    echo "   Please wait a few minutes and re-run this script."
    echo "   You can check stack status with: aws cloudformation describe-stacks --stack-name $STACK_NAME --region $CDK_DEFAULT_REGION"
    exit 1
fi

# Construct JDBC URL from writer endpoint and database name
JDBC_URL="jdbc:postgresql://${WRITER_ENDPOINT}/${DATABASE_NAME}"

echo ""
echo "📋 Connection Details:"
echo "=================================================="
echo "Writer Endpoint: ${WRITER_ENDPOINT}"
echo "Username: ${USERNAME}"
echo "Database: ${DATABASE_NAME}"
echo "Port: 5432"
echo "Region: ${CDK_DEFAULT_REGION}"

echo ""
echo "📝 Updating application.properties..."
echo "=================================================="

# Navigate back to project root to update application.properties
cd ../..

# Update application.properties file
APP_PROPS_FILE="src/main/resources/application.properties"
if [ -f "$APP_PROPS_FILE" ]; then
    # Create backup
    cp "$APP_PROPS_FILE" "${APP_PROPS_FILE}.backup"
    echo "✅ Backup created: ${APP_PROPS_FILE}.backup"
    
    # Update the properties
    cat > "$APP_PROPS_FILE" << EOF
db.url=${JDBC_URL}
db.username=${USERNAME}
EOF
    echo "✅ Updated $APP_PROPS_FILE with connection details"
else
    echo "⚠️  $APP_PROPS_FILE not found, creating new file..."
    mkdir -p "$(dirname "$APP_PROPS_FILE")"
    cat > "$APP_PROPS_FILE" << EOF
db.url=${JDBC_URL}
db.username=${USERNAME}
EOF
    echo "✅ Created $APP_PROPS_FILE with connection details"
fi

echo ""
echo "📋 Next steps:"
echo "1. ✅ application.properties has been updated automatically"
echo "2. Set up database password environment variable (see step 5 in README)"
echo "3. Run the demo: ./gradlew clean run"
echo ""
echo "🧹 To clean up resources later:"
echo "   cd infrastructure/cdk && cdk destroy"