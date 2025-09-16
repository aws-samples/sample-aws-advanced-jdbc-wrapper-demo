package com.myorg;

public class AuroraStackConfig {
    private final String vpcId;
    private final String clusterId;
    private final String dbUsername;
    private final String dbName;
    private final String existingSecurityGroupId;
    private final String existingSubnetGroupName;

    private AuroraStackConfig(Builder builder) {
        this.vpcId = builder.vpcId;
        this.clusterId = builder.clusterId;
        this.dbUsername = builder.dbUsername;
        this.dbName = builder.dbName;
        this.existingSecurityGroupId = builder.existingSecurityGroupId;
        this.existingSubnetGroupName = builder.existingSubnetGroupName;
    }

    public String getVpcId() { return vpcId; }
    public String getClusterId() { return clusterId; }
    public String getDbUsername() { return dbUsername; }
    public String getDbName() { return dbName; }
    public String getExistingSecurityGroupId() { return existingSecurityGroupId; }
    public String getExistingSubnetGroupName() { return existingSubnetGroupName; }

    public static Builder builder() {
        return new Builder();
    }

    public static class Builder {
        private String vpcId;
        private String clusterId;
        private String dbUsername;
        private String dbName;
        private String existingSecurityGroupId;
        private String existingSubnetGroupName;

        public Builder vpcId(String vpcId) {
            this.vpcId = vpcId;
            return this;
        }

        public Builder clusterId(String clusterId) {
            this.clusterId = clusterId;
            return this;
        }

        public Builder dbUsername(String dbUsername) {
            this.dbUsername = dbUsername;
            return this;
        }

        public Builder dbName(String dbName) {
            this.dbName = dbName;
            return this;
        }

        public Builder existingSecurityGroupId(String existingSecurityGroupId) {
            this.existingSecurityGroupId = existingSecurityGroupId;
            return this;
        }

        public Builder existingSubnetGroupName(String existingSubnetGroupName) {
            this.existingSubnetGroupName = existingSubnetGroupName;
            return this;
        }

        public AuroraStackConfig build() {
            return new AuroraStackConfig(this);
        }
    }
}