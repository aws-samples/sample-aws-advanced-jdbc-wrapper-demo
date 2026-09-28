package com.myorg;

import software.amazon.awscdk.App;
import software.amazon.awscdk.Environment;
import software.amazon.awscdk.StackProps;

import java.io.File;
import java.io.FileInputStream;
import java.io.IOException;
import java.util.Properties;

/**
 * CDK app for the AD FS identity provider (Stage 5).
 *
 * Two stacks, deployed in order because the IAM SAML provider needs metadata that
 * only exists after AD FS is configured on the domain controller:
 *
 *   1. adfs-domain-controller   - the Windows AD domain controller (this app)
 *        then run scripts/setup-adfs.ps1 on the DC, which writes FederationMetadata.xml
 *   2. adfs-iam-identity-provider - the IAM SAML provider + role, built from that metadata
 *
 * The IAM stack is only added when the federation metadata file is present, so a first
 * `cdk deploy adfs-domain-controller` works before any metadata exists.
 *
 * Configuration comes from the repo-root .env file or environment variables, so a fresh
 * clone deploys without editing Java. Nothing here hardcodes an account, VPC, or IP.
 */
public class AdfsApp {
    public static void main(final String[] args) {
        App app = new App();
        Properties config = loadEnvConfig();

        String region = getConfigValue(config, "AWS_REGION", System.getenv("CDK_DEFAULT_REGION"));
        Environment env = Environment.builder()
                .account(System.getenv("CDK_DEFAULT_ACCOUNT"))
                .region(region)
                .build();

        // --- Domain controller (AD side), only when its VPC is configured ---
        // The two stacks are independent: synthesizing the app must not require the other
        // stack's inputs. Add the domain controller only when ADFS_VPC_ID (or AWS_VPC_ID)
        // is set, so `cdk deploy adfs-iam-identity-provider` works without DC config.
        String dcVpcId = getConfigValue(config, "ADFS_VPC_ID", getConfigValue(config, "AWS_VPC_ID", null));
        if (dcVpcId != null && !dcVpcId.trim().isEmpty()) {
            new DomainControllerStack(app, "adfs-domain-controller", StackProps.builder()
                    .env(env)
                    .build(), DomainControllerStackConfig.builder()
                    .vpcId(dcVpcId)
                    .subnetId(getConfigValue(config, "ADFS_SUBNET_ID", null))
                    .keyName(getConfigValue(config, "ADFS_KEY_NAME", null))
                    .domainDnsName(getConfigValue(config, "ADFS_DOMAIN_DNS_NAME", "corp.example.com"))
                    .domainNetBiosName(getConfigValue(config, "ADFS_DOMAIN_NETBIOS_NAME", "CORP"))
                    // DSRM password is generated into this Secrets Manager secret by the stack;
                    // nothing is stored in .env.
                    .secretName(getConfigValue(config, "ADFS_DSRM_SECRET_NAME", "adfs/dc/restore-mode-password"))
                    .instanceType(getConfigValue(config, "ADFS_INSTANCE_TYPE", "m5.large"))
                    // Windows Server 2025 - fixed, not configurable.
                    .windowsVersion("2025")
                    .build());
        }

        // --- IAM identity provider (IAM side), only once metadata exists ---
        String metadataPath = getConfigValue(config, "ADFS_FEDERATION_METADATA_PATH", "FederationMetadata.xml");
        File metadataFile = new File(metadataPath);
        if (metadataFile.isFile()) {
            new IamIdentityProviderStack(app, "adfs-iam-identity-provider", StackProps.builder()
                    .env(env)
                    .build(), IamIdentityProviderStackConfig.builder()
                    .providerName(getConfigValue(config, "ADFS_SAML_PROVIDER_NAME", "ADFS"))
                    .roleName(getConfigValue(config, "ADFS_IAM_ROLE_NAME", "ADFS-JDBCDemo"))
                    .metadataFilePath(metadataFile.getAbsolutePath())
                    .clusterResourceId(getConfigValue(config, "AURORA_CLUSTER_RESOURCE_ID", null))
                    .dbIamUsername(getConfigValue(config, "AURORA_IAM_DB_USERNAME", "db_iam_user"))
                    .build());
        } else {
            System.out.println("[info] " + metadataPath + " not found; skipping adfs-iam-identity-provider. "
                    + "Deploy adfs-domain-controller first, run setup-adfs.ps1 on the DC to produce the "
                    + "federation metadata, point ADFS_FEDERATION_METADATA_PATH at it, then deploy again.");
        }

        app.synth();
    }

    private static Properties loadEnvConfig() {
        Properties props = new Properties();
        // This module's own .env, one level up from the cdk dir: identity_providers/adfs/.env
        // (cdk runs from identity_providers/adfs/cdk). Also accept a .env in the cdk dir.
        for (String candidate : new String[] {"../.env", ".env"}) {
            File f = new File(candidate);
            if (f.isFile()) {
                try (FileInputStream fis = new FileInputStream(f)) {
                    props.load(fis);
                    return props;
                } catch (IOException e) {
                    // fall through and try the next candidate
                }
            }
        }
        System.out.println("No .env file found in identity_providers/adfs; using defaults and environment variables");
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
