#!/bin/bash

# AWS JDBC Wrapper Demo Script
# Usage: ./demo.sh [standard-jdbc|aws-jdbc-wrapper|read-write-splitting]

set -e

DEMO_STEP="${1}"

if [ -z "${DEMO_STEP}" ]; then
    echo "Usage: ./demo.sh [standard-jdbc|aws-jdbc-wrapper|read-write-splitting]"
    echo ""
    echo "Available steps:"
    echo "  standard-jdbc        - Reset to standard PostgreSQL JDBC (baseline)"
    echo "  aws-jdbc-wrapper     - Migrate from standard JDBC to AWS JDBC Wrapper"
    echo "  read-write-splitting - Enable read/write splitting for optimal performance"
    exit 1
fi

case "${DEMO_STEP}" in
    "standard-jdbc")
        echo "=== Baseline: Standard JDBC Configuration ==="
        echo "Resetting to standard PostgreSQL JDBC driver with HikariCP..."
        
        # Copy configuration files
        cp config_templates/standard-jdbc/build.gradle .
        cp config_templates/standard-jdbc/DatabaseConfig.java src/main/java/com/example/config/
        cp config_templates/standard-jdbc/OrderDAO.java src/main/java/com/example/dao/
        
        # Remove aws-wrapper prefix from URL if present
        sed -i 's|^db\.url=jdbc:aws-wrapper:postgresql:|db.url=jdbc:postgresql:|' src/main/resources/application.properties
        
        echo "Configuration reset:"
        echo "   - Standard PostgreSQL JDBC driver"
        echo "   - HikariCP connection pooling"
        echo "   - All operations will use writer endpoint"
        echo ""
        echo "Running application..."
        ./gradlew clean run
        ;;
        
    "aws-jdbc-wrapper")
        echo "Adding AWS JDBC Wrapper with failover capability..."
        
        # Copy configuration files
        cp config_templates/aws-jdbc-wrapper/build.gradle .
        cp config_templates/aws-jdbc-wrapper/DatabaseConfig.java src/main/java/com/example/config/
        
        # Add aws-wrapper prefix to URL if not already present
        sed -i 's|^db\.url=jdbc:postgresql:|db.url=jdbc:aws-wrapper:postgresql:|' src/main/resources/application.properties
        
        echo "Configuration updated:"
        echo "   - AWS JDBC Wrapper added"
        echo "   - Failover plugin enabled"
        echo "   - All operations still use writer endpoint"
        echo "   - Fast failover capability added"
        echo ""
        echo "Running application..."
        ./gradlew clean run
        ;;
        
    "read-write-splitting")
        echo "=== Enable Read/Write Splitting ==="
        echo "Enabling read/write splitting for optimal performance..."
        
        # Copy configuration files
        cp config_templates/read-write-splitting/build.gradle .
        cp config_templates/read-write-splitting/DatabaseConfig.java src/main/java/com/example/config/
        cp config_templates/read-write-splitting/OrderDAO.java src/main/java/com/example/dao/
        
        # Add aws-wrapper prefix to URL if not already present
        sed -i 's|^db\.url=jdbc:postgresql:|db.url=jdbc:aws-wrapper:postgresql:|' src/main/resources/application.properties
        
        echo "Configuration updated:"
        echo "   - Read/Write Splitting plugin enabled"
        echo "   - Read operations will use reader endpoints"
        echo "   - Write operations will use writer endpoint"
        echo "   - setReadOnly(true) added to read methods"
        echo ""
        echo "Running application..."
        ./gradlew clean run
        ;;
        
    *)
        echo "ERROR: Invalid step: ${DEMO_STEP}"
        echo "Valid options: standard-jdbc, aws-jdbc-wrapper, read-write-splitting"
        exit 1
        ;;
esac

echo ""
echo "Demo step '${DEMO_STEP}' completed!"
echo ""
echo "Next steps:"
case "${DEMO_STEP}" in
    "standard-jdbc")
        echo "  Run: ./demo.sh aws-jdbc-wrapper"
        ;;
    "aws-jdbc-wrapper")
        echo "  Run: ./demo.sh read-write-splitting"
        ;;
    "read-write-splitting")
        echo "  Demo complete! Check the logs to see read/write splitting in action."
        echo "  To reset: ./demo.sh standard-jdbc"
        ;;
esac