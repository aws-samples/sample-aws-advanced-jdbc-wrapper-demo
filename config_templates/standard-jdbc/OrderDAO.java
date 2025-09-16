package com.example.dao;

import com.example.config.DatabaseConfig;
import com.example.model.Order;
import lombok.extern.slf4j.Slf4j;

import java.sql.*;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Map;

@Slf4j
public class OrderDAO {

    public void createTable() {
        String sql = "CREATE TABLE IF NOT EXISTS orders (" +
                "id SERIAL PRIMARY KEY," +
                "customer_name VARCHAR(100) NOT NULL," +
                "product VARCHAR(100) NOT NULL," +
                "quantity INTEGER NOT NULL," +
                "total_amount NUMERIC(10,2) NOT NULL," +
                "status VARCHAR(50) DEFAULT 'PENDING'," +
                "order_date TIMESTAMP DEFAULT CURRENT_TIMESTAMP" +
                ")";

        try (Connection conn = DatabaseConfig.getDataSource().getConnection();
             Statement stmt = conn.createStatement()) {
            stmt.execute(sql);
            log.info("Connection URL: {}", highlightInstanceType(conn));
            log.info("Table 'orders' created or already exists");
        } catch (SQLException e) {
            log.error("Error creating table", e);
            throw new RuntimeException(e);
        }
    }

    public void createOrder(Order order) {
        log.info("WRITE OPERATION: Creating new order for customer: {}", order.getCustomerName());
        String sql = "INSERT INTO orders (customer_name, product, quantity, total_amount, status) VALUES (?, ?, ?, ?, ?)";

        try (Connection conn = DatabaseConfig.getDataSource().getConnection();
             PreparedStatement pstmt = conn.prepareStatement(sql, Statement.RETURN_GENERATED_KEYS)) {
            
            log.info("Connection URL: {}", highlightInstanceType(conn));
            
            pstmt.setString(1, order.getCustomerName());
            pstmt.setString(2, order.getProduct());
            pstmt.setInt(3, order.getQuantity());
            pstmt.setDouble(4, order.getTotalAmount());
            pstmt.setString(5, order.getStatus());
            
            pstmt.executeUpdate();
            
            try (ResultSet rs = pstmt.getGeneratedKeys()) {
                if (rs.next()) {
                    order.setId(rs.getLong(1));
                }
            }
            
            log.info("Order created with ID: {}", order.getId());
        } catch (SQLException e) {
            log.error("Error creating order", e);
            throw new RuntimeException(e);
        }
    }

    public void updateOrderStatus(Long orderId, String newStatus) {
        log.info("WRITE OPERATION: Updating order {} status to {}", orderId, newStatus);
        String sql = "UPDATE orders SET status = ? WHERE id = ?";

        try (Connection conn = DatabaseConfig.getDataSource().getConnection();
             PreparedStatement pstmt = conn.prepareStatement(sql)) {
            
            log.info("Connection URL: {}", highlightInstanceType(conn));
            
            pstmt.setString(1, newStatus);
            pstmt.setLong(2, orderId);
            
            int updated = pstmt.executeUpdate();
            log.info("Updated {} order(s)", updated);
        } catch (SQLException e) {
            log.error("Error updating order status", e);
            throw new RuntimeException(e);
        }
    }

    public List<Order> getOrderHistory() {
        log.info("READ OPERATION: Getting order history");
        String sql = "SELECT * FROM orders ORDER BY order_date DESC";
        List<Order> orders = new ArrayList<>();

        try (Connection conn = DatabaseConfig.getDataSource().getConnection();
             PreparedStatement pstmt = conn.prepareStatement(sql);
             ResultSet rs = pstmt.executeQuery()) {
                
            log.info("Connection URL: {}", highlightInstanceType(conn));
            
            while (rs.next()) {
                Order order = new Order(
                    rs.getLong("id"),
                    rs.getString("customer_name"),
                    rs.getString("product"),
                    rs.getInt("quantity"),
                    rs.getDouble("total_amount"),
                    rs.getString("status"),
                    rs.getTimestamp("order_date").toLocalDateTime()
                );
                orders.add(order);
            }
            
            log.info("Found {} orders", orders.size());
            return orders;
        } catch (SQLException e) {
            log.error("Error getting order history", e);
            throw new RuntimeException(e);
        }
    }

    public Map<String, Object> getSalesReport() {
        log.info("READ OPERATION: Generating sales report");
        String sql = "SELECT " +
                "COUNT(*) as total_orders, " +
                "SUM(total_amount) as total_revenue, " +
                "AVG(total_amount) as avg_order_value " +
                "FROM orders";

        Map<String, Object> report = new HashMap<>();

        try (Connection conn = DatabaseConfig.getDataSource().getConnection();
             PreparedStatement pstmt = conn.prepareStatement(sql);
             ResultSet rs = pstmt.executeQuery()) {
                
            log.info("Connection URL: {}", highlightInstanceType(conn));
            
            if (rs.next()) {
                report.put("totalOrders", rs.getInt("total_orders"));
                report.put("totalRevenue", rs.getDouble("total_revenue"));
                report.put("avgOrderValue", rs.getDouble("avg_order_value"));
            }
            
            log.info("Sales report generated: {}", report);
            return report;
        } catch (SQLException e) {
            log.error("Error generating sales report", e);
            throw new RuntimeException(e);
        }
    }

    public List<Order> searchOrdersByCustomer(String customerName) {
        log.info("READ OPERATION: Searching orders for customer: {}", customerName);
        String sql = "SELECT * FROM orders WHERE customer_name ILIKE ? ORDER BY order_date DESC";
        List<Order> orders = new ArrayList<>();

        try (Connection conn = DatabaseConfig.getDataSource().getConnection();
             PreparedStatement pstmt = conn.prepareStatement(sql)) {
            log.info("Connection URL: {}", highlightInstanceType(conn));
            
            pstmt.setString(1, "%" + customerName + "%");
            
            try (ResultSet rs = pstmt.executeQuery()) {
                while (rs.next()) {
                    Order order = new Order(
                        rs.getLong("id"),
                        rs.getString("customer_name"),
                        rs.getString("product"),
                        rs.getInt("quantity"),
                        rs.getDouble("total_amount"),
                        rs.getString("status"),
                        rs.getTimestamp("order_date").toLocalDateTime()
                    );
                    orders.add(order);
                }
            }
            
            log.info("Found {} orders for customer: {}", orders.size(), customerName);
            return orders;
        } catch (SQLException e) {
            log.error("Error searching orders", e);
            throw new RuntimeException(e);
        }
    }
    

    private String highlightInstanceType(Connection conn) throws SQLException {
        String url = conn.getMetaData().getURL();
        
        // Query Aurora to determine if this is a reader or writer instance
        try (Statement stmt = conn.createStatement();
             ResultSet rs = stmt.executeQuery("SELECT pg_is_in_recovery()")) {
            if (rs.next()) {
                boolean isReader = rs.getBoolean(1);
                String role = isReader ? "READER" : "WRITER";
                return "\n    → " + role + ": " + url;
            }
        } catch (SQLException e) {
            // Fallback to URL parsing if Aurora query fails
            if (url.contains("reader")) {
                return "\n    → READER: " + url;
            }
        }
        
        return "\n    → WRITER: " + url;
    }
}