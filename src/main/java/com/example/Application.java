package com.example;

import com.example.dao.OrderDAO;
import com.example.model.Order;
import com.example.config.DatabaseConfig;
import lombok.extern.slf4j.Slf4j;

import java.util.List;
import java.util.Map;

@Slf4j
public class Application {
    public static void main(String[] args) {
        OrderDAO dao = new OrderDAO();

        try {
            // Create table
            dao.createTable();

            // WRITE OPERATIONS - Will use Writer endpoint
            log.info("=== PERFORMING WRITE OPERATIONS ===");
            dao.createOrder(new Order(null, "John Doe", "Laptop", 1, 1200.00, "PENDING", null));
            dao.createOrder(new Order(null, "Jane Smith", "Mouse", 2, 50.00, "PENDING", null));
            dao.createOrder(new Order(null, "Bob Johnson", "Keyboard", 1, 80.00, "COMPLETED", null));
            dao.createOrder(new Order(null, "Alice Brown", "Monitor", 1, 300.00, "PENDING", null));
            
            // Update some orders
            dao.updateOrderStatus(1L, "SHIPPED");
            dao.updateOrderStatus(2L, "COMPLETED");

            // READ OPERATIONS - Will use Reader endpoints (with read/write splitting)
            log.info("=== PERFORMING READ OPERATIONS ===");
            
            List<Order> allOrders = dao.getOrderHistory();
            log.info("Retrieved {} total orders", allOrders.size());
            
            Map<String, Object> salesReport = dao.getSalesReport();
            log.info("Sales Report - Total Orders: {}, Total Revenue: ${}, Avg Order Value: ${}", 
                salesReport.get("totalOrders"), 
                salesReport.get("totalRevenue"), 
                salesReport.get("avgOrderValue"));
            
            List<Order> johnOrders = dao.searchOrdersByCustomer("John");
            log.info("Found {} orders for John", johnOrders.size());

        } catch (Exception e) {
            log.error("Application error", e);
        } finally {
            // Close the connection pool
            DatabaseConfig.closePool();
        }
    }
}
