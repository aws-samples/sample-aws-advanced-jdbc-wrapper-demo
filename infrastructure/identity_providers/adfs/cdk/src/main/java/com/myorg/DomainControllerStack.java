package com.myorg;

import software.amazon.awscdk.CfnOutput;
import software.amazon.awscdk.Fn;
import software.amazon.awscdk.Stack;
import software.amazon.awscdk.StackProps;
import software.amazon.awscdk.Tags;
import software.amazon.awscdk.services.ec2.*;
import software.amazon.awscdk.services.iam.CfnInstanceProfile;
import software.amazon.awscdk.services.iam.ManagedPolicy;
import software.amazon.awscdk.services.iam.Role;
import software.amazon.awscdk.services.iam.ServicePrincipal;
import software.amazon.awscdk.services.secretsmanager.Secret;
import software.amazon.awscdk.services.secretsmanager.SecretStringGenerator;
import software.constructs.Construct;

import java.util.Collections;

/**
 * Active Directory domain controller for the AD FS demo.
 *
 * Builds a single Windows Server instance and promotes it to a domain controller with
 * dcpromo (via user data), plus the security groups Active Directory needs. This is the
 * "AD" side of Stage 5. It does NOT install AD FS - that is done afterwards by running
 * scripts/setup-adfs.ps1 on the instance (there is no AWS API to configure AD FS).
 *
 * ACCESS IS BROWSER-BASED VIA AWS SYSTEMS MANAGER, NOT DIRECT RDP:
 *   - the instance has an SSM instance profile for Fleet Manager Remote Desktop and Run
 *     Command,
 *   - no inbound RDP or public IP is required. The domain controller can live in the same
 *     private subnets as Aurora.
 *
 * The domain controller runs in a PRIVATE subnet, so SSM VPC endpoints are always created
 * to give the agent a path to SSM (Fleet Manager / Run Command) without internet access.
 *
 * Windows Server 2025 is fixed (not configurable). The AD FS flow was originally validated
 * on 2016 and confirmed working on 2025.
 */
