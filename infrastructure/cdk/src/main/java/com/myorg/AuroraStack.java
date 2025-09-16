package com.myorg;

import software.amazon.awscdk.Stack;
import software.amazon.awscdk.StackProps;
import software.amazon.awscdk.CfnOutput;
import software.amazon.awscdk.Tags;
import software.amazon.awscdk.services.ec2.*;
import software.amazon.awscdk.services.rds.*;
import software.amazon.awscdk.services.rds.CredentialsBaseOptions;
import software.amazon.awscdk.customresources.*;
import software.constructs.Construct;

import java.util.Arrays;
import java.util.List;

public class AuroraStack extends Stack {
    public AuroraStack(final Construct scope, final String id, final StackProps props, final AuroraStackConfig config) {
        super(scope, id, props);
        
        // Ensure values are never null to avoid 'null' in resource names
        String clusterId = config.getClusterId() != null ? config.getClusterId() : "demo-app";
        String dbUsername = config.getDbUsername() != null ? config.getDbUsername() : "postgres";
        String dbName = config.getDbName() != null ? config.getDbName() : "postgres";

        // Use existing VPC or create new one
        IVpc vpc;
        if (config.getVpcId() != null && !config.getVpcId().trim().isEmpty()) {
            // Validate VPC exists
            vpc = Vpc.fromLookup(this, clusterId + "-existing-vpc", VpcLookupOptions.builder()
                    .vpcId(config.getVpcId())
                    .build());
        } else {
            // Create new VPC with 2 subnets in different AZs
            vpc = Vpc.Builder.create(this, clusterId + "-vpc")
                    .maxAzs(2) // Aurora needs at least 2 AZs
                    .natGateways(0) // No NAT gateways needed for Aurora
                    .subnetConfiguration(Arrays.<SubnetConfiguration>asList(
                            SubnetConfiguration.builder()
                                    .cidrMask(24)
                                    .name(clusterId + "-isolated")
                                    .subnetType(SubnetType.PRIVATE_ISOLATED)
                                    .build()
                    ))
                    .build();
        }

        // Security group - use existing or create new
        ISecurityGroup securityGroup;
        
        if (config.getExistingSecurityGroupId() != null && !config.getExistingSecurityGroupId().trim().isEmpty()) {
            // Use existing security group
            securityGroup = SecurityGroup.fromSecurityGroupId(this, clusterId + "-existing-sg", 
                    config.getExistingSecurityGroupId());
        } else {
            // Create new security group with custom name
            securityGroup = SecurityGroup.Builder.create(this, clusterId + "-security-group")
                    .vpc(vpc)
                    .securityGroupName("aws-jdbc-driver-stack-" + clusterId + "-security-group")
                    .description("Security group for Aurora PostgreSQL cluster")
                    .allowAllOutbound(true)
                    .build();

            // Allow inbound PostgreSQL connections on port 5432
            securityGroup.addIngressRule(
                    Peer.anyIpv4(),
                    Port.tcp(5432),
                    "Allow PostgreSQL connections"
            );
        }

        // DB subnet group - use existing or create new
        ISubnetGroup subnetGroup;
        
        if (config.getExistingSubnetGroupName() != null && !config.getExistingSubnetGroupName().trim().isEmpty()) {
            // Use existing subnet group
            subnetGroup = SubnetGroup.fromSubnetGroupName(this, clusterId + "-existing-subnet-group",
                    config.getExistingSubnetGroupName());
        } else {
            // Create new subnet group with custom name
            subnetGroup = SubnetGroup.Builder.create(this, clusterId + "-subnet-group")
                    .subnetGroupName("aws-jdbc-driver-stack-" + clusterId + "-subnet-group")
                    .description("Subnet group for Aurora PostgreSQL cluster")
                    .vpc(vpc)
                    .vpcSubnets(SubnetSelection.builder()
                            .subnetType(SubnetType.PRIVATE_ISOLATED)
                            .build())
                    .build();
        }

        // Create Aurora PostgreSQL cluster
        DatabaseCluster cluster = DatabaseCluster.Builder.create(this, clusterId + "-aurora-cluster")
                .engine(DatabaseClusterEngine.auroraPostgres(AuroraPostgresClusterEngineProps.builder()
                        .version(AuroraPostgresEngineVersion.VER_15_4)
                        .build()))
                .clusterIdentifier("aws-jdbc-driver-stack-" + clusterId)
                .credentials(Credentials.fromGeneratedSecret(
                    dbUsername, 
                    CredentialsBaseOptions.builder()
                        .secretName("aws-jdbc-driver-stack-" + clusterId + "-credentials")
                        .build()
                ))
                .defaultDatabaseName(dbName)
                .vpc(vpc)
                .securityGroups(Arrays.<ISecurityGroup>asList(securityGroup))
                .subnetGroup(subnetGroup)
                .serverlessV2MinCapacity(0.5)
                .serverlessV2MaxCapacity(2.0)
                .writer(ClusterInstance.serverlessV2("writer", ServerlessV2ClusterInstanceProps.builder()
                        .instanceIdentifier("aws-jdbc-driver-stack-" + clusterId + "-writer")
                        .build()))
                .readers(Arrays.<IClusterInstance>asList(
                        ClusterInstance.serverlessV2("reader1", ServerlessV2ClusterInstanceProps.builder()
                                .instanceIdentifier("aws-jdbc-driver-stack-" + clusterId + "-reader-1")
                                .scaleWithWriter(true)
                                .build()),
                        ClusterInstance.serverlessV2("reader2", ServerlessV2ClusterInstanceProps.builder()
                                .instanceIdentifier("aws-jdbc-driver-stack-" + clusterId + "-reader-2")
                                .build())
                ))
                .deletionProtection(false)
                .build();

        // Apply standard tags
        Tags.of(cluster).add("Project", "AWS-JDBC-Driver-Demo");
        Tags.of(cluster).add("Environment", "Demo");
        Tags.of(cluster).add("Purpose", "JDBC-Driver-Testing");
        Tags.of(cluster).add("Owner", "Developer");
        Tags.of(cluster).add("AutoDelete", "true");
        Tags.of(cluster).add("CreatedBy", "cdk-java-stack");

        // Output connection details
        CfnOutput.Builder.create(this, "WriterEndpoint")
                .value(cluster.getClusterEndpoint().getSocketAddress())
                .description("Aurora cluster writer endpoint")
                .build();

        CfnOutput.Builder.create(this, "ReaderEndpoint")
                .value(cluster.getClusterReadEndpoint().getSocketAddress())
                .description("Aurora cluster reader endpoint")
                .build();

        CfnOutput.Builder.create(this, "SecretArn")
                .value(cluster.getSecret() != null ? cluster.getSecret().getSecretArn() : "No secret created")
                .description("ARN of the secret containing database credentials")
                .build();

        CfnOutput.Builder.create(this, "DatabaseName")
                .value(dbName)
                .description("Database name")
                .build();

        CfnOutput.Builder.create(this, "Username")
                .value(dbUsername)
                .description("Database username")
                .build();
    }
}