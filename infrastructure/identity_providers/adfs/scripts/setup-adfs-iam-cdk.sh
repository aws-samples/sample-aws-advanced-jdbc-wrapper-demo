#!/bin/bash

# AD FS IAM identity provider setup (CDK)
# Creates the IAM SAML identity provider (from the AD FS federation metadata) and the role
# the federated user assumes to connect to Aurora with an IAM token.
#
# Run this AFTER the domain controller exists and setup-adfs.ps1 has produced
# FederationMetadata.xml. Copy that file to this host and point ADFS_FEDERATION_METADATA_PATH
# at it (default: FederationMetadata.xml).
#
# Config comes from this module's .env: infrastructure/identity_providers/adfs/.env

set -e

echo "AD FS IAM identity provider setup (CDK)"
echo "========================================"

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
    echo "ERROR: $ENV_FILE not found. Copy the template: cp \"$MODULE_DIR/.env.example\" \"$ENV_FILE\""
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

# --- Federation metadata (produced by setup-adfs.ps1 on the domain controller) ---
METADATA_PATH="${ADFS_FEDERATION_METADATA_PATH:-FederationMetadata.xml}"
if [ ! -f "$METADATA_PATH" ]; then
    echo "ERROR: federation metadata not found at '$METADATA_PATH'."
    echo "       Run setup-adfs.ps1 on the domain controller, copy the generated"
    echo "       FederationMetadata.xml here, and set ADFS_FEDERATION_METADATA_PATH to it."
    exit 1
fi
# CDK reads the metadata relative to the cdk dir; give it an absolute path.
export ADFS_FEDERATION_METADATA_PATH="$(cd "$(dirname "$METADATA_PATH")" && pwd)/$(basename "$METADATA_PATH")"
echo "Federation metadata: $ADFS_FEDERATION_METADATA_PATH"

# --- Discover the Aurora cluster resource id (for the rds-db:connect policy) ---
AURORA_STACK_NAME="${AURORA_STACK_NAME:-aws-jdbc-driver-stack}"
if [ -z "$AURORA_CLUSTER_RESOURCE_ID" ]; then
    echo "Discovering the Aurora cluster resource id from stack '$AURORA_STACK_NAME'..."
    AURORA_CLUSTER_RESOURCE_ID="$(aws cloudformation describe-stacks \
        --stack-name "$AURORA_STACK_NAME" --region "$REGION" \
        --query "Stacks[0].Outputs[?OutputKey=='ClusterResourceId'].OutputValue" \
        --output text 2>/dev/null || true)"
    if [ -z "$AURORA_CLUSTER_RESOURCE_ID" ] || [ "$AURORA_CLUSTER_RESOURCE_ID" = "None" ]; then
        echo "ERROR: Could not read ClusterResourceId from stack '$AURORA_STACK_NAME'."
        echo "       Deploy Aurora first, or set AURORA_CLUSTER_RESOURCE_ID in .env."
        exit 1
    fi
fi
export AURORA_CLUSTER_RESOURCE_ID
echo "Aurora cluster resource id: $AURORA_CLUSTER_RESOURCE_ID"

# --- Warn if the provider/role already exist (CDK cannot create over existing ones) ---
PROVIDER_NAME="${ADFS_SAML_PROVIDER_NAME:-ADFS}"
ROLE_NAME="${ADFS_IAM_ROLE_NAME:-ADFS-JDBCDemo}"
export ADFS_SAML_PROVIDER_NAME="$PROVIDER_NAME"
export ADFS_IAM_ROLE_NAME="$ROLE_NAME"
export AURORA_IAM_DB_USERNAME="${AURORA_IAM_DB_USERNAME:-db_iam_user}"

if aws iam get-saml-provider \
     --saml-provider-arn "arn:aws:iam::${CDK_DEFAULT_ACCOUNT}:saml-provider/${PROVIDER_NAME}" &>/dev/null; then
    echo ""
    echo "WARNING: an IAM SAML provider named '$PROVIDER_NAME' already exists."
    echo "         CDK cannot create over an existing provider. Either delete it first, or set"
    echo "         ADFS_SAML_PROVIDER_NAME to a new name in .env (and re-run the AD FS claim"
    echo "         rules with the matching provider/role names on the domain controller)."
    exit 1
fi
if aws iam get-role --role-name "$ROLE_NAME" &>/dev/null; then
    echo ""
    echo "WARNING: an IAM role named '$ROLE_NAME' already exists."
    echo "         CDK cannot create over an existing role. Delete it first, or set"
    echo "         ADFS_IAM_ROLE_NAME to a new name in .env (matching the DC's claim rules)."
    exit 1
fi

echo ""
echo "Will create:"
echo "  SAML provider : $PROVIDER_NAME"
echo "  IAM role      : $ROLE_NAME  (rds-db:connect on $AURORA_CLUSTER_RESOURCE_ID/$AURORA_IAM_DB_USERNAME)"
echo ""

# --- Deploy ---
cd "$CDK_DIR"
echo "Compiling CDK app..."
mvn -q compile

echo "Checking CDK bootstrap..."
if ! aws cloudformation describe-stacks --stack-name CDKToolkit --region "$REGION" &>/dev/null; then
    echo "  Bootstrapping CDK (first time)..."
    cdk bootstrap
fi

echo "Deploying the IAM identity provider..."
cdk deploy adfs-iam-identity-provider --require-approval never

echo ""
echo "Done. Outputs above include SamlProviderArn and FederatedRoleArn - use them as"
echo "iam.idp.arn and iam.role.arn in the JDBC federatedAuth stage."
