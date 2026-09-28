package com.myorg;

import software.amazon.awscdk.CfnOutput;
import software.amazon.awscdk.Stack;
import software.amazon.awscdk.StackProps;
import software.amazon.awscdk.Tags;
import software.amazon.awscdk.services.iam.CfnSAMLProvider;
import software.amazon.awscdk.services.iam.PolicyStatement;
import software.amazon.awscdk.services.iam.Role;
import software.amazon.awscdk.services.iam.SamlPrincipal;
import software.amazon.awscdk.services.iam.ISamlProvider;
import software.constructs.Construct;

import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Paths;
import java.util.Collections;

/**
 * The IAM side of AD FS federation:
 *   - an IAM SAML identity provider built from the AD FS federation metadata, and
 *   - the role the federated user assumes, allowed only to connect to Aurora via an
 *     IAM database token (rds-db:connect).
 *
 * Deploy this AFTER the domain controller exists and setup-adfs.ps1 has produced
 * FederationMetadata.xml (point ADFS_FEDERATION_METADATA_PATH at it).
 */
public class IamIdentityProviderStack extends Stack {
    public IamIdentityProviderStack(final Construct scope, final String id, final StackProps props,
                                    final IamIdentityProviderStackConfig config) {
        super(scope, id, props);

        if (config.getClusterResourceId() == null || config.getClusterResourceId().trim().isEmpty()) {
            throw new IllegalArgumentException(
                    "AURORA_CLUSTER_RESOURCE_ID is required so the rds-db:connect policy can be scoped to the cluster. "
                    + "Get it from the Aurora stack output ClusterResourceId.");
        }

        String metadataXml = readMetadata(config.getMetadataFilePath());

        // IAM SAML identity provider (IAM -> Identity providers), fed by the AD FS metadata.
        CfnSAMLProvider samlProvider = CfnSAMLProvider.Builder.create(this, "adfs-saml-provider")
                .name(config.getProviderName())
                .samlMetadataDocument(metadataXml)
                .build();

        ISamlProvider providerRef = software.amazon.awscdk.services.iam.SamlProvider.fromSamlProviderArn(
                this, "adfs-saml-provider-ref", samlProvider.getAttrArn());

        // Trust: allow AssumeRoleWithSAML from this provider, audience-scoped to AWS sign-in.
        SamlPrincipal principal = new SamlPrincipal(providerRef, Collections.singletonMap(
                "StringEquals",
                Collections.singletonMap("SAML:aud", "https://signin.aws.amazon.com/saml")));

        Role role = Role.Builder.create(this, "adfs-federated-role")
                .roleName(config.getRoleName())
                .assumedBy(principal)
                .description("Assumed via AD FS SAML federation; may connect to Aurora with an IAM token")
                .build();

        // Permission: only rds-db:connect, scoped to the specific cluster + database user.
        String dbUserArn = "arn:aws:rds-db:" + this.getRegion() + ":" + this.getAccount()
                + ":dbuser:" + config.getClusterResourceId() + "/" + config.getDbIamUsername();
        role.addToPolicy(PolicyStatement.Builder.create()
                .actions(Collections.singletonList("rds-db:connect"))
                .resources(Collections.singletonList(dbUserArn))
                .build());

        Tags.of(this).add("Project", "AWS-JDBC-Driver-Demo");
        Tags.of(this).add("Purpose", "ADFS-Federated-Auth");
        Tags.of(this).add("AutoDelete", "true");

        CfnOutput.Builder.create(this, "SamlProviderArn")
                .value(samlProvider.getAttrArn())
                .description("IAM SAML identity provider ARN (use as iam.idp.arn in the JDBC stage)")
                .build();
        CfnOutput.Builder.create(this, "FederatedRoleArn")
                .value(role.getRoleArn())
                .description("IAM role ARN (use as iam.role.arn in the JDBC stage)")
                .build();
    }

    private static String readMetadata(String path) {
        try {
            return new String(Files.readAllBytes(Paths.get(path)), StandardCharsets.UTF_8);
        } catch (IOException e) {
            throw new RuntimeException("Could not read AD FS federation metadata at " + path
                    + ". Deploy the domain controller, run setup-adfs.ps1, and point "
                    + "ADFS_FEDERATION_METADATA_PATH at the generated FederationMetadata.xml.", e);
        }
    }
}