public class DomainControllerStack extends Stack {
    public DomainControllerStack(final Construct scope, final String id, final StackProps props,
                                 final DomainControllerStackConfig config) {
        super(scope, id, props);

        requireValue(config.getVpcId(), "ADFS_VPC_ID");
        requireValue(config.getSubnetId(), "ADFS_SUBNET_ID");
        requireValue(config.getKeyName(), "ADFS_KEY_NAME");

        final String domainDns = config.getDomainDnsName();
        final String netbios = config.getDomainNetBiosName();

        // Look up the existing VPC the Aurora demo already uses, so the domain controller
        // can reach the cluster over private IPs.
        IVpc vpc = Vpc.fromLookup(this, "adfs-vpc", VpcLookupOptions.builder()
                .vpcId(config.getVpcId())
                .build());

        // Latest patch of the requested Windows Server release, resolved at deploy time
        // from the SSM public parameter (so we never hardcode an AMI id).
        String ssmParam = "/aws/service/ami-windows-latest/Windows_Server-"
                + config.getWindowsVersion() + "-English-Full-Base";
        IMachineImage windowsImage = MachineImage.fromSsmParameter(ssmParam,
                SsmParameterImageOptions.builder().os(OperatingSystemType.WINDOWS).build());

        // Domain members security group (referenced by the DC SG for intra-domain traffic).
        SecurityGroup memberSg = SecurityGroup.Builder.create(this, "domain-member-sg")
                .vpc(vpc)
                .description("AD FS demo - domain members")
                .allowAllOutbound(true)
                .build();

        // Domain controller security group. No inbound from the internet; access is via SSM.
        SecurityGroup dcSg = SecurityGroup.Builder.create(this, "domain-controller-sg")
                .vpc(vpc)
                .description("AD FS demo - domain controller (SSM access, no RDP)")
                .allowAllOutbound(true)
                .build();

        // Active Directory ports, reachable from domain members within the VPC.
        addAdIngress(dcSg, memberSg, Port.udp(123), "NTP");
        addAdIngress(dcSg, memberSg, Port.tcp(135), "RPC endpoint mapper");
        addAdIngress(dcSg, memberSg, Port.udp(135), "RPC endpoint mapper (udp)");
        addAdIngress(dcSg, memberSg, Port.udp(138), "NetBIOS datagram");
        addAdIngress(dcSg, memberSg, Port.tcpRange(1024, 65535), "RPC dynamic range");
        addAdIngress(dcSg, memberSg, Port.tcp(389), "LDAP");
        addAdIngress(dcSg, memberSg, Port.udp(389), "LDAP (udp)");
        addAdIngress(dcSg, memberSg, Port.tcp(636), "LDAPS");
        addAdIngress(dcSg, memberSg, Port.tcp(3268), "Global catalog");
        addAdIngress(dcSg, memberSg, Port.tcp(3269), "Global catalog SSL");
        addAdIngress(dcSg, memberSg, Port.tcp(53), "DNS");
        addAdIngress(dcSg, memberSg, Port.udp(53), "DNS (udp)");
        addAdIngress(dcSg, memberSg, Port.tcp(88), "Kerberos");
        addAdIngress(dcSg, memberSg, Port.udp(88), "Kerberos (udp)");
        addAdIngress(dcSg, memberSg, Port.tcp(445), "SMB");
        addAdIngress(dcSg, memberSg, Port.udp(445), "SMB (udp)");
        dcSg.addIngressRule(memberSg, Port.allIcmp(), "ICMP from domain members");
        // AD FS HTTPS: the federatedAuth plugin (running on the demo app host anywhere in the
        // VPC) posts credentials to the AD FS forms endpoint on 443. Allow it from the whole
        // VPC CIDR, not just the domain-member SG, so the app host can reach it without being
        // joined to the domain or added to that SG.
        dcSg.addIngressRule(Peer.ipv4(vpc.getVpcCidrBlock()), Port.tcp(443), "AD FS HTTPS from within the VPC");

        // Directory Services Restore Mode password: generated by Secrets Manager, never
        // stored in .env, git, or the CDK source.
        Secret dsrmSecret = Secret.Builder.create(this, "dsrm-password")
                .secretName(config.getSecretName())
                .description("AD FS demo - Directory Services Restore Mode password for the domain controller")
                .generateSecretString(SecretStringGenerator.builder()
                        // dcpromo needs complexity; exclude characters that break the PowerShell fetch.
                        .passwordLength(24)
                        .excludePunctuation(true)
                        .excludeCharacters("\"'$`\\")
                        .build())
                .build();

        // Instance role for SSM: this enables Fleet Manager Remote Desktop and Run Command
        // without opening inbound RDP.
        Role instanceRole = Role.Builder.create(this, "domain-controller-role")
                .assumedBy(new ServicePrincipal("ec2.amazonaws.com"))
                .managedPolicies(Collections.singletonList(
                        ManagedPolicy.fromAwsManagedPolicyName("AmazonSSMManagedInstanceCore")))
                .description("Allows browser-based SSM access to the AD FS domain controller")
                .build();
        CfnInstanceProfile instanceProfile = CfnInstanceProfile.Builder.create(this, "domain-controller-instance-profile")
                .roles(Collections.singletonList(instanceRole.getRoleName()))
                .build();

        // Let the instance read the DSRM password from Secrets Manager at boot.
        dsrmSecret.grantRead(instanceRole);

        // The domain controller runs in a PRIVATE subnet (no internet route), so the SSM
        // agent cannot reach the public SSM endpoints. These interface endpoints give it a
        // private path to SSM - without them there is no Fleet Manager / Run Command access
        // and the instance is unreachable. They are always created for that reason.
        SecurityGroup endpointSg = SecurityGroup.Builder.create(this, "ssm-endpoint-sg")
                .vpc(vpc)
                .description("AD FS demo - SSM interface endpoints")
                .allowAllOutbound(true)
                .build();
        endpointSg.addIngressRule(dcSg, Port.tcp(443), "HTTPS from the domain controller");

        SubnetSelection endpointSubnets = SubnetSelection.builder()
                .subnets(Collections.singletonList(
                        Subnet.fromSubnetId(this, "adfs-endpoint-subnet", config.getSubnetId())))
                .build();

        java.util.Map<String, InterfaceVpcEndpointAwsService> ssmServices = new java.util.LinkedHashMap<>();
        ssmServices.put("ssm", InterfaceVpcEndpointAwsService.SSM);
        ssmServices.put("ssmmessages", InterfaceVpcEndpointAwsService.SSM_MESSAGES);
        ssmServices.put("ec2messages", InterfaceVpcEndpointAwsService.EC2_MESSAGES);

        for (java.util.Map.Entry<String, InterfaceVpcEndpointAwsService> e : ssmServices.entrySet()) {
            InterfaceVpcEndpoint.Builder.create(this, "ssm-endpoint-" + e.getKey())
                    .vpc(vpc)
                    .service(e.getValue())
                    .subnets(endpointSubnets)
                    .securityGroups(Collections.singletonList(endpointSg))
                    .privateDnsEnabled(true)
                    .build();
        }

        // dcpromo runs unattended on first boot. The password is read from Secrets Manager on
        // the instance (via the instance role), so no plaintext password is in user-data.
        String userData = "<powershell>\n"
                + "Install-WindowsFeature AD-Domain-Services -IncludeManagementTools\n"
                + "Import-Module ADDSDeployment\n"
                + "$secretJson = (Get-SECSecretValue -SecretId '" + dsrmSecret.getSecretName()
                + "' -Region '" + this.getRegion() + "').SecretString\n"
                + "$plain = ($secretJson | ConvertFrom-Json).password\n"
                + "if (-not $plain) { $plain = $secretJson }\n"
                + "$secure = ConvertTo-SecureString $plain -AsPlainText -Force\n"
                + "Install-ADDSForest "
                + "-DomainName '" + domainDns + "' "
                + "-DomainNetbiosName '" + netbios + "' "
                + "-ForestMode 'WinThreshold' -DomainMode 'WinThreshold' "
                + "-InstallDns "
                + "-SafeModeAdministratorPassword $secure "
                + "-Force\n"
                + "</powershell>";

        CfnInstance instance = CfnInstance.Builder.create(this, "domain-controller")
                .imageId(windowsImage.getImage(this).getImageId())
                .instanceType(config.getInstanceType())
                .keyName(config.getKeyName())
                .subnetId(config.getSubnetId())
                .iamInstanceProfile(instanceProfile.getRef())
                .securityGroupIds(Collections.singletonList(dcSg.getSecurityGroupId()))
                .userData(Fn.base64(userData))
                .build();

        Tags.of(this).add("Project", "AWS-JDBC-Driver-Demo");
        Tags.of(this).add("Purpose", "ADFS-Federated-Auth");
        Tags.of(this).add("AutoDelete", "true");

        CfnOutput.Builder.create(this, "DomainControllerInstanceId")
                .value(instance.getRef())
                .description("Instance ID. Access the domain controller through Systems Manager "
                        + "Fleet Manager Remote Desktop or Run Command.")
                .build();
        CfnOutput.Builder.create(this, "DomainControllerPrivateIp")
                .value(instance.getAttrPrivateIp())
                .description("Private IP of the domain controller (also the DNS server). "
                        + "Use it when configuring DNS access from the Java application host.")
                .build();
        CfnOutput.Builder.create(this, "DomainAdmin")
                .value(netbios + "\\Administrator")
                .description("Domain administrator account")
                .build();
        CfnOutput.Builder.create(this, "DsrmSecretName")
                .value(dsrmSecret.getSecretName())
                .description("Secrets Manager secret holding the generated DSRM password")
                .build();
    }

    private static void addAdIngress(SecurityGroup dcSg, SecurityGroup memberSg, Port port, String description) {
        dcSg.addIngressRule(memberSg, port, description);
    }

    private static void requireValue(String value, String envKey) {
        if (value == null || value.trim().isEmpty()) {
            throw new IllegalArgumentException(
                    envKey + " is required for the AD FS domain controller. Set it in .env or the environment.");
        }
    }
}
