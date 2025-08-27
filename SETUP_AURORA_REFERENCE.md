# Aurora Setup Reference Guide

## Overview

The `setup-aurora.sh` script creates an Aurora PostgreSQL cluster for the AWS JDBC Driver demo. 

**Important**: This script does NOT create VPCs, security groups, or DB subnet groups - it only validates that they exist and are properly configured.

## Prerequisites

You need these existing AWS resources:
1. **VPC** with subnets in at least 2 availability zones
2. **Security Group** that allows inbound port 5432 (PostgreSQL)
3. **DB Subnet Group** with subnets in different AZs

## Configuration (.env file)

Fill in your `.env` file with these values:

```bash
# Aurora Cluster Configuration
AURORA_CLUSTER_ID=aurora-jdbc-demo
AURORA_DB_USERNAME=postgres
AURORA_DB_NAME=postgres

# AWS Infrastructure Configuration
AWS_REGION=us-east-1
AWS_VPC_ID=vpc-xxxx                         # Replace with your VPC ID
AWS_SECURITY_GROUP_ID=sg-xxxx               # Replace with your Security Group ID
AWS_DB_SUBNET_GROUP_NAME=your-subnet-group  # Replace with your DB Subnet Group name
```

## Finding Your AWS Resources

### 1. Find Your VPC

**List all VPCs:**
```bash
aws ec2 describe-vpcs --query 'Vpcs[*].[VpcId,IsDefault,CidrBlock]' --output table
```

**Get default VPC:**
```bash
aws ec2 describe-vpcs --filters "Name=is-default,Values=true" --query 'Vpcs[0].VpcId' --output text
```

**Example output:**
```
vpc-12345678
```

### 2. Find Security Group (Must Allow Port 5432)

**List security groups in your VPC:**
```bash
aws ec2 describe-security-groups --filters "Name=vpc-id,Values=vpc-12345678" --query 'SecurityGroups[*].[GroupId,GroupName]' --output table
```

**Check if security group allows port 5432:**
```bash
aws ec2 describe-security-groups --group-ids sg-12345678 --query "SecurityGroups[0].IpPermissions[?FromPort<=\`5432\` && ToPort>=\`5432\`]" --output text
```

**If empty, add port 5432 rule:**
```bash
aws ec2 authorize-security-group-ingress \
    --group-id sg-12345678 \
    --protocol tcp \
    --port 5432 \
    --cidr 10.0.0.0/16
```

### 3. Find DB Subnet Group

**List all DB subnet groups:**
```bash
aws rds describe-db-subnet-groups --query 'DBSubnetGroups[*].[DBSubnetGroupName,VpcId]' --output table
```

**If none exist, create one:**
```bash
# Get subnets in your VPC (need at least 2 in different AZs)
aws ec2 describe-subnets --filters "Name=vpc-id,Values=vpc-12345678" --query 'Subnets[*].[SubnetId,AvailabilityZone]' --output table

# Create DB subnet group
aws rds create-db-subnet-group \
    --db-subnet-group-name aurora-demo-subnet-group \
    --db-subnet-group-description "Aurora demo subnet group" \
    --subnet-ids subnet-12345678 subnet-87654321
```

## Verification Commands

Before running the setup script, verify your resources:

### Verify VPC
```bash
aws ec2 describe-vpcs --vpc-ids vpc-12345678
```

### Verify Security Group (Port 5432)
```bash
aws ec2 describe-security-groups --group-ids sg-12345678 --query "SecurityGroups[0].IpPermissions[?FromPort<=\`5432\` && ToPort>=\`5432\`]"
```

### Verify DB Subnet Group
```bash
aws rds describe-db-subnet-groups --db-subnet-group-name your-subnet-group-name
```

## Quick Setup Commands

**Get all values at once:**
```bash
# Get region
echo "Region: $(aws configure get region)"

# Get default VPC
DEFAULT_VPC=$(aws ec2 describe-vpcs --filters "Name=is-default,Values=true" --query 'Vpcs[0].VpcId' --output text)
echo "Default VPC: $DEFAULT_VPC"

# List security groups in VPC
echo "Security Groups:"
aws ec2 describe-security-groups --filters "Name=vpc-id,Values=$DEFAULT_VPC" --query 'SecurityGroups[*].[GroupId,GroupName]' --output table

# List DB subnet groups
echo "DB Subnet Groups:"
aws rds describe-db-subnet-groups --query 'DBSubnetGroups[*].[DBSubnetGroupName,VpcId]' --output table
```

## Example .env Configuration

```bash
# Aurora Cluster Configuration
AURORA_CLUSTER_ID=aurora-jdbc-demo
AURORA_DB_USERNAME=postgres
AURORA_DB_NAME=postgres

# AWS Infrastructure Configuration (Replace with your actual values)
AWS_REGION=us-east-1
AWS_VPC_ID=vpc-0a1b2c3d4e5f67890
AWS_SECURITY_GROUP_ID=sg-0a1b2c3d4e5f67890
AWS_DB_SUBNET_GROUP_NAME=default
```

## Common Issues

### Issue: "VPC not found"
```bash
# Check if VPC exists in your region
aws ec2 describe-vpcs --vpc-ids vpc-12345678 --region us-east-1
```

### Issue: "Security Group does not allow port 5432"
```bash
# Add port 5432 rule
aws ec2 authorize-security-group-ingress \
    --group-id sg-12345678 \
    --protocol tcp \
    --port 5432 \
    --cidr 10.0.0.0/16
```

### Issue: "DB Subnet Group not found"
```bash
# Create DB subnet group
SUBNETS=$(aws ec2 describe-subnets --filters "Name=vpc-id,Values=vpc-12345678" --query 'Subnets[*].SubnetId' --output text)
aws rds create-db-subnet-group \
    --db-subnet-group-name aurora-demo-subnet-group \
    --db-subnet-group-description "Aurora demo subnet group" \
    --subnet-ids $SUBNETS
```

## Next Steps

1. **Fill in .env file** with your actual AWS resource IDs
2. **Run setup script**: `./setup-aurora.sh`
3. **Run demo**: `./demo.sh standard-jdbc`
4. **Clean up**: `./cleanup-aurora.sh`