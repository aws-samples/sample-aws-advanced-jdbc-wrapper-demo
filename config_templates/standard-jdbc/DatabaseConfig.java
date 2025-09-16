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
            
            // Standard JDBC configuration
            configuredJdbcUrl = props.getProperty("db.url");
            config.setJdbcUrl(configuredJdbcUrl);
            config.setUsername(props.getProperty("db.username"));
            
            // Get password from environment variable only
            String password = System.getenv("DB_PASSWORD");
            if (password == null || password.trim().isEmpty()) {
                throw new RuntimeException("DB_PASSWORD environment variable is required but not set");
            }
            config.setPassword(password);
            
            config.setMaximumPoolSize(5);
            config.setMinimumIdle(2);
            config.setIdleTimeout(300000);
            config.setConnectionTimeout(20000);
            config.setPoolName("StandardPostgresPool");
            
            dataSource = new HikariDataSource(config);
            
            log.info("Standard JDBC connection pool initialized");
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