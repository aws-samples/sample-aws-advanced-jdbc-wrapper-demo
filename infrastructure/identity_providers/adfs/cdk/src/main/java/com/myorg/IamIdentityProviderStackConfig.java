package com.myorg;

/**
 * Configuration for the IAM identity provider stack: the IAM SAML provider that trusts
 * AD FS, and the role the federated user assumes to connect to Aurora with IAM auth.
 */
public class IamIdentityProviderStackConfig {
    private final String providerName;
    private final String roleName;
    private final String metadataFilePath;
    private final String clusterResourceId;
    private final String dbIamUsername;

    private IamIdentityProviderStackConfig(Builder b) {
        this.providerName = b.providerName;
        this.roleName = b.roleName;
        this.metadataFilePath = b.metadataFilePath;
        this.clusterResourceId = b.clusterResourceId;
        this.dbIamUsername = b.dbIamUsername;
    }

    public String getProviderName() { return providerName; }
    public String getRoleName() { return roleName; }
    public String getMetadataFilePath() { return metadataFilePath; }
    public String getClusterResourceId() { return clusterResourceId; }
    public String getDbIamUsername() { return dbIamUsername; }

    public static Builder builder() { return new Builder(); }

    public static class Builder {
        private String providerName;
        private String roleName;
        private String metadataFilePath;
        private String clusterResourceId;
        private String dbIamUsername;

        public Builder providerName(String v) { this.providerName = v; return this; }
        public Builder roleName(String v) { this.roleName = v; return this; }
        public Builder metadataFilePath(String v) { this.metadataFilePath = v; return this; }
        public Builder clusterResourceId(String v) { this.clusterResourceId = v; return this; }
        public Builder dbIamUsername(String v) { this.dbIamUsername = v; return this; }

        public IamIdentityProviderStackConfig build() { return new IamIdentityProviderStackConfig(this); }
    }
}
