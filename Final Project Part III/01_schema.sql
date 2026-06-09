/* =========================================================
   Equipment Management System - 01_schema.sql
   Target: MySQL 8.0 / MariaDB
   Charset: utf8mb4
   ========================================================= */

SET NAMES utf8mb4;
SET FOREIGN_KEY_CHECKS = 0;

DROP TABLE IF EXISTS STATUS_HISTORY;
DROP TABLE IF EXISTS MAINTENANCE_TICKET;
DROP TABLE IF EXISTS BORROW_RECORD;
DROP TABLE IF EXISTS CONSUME_RECORD;
DROP TABLE IF EXISTS CONSUMABLE_DETAIL;
DROP TABLE IF EXISTS REUSABLE_EQUIPMENT;
DROP TABLE IF EXISTS ASSET_DETAIL;
DROP TABLE IF EXISTS ITEM;
DROP TABLE IF EXISTS DEPARTMENT_ADMINISTRATOR;
DROP TABLE IF EXISTS EQUIPMENT_SUPERVISOR;
DROP TABLE IF EXISTS `USER`;
DROP TABLE IF EXISTS VENDOR;
DROP TABLE IF EXISTS ROLE;
DROP TABLE IF EXISTS SPACE;

SET FOREIGN_KEY_CHECKS = 1;

/* -------------------------
   1. Storage spaces
   ------------------------- */
