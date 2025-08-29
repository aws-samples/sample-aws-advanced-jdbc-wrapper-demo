
## 🚀 AWS JDBC Drive Demo Application

## 🎯 Purpose

**The purpose of this repository is to help developers learn how to leverage the powerful features of [AWS JDBC Driver](https://github.com/aws/aws-advanced-jdbc-wrapper) in their existing enterprise Java applications.**

We aim to provide step-by-step instructions through our real-world order management system demo, where developers will learn how to:

- **Configure Gradle project** to use AWS JDBC Driver
- **Implement fast failover** for improved Aurora reliability
- **Enable read/write splitting** for optimal performance
- **Integrate with AWS services** like IAM authentication and Secrets Manager _(Coming in future releases)_
- **Integrate with ADFS and Okta** for federated authentication _(Coming in future releases)_

This repository contains sample code that simulates a real-world order management system powering an online store using Amazon Aurora databases.

## ⚡ The Challenge

Modern Java applications using Amazon Aurora often struggle to fully take advantage of its cloud-based capabilities. Although Aurora offers powerful features like fast failover, AWS Identity and Access Management (IAM) authentication support, and AWS Secrets Manager integration, standard JDBC drivers weren't designed for the cloud.

When Aurora fails over in seconds, standard JDBC drivers can take up to a minute to reconnect due to DNS propagation delays. Implementing IAM authentication or Secrets Manager requires complex custom code and error handling that most developers shouldn't need to write.

The AWS JDBC Driver makes it effortless for developers to unlock the full potential of Aurora with minimal changes.

## 🔧 Solution overview

The AWS JDBC Driver is an intelligent wrapper that enhances your existing JDBC driver with Aurora and AWS Cloud-based capabilities. It can transform your standard PostgreSQL, MySQL, or MariaDB driver into a cloud-aware, production-ready solution.

**💡 Developers adopt the AWS JDBC Driver for several compelling capabilities:**

• **Fast failover (beyond DNS limitations)** – The AWS JDBC Driver maintains a real-time cache of your Aurora cluster topology and each database instance's role (primary or replica) through direct queries to Aurora. This bypasses DNS delays entirely, enabling immediate connections to the new primary instance during failover.

• **Seamless AWS authentication** – Aurora supports IAM database authentication, but implementing it traditionally requires custom code to generate tokens, handle expiration, and manage renewals. The AWS JDBC Driver minimizes this complexity by automatically handling the entire IAM authentication lifecycle.

• **Built-in Secrets Manager support** – The Secrets Manager integration retrieves database credentials automatically. Your application doesn't need to know the actual password

• **Read/write splitting using connection control** – You can maximize Aurora performance by automatically routing write operations to the primary instance and distributing reads across Aurora replicas through a simple configuration setting. We explore this feature in detail later in this post.

• **Federated authentication** – Enable database access using organizational credentials through Microsoft ADFS or Okta.


**📈 In the following sections, we walk through a real-world transformation using the AWS JDBC Driver. You'll see how an existing Java application evolves through three progressive stages:**

• **Stage 1: Standard JDBC (Baseline)** – The application connects directly to the Aurora writer endpoint through standard JDBC driver, with all operations using a single database instance and relying on DNS-based failover.

• **Stage 2: AWS JDBC with failover** – The application uses AWS JDBC Driver to maintain awareness of the Aurora cluster topology, enabling fast failover through direct instance discovery while still routing all operations through the writer endpoint.

• **Stage 3: Read/Write splitting** – The application uses AWS JDBC Driver read/write splitting feature to send write operations to the Aurora writer instance and distribute read operations across Aurora reader instances, optimizing performance through automatic load balancing.

![Figure 1: Architecture diagram showing Stage 3 configuration with read/write splitting enabled](images/stage3.png)

## 🚀 Getting Started

### 📋 Prerequisites

You must have the following prerequisites:

- **AWS account** with permissions to create Aurora clusters
  - For required permissions, see the IAM policy in [iam-policy.json](iam-policy.json)
- **AWS CLI version 2** (or you can create databases using the AWS Management Console)
- **Java Development Kit (JDK) 8 or later**
- **Gradle 8.14 or later**
- **VPC, DB subnet group, and security group** with port 5432 (PostgreSQL) open ([see detailed setup guide](SETUP_AURORA_REFERENCE.md))

For the complete list of IAM permissions needed, review the IAM policy file in the repository.

### 🎯 Application Overview

**What You're Working With:**
A Java order management system using HikariCP connection pooling and standard PostgreSQL JDBC driver - a typical setup most developers recognize.

**Business Scenario:**
Our demo application simulates a real-world order management system powering an online store where customers place orders, staff update order statuses, and managers generate sales reports. This scenario demonstrates the challenge of mixed database workloads - some operations need immediate consistency (like processing payments), while others can tolerate slight delays (like generating sales reports).

### 📁 Repository Structure

```
aws-jdbc-wrapper-demo/
├── src/main/java/com/example/
│   ├── Application.java           # Main application entry point
│   ├── model/
│   │   └── Order.java            # Order entity with customer/product details
│   ├── dao/
│   │   └── OrderDAO.java         # Data access layer (create, update, query operations)
│   └── config/
│       └── DatabaseConfig.java   # HikariCP + JDBC configuration
├── src/main/resources/
│   └── application.properties    # Database connection settings
├── config_templates/             # Configuration templates for each demo step
│   ├── standard-jdbc/           # Current state (standard PostgreSQL JDBC)
│   ├── aws-jdbc-wrapper/        # Step 2: AWS JDBC wrapper migration
│   └── read-write-splitting/    # Step 3: Read/write splitting enabled
├── build.gradle                 # Gradle dependencies and build configuration
├── setup-aurora.sh             # Creates Aurora cluster + auto-configures endpoints
├── demo.sh                     # Switches between demo configurations
└── cleanup-aurora.sh           # Removes Aurora cluster when done
```

### ⚡ Quick Start

**📚 For detailed setup instructions and AWS resource configuration, see the [Step-by-Step Implementation](#-step-by-step-implementation) section below.**

#### 1. Clone the repository
```bash
git clone https://github.com/aws-samples/sample-aws-advanced-jdbc-wrapper-demo.git
cd sample-aws-advanced-jdbc-wrapper-demo
```

#### 2. Create .env file that will be used to provision Aurora cluster

```bash
cp .env.example .env
```

#### 3. Edit .env with your AWS resource values

For detailed AWS infrastructure setup instructions, see our [Aurora Setup Reference Guide](SETUP_AURORA_REFERENCE.md).

#### 4. Create Aurora cluster

Required AWS resources must be configured in .env file. This script does NOT create VPCs, security groups, or DB subnet groups - it only validates that they exist and are properly configured.

```bash
./setup-aurora.sh
```

#### 5. Create application properties file in src/main/resources directory

```bash
cp src/main/resources/application.properties.example src/main/resources/application.properties
```

Edit application.properties with your Aurora connection details.

#### 6. Edit src/main/resources/application.properties with URI and database username

These values will be displayed when your Aurora cluster is successfully completed (step 4).

#### 7. Set up environment variable

```bash
export DB_PASSWORD=<your_database_password>
```

#### 8. Run command to configure standard JDBC and run the application

As described in [Stage 1: Standard JDBC (Baseline)](#solution-overview), this configures the application with standard JDBC driver.

```bash
./demo.sh standard-jdbc
```

#### 9. Run command to configure AWS JDBC wrapper with failover

As described in [Stage 2: AWS JDBC with failover](#solution-overview), this adds fast failover capabilities.

```bash
./demo.sh aws-jdbc-wrapper
```

#### 10. Run command to enable read/write splitting

As described in [Stage 3: Read/Write splitting](#solution-overview), this enables intelligent connection routing.

```bash
./demo.sh read-write-splitting
```

#### 11. Clean up
```bash
./cleanup-aurora.sh
```

## 📚 Step-by-Step Implementation

### 🛠️ Step 1: Set Up the Development Environment

#### 1.1: Clone the demo repository

```bash
git clone https://github.com/ramesheega/aws-jdbc-warpper-demo.git
cd aws-jdbc-wrapper-demo
```

### 🏗️ Step 2: Deploy the Database Infrastructure

#### 2.1: Configure Your AWS Environment Settings

We'll create an Amazon Aurora cluster using an automated script. The script requires configuration through environment variables in a `.env` file. Please ensure you set all the required variables with your actual AWS resource values to successfully create the Amazon Aurora cluster.

**📚 For detailed AWS infrastructure setup instructions, see our [Aurora Setup Reference Guide](SETUP_AURORA_REFERENCE.md)**

**Create `.env` file with your configuration:**

```bash
cp .env.example .env
# Edit .env with your AWS resource values
```

**Required environment variables:**

```bash
# Aurora Cluster Configuration
AURORA_CLUSTER_ID=aurora-jdbc-demo          # Unique identifier for your Aurora cluster
AURORA_DB_USERNAME=postgres                 # Master username for database authentication
AURORA_DB_NAME=postgres                     # Default database name to create

# AWS Infrastructure Configuration
AWS_REGION=us-east-1                        # AWS region where cluster will be deployed
AWS_VPC_ID=vpc-xxxx                         # VPC ID where Aurora cluster will be created
AWS_SECURITY_GROUP_ID=sg-xxxx               # Security group allowing inbound port 5432 (PostgreSQL)
AWS_DB_SUBNET_GROUP_NAME=jdbc-private-subnets  # DB subnet group with subnets in multiple AZs

# Note: Database password will be prompted securely during setup for security reasons
```

#### 2.2: Create Your Aurora Cluster with two read replicas

Run the script to create Aurora cluster. This will create two reader instances along the writer instance.

```bash
# Setup Aurora cluster with your configuration
./setup-aurora.sh
```

**Expected output after successful creation:**

```
📋 Connection Details:
==================================================
Writer Endpoint: aurora-jdbc-demo.cluster-xxxx.us-east-1.rds.amazonaws.com
Reader Endpoint: aurora-jdbc-demo.cluster-ro-xxxx.us-east-1.rds.amazonaws.com
Username: postgres
Database: postgres
Port: 5432
Region: us-east-1

📝 Update your application.properties with:
==================================================
db.url=jdbc:postgresql://aurora-jdbc-demo.cluster-abc123.us-east-1.rds.amazonaws.com:5432/postgres
db.username=postgres

📝 Set up database password via environment variable:
==================================================
export DB_PASSWORD=<your_actual_aurora_password>
```

### 📊 Step 3: Establish Baseline

Now let's run our application using the standard PostgreSQL JDBC driver to establish our baseline before we enhance it with AWS JDBC wrapper capabilities.

#### 3.1: Configure Application to use the database created

**If you used the automated script**, use the connection details displayed after cluster creation. **If you created the cluster manually through the AWS Console**, gather your Aurora cluster endpoints from the RDS console. Then update the application configuration file with these details:

Create the application configuration file to connect to your newly created Aurora cluster:

**Create `src/main/resources/application.properties`:**

```bash
cp src/main/resources/application.properties.example src/main/resources/application.properties
```

Edit `src/main/resources/application.properties` with your Aurora connection details.

```properties
# Example configuration - replace with your actual Aurora endpoints
db.url=jdbc:postgresql://aurora-jdbc-demo.cluster-abc123.us-east-1.rds.amazonaws.com:5432/postgres
db.username=postgres
```

**Set up the database password via environment variable:**

```bash
export DB_PASSWORD=<your_actual_aurora_password>
```

**Note:** This application uses environment variables for secure password handling instead of storing passwords in configuration files. Standard JDBC drivers require both username and password credentials to connect to the database. We start with the standard JDBC driver as our baseline and then transform the application to use the AWS JDBC Driver.

In an upcoming blog post, we'll demonstrate how to remove the password requirement entirely by leveraging:

- **IAM Database Authentication** for secure, token-based access
- **AWS Secrets Manager** for automatic credential management
- **Federated Authentication** for enterprise identity integration

These AWS authentication methods eliminate the need for hardcoded passwords in your application configuration.

#### 3.2: Run the Application

Execute the application to observe standard JDBC behavior:

**Make sure the environment variable is set and run the application:**

```bash
# Run the application
./gradlew clean run
```

**Expected Output:**

```
Task :run
INFO com.zaxxer.hikari.HikariDataSource - StandardPostgresPool - Starting...
INFO com.example.config.DatabaseConfig - Standard JDBC connection pool initialized

=== PERFORMING WRITE OPERATIONS ===
INFO com.example.dao.OrderDAO - WRITE OPERATION: Creating new order for customer: John Doe
INFO com.example.dao.OrderDAO - Connection URL:
    → WRITER: jdbc:postgresql://aurora-jdbc-demo.cluster-xxxxxxx.us-east-1.rds.amazonaws.com:5432/postgres
INFO com.example.dao.OrderDAO - Order created with ID: 1

=== PERFORMING READ OPERATIONS ===
INFO com.example.dao.OrderDAO - READ OPERATION: Getting order history
INFO com.example.dao.OrderDAO - Connection URL:
    → WRITER: jdbc:postgresql://aurora-jdbc-demo.cluster-xxxxxxx.us-east-1.rds.amazonaws.com:5432/postgres
INFO com.example.dao.OrderDAO - Found 4 orders
INFO com.example.Application - Retrieved 4 total orders

BUILD SUCCESSFUL in 2s
```

**Key Observation:** All operations (reads and writes) use the same Aurora writer endpoint, demonstrating standard JDBC behavior where everything hits the primary database.

### 🔄 Step 4: Upgrade the application to use AWS JDBC Driver

Now let's upgrde this application to use AWS JDBC Driver while maintaining the same functionality, adding fast failover.

#### 4.1: Review the changes needed to use AWS JDBC Driver

We will use a script to automatically apply the necessary changes. The script updates necessary changes to transform your standard JDBC application into a cloud-native application using AWS JDBC Driver.

Before running the script, let's examine what changes are needed to understand how AWS JDBC Driver integration works:

**File 1: `build.gradle` - Add AWS JDBC Driver Dependency**

**Current (Standard JDBC):**

```gradle
dependencies {
    implementation 'com.zaxxer:HikariCP:4.0.3'
    implementation 'org.postgresql:postgresql:42.4.4'
    implementation 'ch.qos.logback:logback-classic:1.2.12'
    implementation 'org.slf4j:slf4j-api:1.7.36'

    compileOnly 'org.projectlombok:lombok:1.18.24'
    annotationProcessor 'org.projectlombok:lombok:1.18.24'
}
```

**Required Change (AWS JDBC Driver):**

```gradle
dependencies {
    implementation 'com.zaxxer:HikariCP:4.0.3'
    implementation 'org.postgresql:postgresql:42.4.4'
    implementation 'software.amazon.jdbc:aws-advanced-jdbc-wrapper:2.6.2'  // ← Add this
    implementation 'ch.qos.logback:logback-classic:1.2.12'
    implementation 'org.slf4j:slf4j-api:1.7.36'

    compileOnly 'org.projectlombok:lombok:1.18.24'
    annotationProcessor 'org.projectlombok:lombok:1.18.24'
}
```

**Purpose:** Adds the AWS JDBC Driver library that wraps around the standard PostgreSQL driver.

**File 2: `DatabaseConfig.java` - Update Connection Configuration**

**Current (Standard JDBC Configuration):**

```java
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

config.setPoolName("StandardPostgresPool");
log.info("Standard JDBC connection pool initialized");
```

**Required Change (AWS JDBC Driver Configuration):**

```java
// AWS JDBC Driver configuration
configuredJdbcUrl = props.getProperty("db.url");
config.setDataSourceClassName("software.amazon.jdbc.ds.AwsWrapperDataSource");
config.addDataSourceProperty("jdbcUrl", configuredJdbcUrl);
config.addDataSourceProperty("targetDataSourceClassName", "org.postgresql.ds.PGSimpleDataSource");

Properties targetProps = new Properties();
targetProps.setProperty("user", props.getProperty("db.username"));

// Get password from environment variable only
String password = System.getenv("DB_PASSWORD");
if (password == null || password.trim().isEmpty()) {
    throw new RuntimeException("DB_PASSWORD environment variable is required but not set");
}
targetProps.setProperty("password", password);
targetProps.setProperty("wrapperPlugins", "failover");  // ← Enables fast failover

config.addDataSourceProperty("targetDataSourceProperties", targetProps);
config.setPoolName("AWSJDBCPool");
log.info("AWS JDBC Driver connection pool initialized");
```

**Purpose:** Changes from direct JDBC URL configuration to AWS wrapper datasource with plugin support for Aurora-specific features. The wrapper datasource acts as an intelligent proxy that adds Aurora topology awareness, fast failover capabilities, and a foundation for advanced features like read/write splitting and IAM authentication, while transparently delegating actual database operations to the underlying PostgreSQL driver. This transformation enables cloud-native database capabilities without requiring any changes to your application's business logic.

**File 3: `application.properties` - Update JDBC URL**

**Current (Standard JDBC):**

```properties
db.url=jdbc:postgresql://aurora-jdbc-demo.cluster-abc123.us-east-1.rds.amazonaws.com:5432/postgres
```

**Required Change (AWS JDBC Driver):**

```properties
db.url=jdbc:aws-wrapper:postgresql://aurora-jdbc-demo.cluster-abc123.us-east-1.rds.amazonaws.com:5432/postgres
```

**Purpose:** The `aws-wrapper:` prefix tells the driver to use AWS JDBC Driver capabilities instead of the standard PostgreSQL driver.

#### 4.2: Run the script to apply the changes and then execute

```bash
./demo.sh aws-jdbc-wrapper
```

**Expected Output:**

```
Running application...
> Task :run
16:22:18.954 [main] INFO com.zaxxer.hikari.HikariDataSource - AWSJDBCPool - Starting...
16:22:19.632 [main] INFO com.zaxxer.hikari.pool.HikariPool - AWSJDBCPool - Added connection software.amazon.jdbc.wrapper.ConnectionWrapper@770d3326 - org.postgresql.jdbc.PgConnection@4cc8eb05
16:22:19.634 [main] INFO com.zaxxer.hikari.HikariDataSource - AWSJDBCPool - Start completed.
16:22:19.634 [main] INFO com.example.config.DatabaseConfig - AWS JDBC Driver connection pool initialized

=== WRITE OPERATIONS ===
16:22:19.661 [main] INFO com.example.dao.OrderDAO - WRITE OPERATION: Creating new order for customer: John Doe
16:22:19.665 [main] INFO com.example.dao.OrderDAO - Connection URL:
    → WRITER: jdbc:postgresql://aurora-jdbc-demo4.cluster-curzkcvul3uv.us-east-1.rds.amazonaws.com:5432/postgres
16:22:19.684 [main] INFO com.example.dao.OrderDAO - Order created with ID: 13

=== READ OPERATIONS ===
16:22:19.706 [main] INFO com.example.dao.OrderDAO - READ OPERATION: Getting order history
16:22:19.708 [main] INFO com.example.dao.OrderDAO - Connection URL:
    → WRITER: jdbc:postgresql://aurora-jdbc-demo4.cluster-curzkcvul3uv.us-east-1.rds.amazonaws.com:5432/postgres
16:22:19.714 [main] INFO com.example.dao.OrderDAO - Found 16 orders
```

**Key Observation:** All operations still use the writer endpoint, but now your application has fast failover capability without any business logic changes.

### ⚡ Step 5: Enable Read/Write Splitting

Let's unlock the AWS JDBC Driver feature by enabling intelligent connection routing - writes go to the primary instance while reads distribute across Aurora replicas for optimal performance.

#### 5.1: Review the changes needed to use Read/Write Splitting

**File 1: `DatabaseConfig.java` – Add readWriteSplitting plugin**

**Current:**

```java
targetProps.setProperty("wrapperPlugins", "failover");
```

**After:**

```java
targetProps.setProperty("wrapperPlugins", "readWriteSplitting,failover");
```

**File 2: `OrderDAO.java` Read Method Enhancement**

```java
conn.setReadOnly(true);  // Enable read/write splitting for this connection
```

#### 5.2: Run the script to apply the changes and then execute

Run the read/write splitting configuration:

```bash
./demo.sh read-write-splitting
```

**Expected Output:**

```
Running application...
> Task :run
16:51:18.705 [main] INFO com.zaxxer.hikari.HikariDataSource - AWSJDBCReadWritePool - Starting...
16:51:19.405 [main] INFO com.example.config.DatabaseConfig - AWS JDBC Driver with Read/Write Splitting initialized

=== PERFORMING WRITE OPERATIONS ===
16:51:19.434 [main] INFO com.example.dao.OrderDAO - WRITE OPERATION: Creating new order for customer: John Doe
16:51:19.437 [main] INFO com.example.dao.OrderDAO - Connection URL:
    → WRITER: jdbc:postgresql://aurora-jdbc-demo4.cluster-curzkcvul3uv.us-east-1.rds.amazonaws.com:5432/postgres
16:51:19.456 [main] INFO com.example.dao.OrderDAO - Order created with ID: 17

=== PERFORMING READ OPERATIONS ===
16:51:19.477 [main] INFO com.example.dao.OrderDAO - READ OPERATION: Getting order history
16:51:20.044 [main] INFO com.example.dao.OrderDAO - Connection URL:
    → READER: jdbc:postgresql://aurora-jdbc-reader-2.curzkcvul3uv.us-east-1.rds.amazonaws.com:5432/postgres
16:51:20.051 [main] INFO com.example.dao.OrderDAO - Found 20 orders

16:51:20.052 [main] INFO com.example.dao.OrderDAO - READ OPERATION: Generating sales report
16:51:20.285 [main] INFO com.example.dao.OrderDAO - Connection URL:
    → READER: jdbc:postgresql://aurora-jdbc-reader-2.curzkcvul3uv.us-east-1.rds.amazonaws.com:5432/postgres
16:51:20.285 [main] INFO com.example.dao.OrderDAO - Sales report generated: {totalOrders=20, totalRevenue=8150.0}

BUILD SUCCESSFUL in 3s
```

**Key Observation:** While the configured URL remains the same, the AWS JDBC Driver now intelligently routes:

- **Write Operations** → Aurora writer endpoint (primary instance)
- **Read Operations** → Aurora reader endpoints (replica instances)

**Performance Benefits:**

- Reduced writer load: Analytics queries no longer compete with transactions
- Improved scalability: Read traffic distributes across multiple replicas
- Better resource utilization: Each Aurora instance serves its optimal workload

## Resources

- [AWS JDBC Driver Documentation](https://github.com/aws/aws-advanced-jdbc-wrapper)
- [Amazon Aurora Best Practices](https://docs.aws.amazon.com/AmazonRDS/latest/AuroraUserGuide/Aurora.BestPractices.html)
- [HikariCP Connection Pooling](https://github.com/brettwooldridge/HikariCP)

## Security

See [CONTRIBUTING](CONTRIBUTING.md#security-issue-notifications) for more information.

## License

This library is licensed under the MIT-0 License. See the LICENSE file.
 need 