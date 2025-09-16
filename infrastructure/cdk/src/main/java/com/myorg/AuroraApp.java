package com.myorg;

import software.amazon.awscdk.App;
import software.amazon.awscdk.Environment;
import software.amazon.awscdk.StackProps;

import java.io.FileInputStream;
import java.io.IOException;
import java.util.Properties;

public class AuroraApp {
    public static void main(final String[] args) {
        App app = new App();

        // Load configuration from .env file
        Properties config = loadEnvConfig();
        
        // Get configuration values with defaults
        String vpcId = getConfigValue(config, "AWS_VPC_ID", null);
        String clusterId = getConfigValue(config, "AURORA_CLUSTER_ID", null);
        String dbUsername = getConfigValue(config, "AURORA_DB_USERNAME", null);
        String dbName = getConfigValue(config, "AURORA_DB_NAME", null);
        String region = getConfigValue(config, "AWS_REGION", System.getenv("CDK_DEFAULT_REGION"));     
        String existingSecurityGroupId = getConfigValue(config, "AWS_SECURITY_GROUP_ID", null);
        String existingSubnetGroupName = getConfigValue(config, "AWS_DB_SUBNET_GROUP_NAME", null);

        // Environment configuration
        Environment env = Environment.builder()
                .account(System.getenv("CDK_DEFAULT_ACCOUNT"))
                .region(region)
                .build();

        new AuroraStack(app, "aws-jdbc-driver-stack", StackProps.builder()
                .env(env)
                .build(), AuroraStackConfig.builder()
                .vpcId(vpcId)
                .clusterId(clusterId)
                .dbUsername(dbUsername)
                .dbName(dbName)
                .existingSecurityGroupId(existingSecurityGroupId)
                .existingSubnetGroupName(existingSubnetGroupName)
                .build());

        app.synth();
    }

    private static Properties loadEnvConfig() {
        Properties props = new Properties();
        try {
            // Try to load from .env file in project root
            FileInputStream fis = new FileInputStream("../../.env");
            props.load(fis);
            fis.close();
        } catch (IOException e) {
            System.out.println("No .env file found, using defaults and environment variables");
        }
        return props;
    }

    private static String getConfigValue(Properties props, String key, String defaultValue) {
        // Priority: .env file > environment variable > default value
        String value = props.getProperty(key);
        if (value == null || value.trim().isEmpty()) {
            value = System.getenv(key);
        }
        if (value == null || value.trim().isEmpty()) {
            value = defaultValue;
        }
        return value;
    }
}