CREATE TABLE SPACE (
    space_id VARCHAR(50) PRIMARY KEY,
    space_name VARCHAR(100) NOT NULL,
    location_type VARCHAR(100) NOT NULL,
    CHECK (location_type IN ('教室', '實驗室', '儲藏室', '辦公室'))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

/* -------------------------
   2. Roles
   ------------------------- */
CREATE TABLE ROLE (
    role_id INT PRIMARY KEY,
    role_name VARCHAR(50) NOT NULL UNIQUE,
    CHECK (role_name IN ('系所管理員', '全系師生', '設備負責人'))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

/* -------------------------
   3. Maintenance vendors
   ------------------------- */
CREATE TABLE VENDOR (
    vendor_id INT PRIMARY KEY,
    vendor_name VARCHAR(100) NOT NULL,
    vendor_contact VARCHAR(255)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

/* -------------------------
   4. Users
   NOTE: USER is quoted because USER is a MySQL reserved/system keyword.
   ------------------------- */
CREATE TABLE `USER` (
    user_id VARCHAR(50) PRIMARY KEY,
    user_name VARCHAR(100) NOT NULL,
    email VARCHAR(255) UNIQUE NOT NULL,
    role_id INT NOT NULL,
    FOREIGN KEY (role_id) REFERENCES ROLE(role_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

/* Optional ISA subtables for user roles. */
CREATE TABLE DEPARTMENT_ADMINISTRATOR (
    user_id VARCHAR(50) PRIMARY KEY,
    FOREIGN KEY (user_id) REFERENCES `USER`(user_id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE EQUIPMENT_SUPERVISOR (
    user_id VARCHAR(50) PRIMARY KEY,
    FOREIGN KEY (user_id) REFERENCES `USER`(user_id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

/* -------------------------
   5. Base item table
   ------------------------- */
CREATE TABLE ITEM (
    internal_id VARCHAR(50) PRIMARY KEY,
    item_name VARCHAR(255) NOT NULL,
    manage_type VARCHAR(50) NOT NULL,
    current_status VARCHAR(50) NOT NULL,
    warranty_expiry DATE,
    space_id VARCHAR(50) NOT NULL,
    created_by_user_id VARCHAR(50),
    CHECK (manage_type IN ('財產設備', '非列管設備', '耗材')),
    CHECK (current_status IN ('可用', '借出中', '維修中', '停用', '報廢', '遺失')),
    FOREIGN KEY (space_id) REFERENCES SPACE(space_id),
    FOREIGN KEY (created_by_user_id) REFERENCES `USER`(user_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

/* -------------------------
   6. Asset details
   ------------------------- */
CREATE TABLE ASSET_DETAIL (
    asset_id VARCHAR(50) PRIMARY KEY,
    internal_id VARCHAR(50) NOT NULL UNIQUE,
    fund_source VARCHAR(100),
    acquired_date DATE,
    acquired_cost INT CHECK (acquired_cost >= 3000),
    lifespan_years INT CHECK (lifespan_years > 0),
    custodian_id VARCHAR(50) NOT NULL,
    FOREIGN KEY (internal_id) REFERENCES ITEM(internal_id) ON DELETE CASCADE,
    FOREIGN KEY (custodian_id) REFERENCES `USER`(user_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

/* -------------------------
   7. Reusable equipment details
   ------------------------- */
CREATE TABLE REUSABLE_EQUIPMENT (
    internal_id VARCHAR(50) PRIMARY KEY,
    specification VARCHAR(255) NOT NULL,
    quantity INT DEFAULT 0 CHECK (quantity >= 0),
    is_borrowable BOOLEAN NOT NULL DEFAULT TRUE,
    need_return BOOLEAN NOT NULL DEFAULT TRUE,
    FOREIGN KEY (internal_id) REFERENCES ITEM(internal_id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

/* -------------------------
   8. Consumable details
   ------------------------- */
CREATE TABLE CONSUMABLE_DETAIL (
    internal_id VARCHAR(50) PRIMARY KEY,
    stock_quantity INT DEFAULT 0 CHECK (stock_quantity >= 0),
    min_stock INT DEFAULT 0 CHECK (min_stock >= 0),
    unit VARCHAR(20) NOT NULL,
    FOREIGN KEY (internal_id) REFERENCES ITEM(internal_id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

/* -------------------------
   9. Consumable usage records
   ------------------------- */
CREATE TABLE CONSUME_RECORD (
    record_id INT AUTO_INCREMENT PRIMARY KEY,
    internal_id VARCHAR(50) NOT NULL,
    user_id VARCHAR(50) NOT NULL,
    consume_time TIMESTAMP NOT NULL,
    amount INT NOT NULL CHECK (amount > 0),
    purpose VARCHAR(255) NOT NULL,
    FOREIGN KEY (internal_id) REFERENCES CONSUMABLE_DETAIL(internal_id),
    FOREIGN KEY (user_id) REFERENCES `USER`(user_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

/* -------------------------
   10. Borrow records
   ------------------------- */
CREATE TABLE BORROW_RECORD (
    record_id INT AUTO_INCREMENT PRIMARY KEY,
    internal_id VARCHAR(50) NOT NULL,
    user_id VARCHAR(50) NOT NULL,
    borrow_time TIMESTAMP NOT NULL,
    expected_return TIMESTAMP,
    actual_return TIMESTAMP,
    status VARCHAR(50) NOT NULL,
    CHECK (status IN ('借用中', '已歸還', '逾期', '取消')),
    CHECK (expected_return IS NULL OR expected_return > borrow_time),
    CHECK (actual_return IS NULL OR actual_return >= borrow_time),
    FOREIGN KEY (internal_id) REFERENCES ITEM(internal_id),
    FOREIGN KEY (user_id) REFERENCES `USER`(user_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

/* -------------------------
   11. Maintenance tickets
   ------------------------- */
CREATE TABLE MAINTENANCE_TICKET (
    ticket_id INT AUTO_INCREMENT PRIMARY KEY,
    internal_id VARCHAR(50) NOT NULL,
    reporter_id VARCHAR(50) NOT NULL,
    handler_id VARCHAR(50),
    vendor_id INT,
    repair_time TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    issue_desc TEXT NOT NULL,
    maint_status VARCHAR(50) NOT NULL,
    repair_cost INT CHECK (repair_cost >= 0),
    resolved_time TIMESTAMP NULL,
    replaced_parts VARCHAR(255),
    next_maint_date DATE,
    result TEXT,
    CHECK (maint_status IN ('待處理', '處理中', '已完成', '取消')),
    CHECK (resolved_time IS NULL OR resolved_time >= repair_time),
    CHECK (
        next_maint_date IS NULL
        OR (
            resolved_time IS NOT NULL
            AND next_maint_date > CAST(resolved_time AS DATE)
        )
        OR (
            resolved_time IS NULL
            AND next_maint_date > CAST(repair_time AS DATE)
        )
    ),
    FOREIGN KEY (internal_id) REFERENCES ITEM(internal_id),
    FOREIGN KEY (reporter_id) REFERENCES `USER`(user_id),
    FOREIGN KEY (handler_id) REFERENCES `USER`(user_id),
    FOREIGN KEY (vendor_id) REFERENCES VENDOR(vendor_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

/* -------------------------
   12. Status history
   ------------------------- */
CREATE TABLE STATUS_HISTORY (
    log_id INT AUTO_INCREMENT PRIMARY KEY,
    internal_id VARCHAR(50) NOT NULL,
    operator_id VARCHAR(50) NOT NULL,
    change_time TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    old_status VARCHAR(50),
    new_status VARCHAR(50) NOT NULL,
    reason VARCHAR(255) NOT NULL,
    CHECK (old_status IS NULL OR old_status IN ('可用', '借出中', '維修中', '停用', '報廢', '遺失')),
    CHECK (new_status IN ('可用', '借出中', '維修中', '停用', '報廢', '遺失')),
    FOREIGN KEY (internal_id) REFERENCES ITEM(internal_id),
    FOREIGN KEY (operator_id) REFERENCES `USER`(user_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

/* Helpful indexes for views and procedures. */
CREATE INDEX idx_item_status_type ON ITEM(current_status, manage_type);
CREATE INDEX idx_item_space ON ITEM(space_id);
CREATE INDEX idx_borrow_item_status ON BORROW_RECORD(internal_id, status, actual_return);
CREATE INDEX idx_maint_item_status ON MAINTENANCE_TICKET(internal_id, maint_status);
CREATE INDEX idx_consume_item_time ON CONSUME_RECORD(internal_id, consume_time);
CREATE INDEX idx_status_history_item_time ON STATUS_HISTORY(internal_id, change_time);
