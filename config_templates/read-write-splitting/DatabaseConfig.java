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
            
            // AWS JDBC Wrapper with Read/Write Splitting
            config.setDataSourceClassName("software.amazon.jdbc.ds.AwsWrapperDataSource");
            configuredJdbcUrl = props.getProperty("db.url");
            config.addDataSourceProperty("jdbcUrl", configuredJdbcUrl);
            config.addDataSourceProperty("targetDataSourceClassName", "org.postgresql.ds.PGSimpleDataSource");
            
            Properties targetProps = new Properties();
            targetProps.setProperty("user", props.getProperty("db.username"));
            targetProps.setProperty("password", props.getProperty("db.password"));
            targetProps.setProperty("wrapperPlugins", "readWriteSplitting,failover");
            
            config.addDataSourceProperty("targetDataSourceProperties", targetProps);
            
            config.setMaximumPoolSize(5);
            config.setMinimumIdle(2);
            config.setIdleTimeout(300000);
            config.setConnectionTimeout(20000);
            config.setPoolName("AWSJDBCReadWritePool");
            
            dataSource = new HikariDataSource(config);
            
            log.info("AWS JDBC Wrapper with Read/Write Splitting initialized");
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