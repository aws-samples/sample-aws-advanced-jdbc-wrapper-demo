package com.example.config;

import com.zaxxer.hikari.HikariConfig;
import com.zaxxer.hikari.HikariDataSource;
import lombok.extern.slf4j.Slf4j;

import java.io.IOException;
import java.io.InputStream;
import java.util.Properties;

@Slf4j
public class DatabaseConfig {
    private static final HikariDataSource dataSource;
    private static String configuredJdbcUrl;

    static {
        try {
            Properties props = loadConfig();
            HikariConfig config = new HikariConfig();

            // AWS JDBC Wrapper with Read/Write Splitting and federated authentication
            config.setDataSourceClassName("software.amazon.jdbc.ds.AwsWrapperDataSource");
            configuredJdbcUrl = props.getProperty("db.url");
            config.addDataSourceProperty("jdbcUrl", configuredJdbcUrl);
            config.addDataSourceProperty("targetDataSourceClassName", "org.postgresql.ds.PGSimpleDataSource");

            String iamUsername = props.getProperty("db.iam.username");
            if (iamUsername == null || iamUsername.trim().isEmpty()) {
                throw new RuntimeException("db.iam.username is required but not set");
            }

            Properties targetProps = new Properties();
            targetProps.setProperty("sslmode", "require");
            targetProps.setProperty("wrapperPlugins", "readWriteSplitting,failover,federatedAuth");

            // Identity provider (AD FS)
            targetProps.setProperty("idpName", "adfs");
            targetProps.setProperty("idpEndpoint", props.getProperty("idp.endpoint"));
            targetProps.setProperty("idpPort", "443");
            targetProps.setProperty("idpUsername", props.getProperty("idp.username"));

            // Get AD FS password from environment variable only
            String idpPassword = System.getenv("IDP_PASSWORD");
            if (idpPassword == null || idpPassword.trim().isEmpty()) {
                throw new RuntimeException("IDP_PASSWORD environment variable is required but not set");
            }
            targetProps.setProperty("idpPassword", idpPassword);

            targetProps.setProperty("rpIdentifier", "urn:amazon:webservices");
            targetProps.setProperty("sslInsecure", props.getProperty("sslInsecure", "false"));

            // AWS
            targetProps.setProperty("iamRoleArn", props.getProperty("iam.role.arn"));
            targetProps.setProperty("iamIdpArn", props.getProperty("iam.idp.arn"));
            targetProps.setProperty("iamRegion", props.getProperty("iam.region"));
            targetProps.setProperty("dbUser", iamUsername);

            config.addDataSourceProperty("targetDataSourceProperties", targetProps);

            config.setMaximumPoolSize(5);
            config.setMinimumIdle(2);
            config.setIdleTimeout(300000);
            config.setConnectionTimeout(20000);
            config.setPoolName("AWSJDBCFederatedAuthPool");

            dataSource = new HikariDataSource(config);

            log.info("AWS JDBC Wrapper with Federated Authentication initialized");
        } catch (IOException e) {
            log.error("Failed to initialize database connection pool", e);
            throw new RuntimeException(e);
        }
    }

    private static Properties loadConfig() throws IOException {
        Properties props = new Properties();
        try (InputStream input = DatabaseConfig.class
                .getClassLoader()
                .getResourceAsStream("application.properties")) {
            if (input == null) {
                throw new IOException("Unable to find application.properties");
            }
            props.load(input);
        }
        return props;
    }

    public static HikariDataSource getDataSource() {
        return dataSource;
    }

    public static void closePool() {
        if (dataSource != null) {
            dataSource.close();
            log.info("Database connection pool closed");
        }
    }

    public static String getConfiguredUrl() {
        return configuredJdbcUrl != null ? configuredJdbcUrl : "URL not initialized";
    }
}
