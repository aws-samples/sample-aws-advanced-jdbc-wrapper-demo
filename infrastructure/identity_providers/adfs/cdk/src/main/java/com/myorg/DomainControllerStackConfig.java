package com.myorg;

/**
 * Configuration for the Active Directory domain controller stack.
 *
 * Values come from the repo-root .env file or environment variables (see AdfsApp),
 * so a fresh clone deploys without editing Java.
 */
public class DomainControllerStackConfig {
    private final String vpcId;
    private final String subnetId;
    private final String keyName;
    private final String domainDnsName;
    private final String domainNetBiosName;
    private final String secretName;
    private final String instanceType;
    private final String windowsVersion;

    private DomainControllerStackConfig(Builder b) {
        this.vpcId = b.vpcId;
        this.subnetId = b.subnetId;
        this.keyName = b.keyName;
        this.domainDnsName = b.domainDnsName;
        this.domainNetBiosName = b.domainNetBiosName;
        this.secretName = b.secretName;
        this.instanceType = b.instanceType;
        this.windowsVersion = b.windowsVersion;
    }

    public String getVpcId() { return vpcId; }
    public String getSubnetId() { return subnetId; }
    public String getKeyName() { return keyName; }
    public String getDomainDnsName() { return domainDnsName; }
    public String getDomainNetBiosName() { return domainNetBiosName; }
    public String getSecretName() { return secretName; }
    public String getInstanceType() { return instanceType; }
    public String getWindowsVersion() { return windowsVersion; }


    public static Builder builder() { return new Builder(); }

    public static class Builder {
        private String vpcId;
        private String subnetId;
        private String keyName;
        private String domainDnsName;
        private String domainNetBiosName;
        private String secretName;
        private String instanceType;
        private String windowsVersion;

        public Builder vpcId(String v) { this.vpcId = v; return this; }
        public Builder subnetId(String v) { this.subnetId = v; return this; }
        public Builder keyName(String v) { this.keyName = v; return this; }
        public Builder domainDnsName(String v) { this.domainDnsName = v; return this; }
        public Builder domainNetBiosName(String v) { this.domainNetBiosName = v; return this; }
        public Builder secretName(String v) { this.secretName = v; return this; }
        public Builder instanceType(String v) { this.instanceType = v; return this; }
        public Builder windowsVersion(String v) { this.windowsVersion = v; return this; }

        public DomainControllerStackConfig build() { return new DomainControllerStackConfig(this); }
    }
}
