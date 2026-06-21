/* =========================================================
   Department Managed Item and Maintenance System
   Final Project Part III - single executable SQL file

   Target DBMS : MariaDB 10.6+ / tested with MariaDB 12.3 client
   Charset     : utf8mb4
   How to run  :
       mysql -u root -p < sql/00_final_project_all.sql

   Design notes:
   - All tables use numeric surrogate primary keys.
   - Business identifiers use fixed CHAR codes.
   - Status and role values are stored as codes and referenced by code tables.
   - Daily views filter out archived rows; admin audit view keeps archive history.
   ========================================================= */

SET NAMES utf8mb4;
CREATE DATABASE IF NOT EXISTS equipment_management
  DEFAULT CHARACTER SET utf8mb4
  DEFAULT COLLATE utf8mb4_unicode_ci;
USE equipment_management;

SET FOREIGN_KEY_CHECKS = 0;

DROP VIEW IF EXISTS vw_Admin_Archived_History;
DROP VIEW IF EXISTS vw_Admin_Overdue_Borrows;
DROP VIEW IF EXISTS vw_Admin_Audit_Trail;
DROP VIEW IF EXISTS vw_Admin_Maintenance_Ticket_Master;
DROP VIEW IF EXISTS vw_Admin_Consumable_Master;
DROP VIEW IF EXISTS vw_Admin_Consumable_Alert;
DROP VIEW IF EXISTS vw_Admin_Item_Management;
DROP VIEW IF EXISTS vw_Admin_Asset_Master;
DROP VIEW IF EXISTS vw_Supervisor_Assigned_Maintenance_History;
DROP VIEW IF EXISTS vw_Supervisor_Assigned_Maintenance_Active;
DROP VIEW IF EXISTS vw_Supervisor_Maintenance_History;
DROP VIEW IF EXISTS vw_Supervisor_Assigned_Maintenance_Tasks;
DROP VIEW IF EXISTS vw_Student_Maintenance_Handlers;
DROP VIEW IF EXISTS vw_Student_Maintenance_Reportable_Items;
DROP VIEW IF EXISTS vw_Student_Current_Borrowed_Items;
DROP VIEW IF EXISTS vw_Student_Available_Consumables;
DROP VIEW IF EXISTS vw_Student_Available_Borrowable_Items;
DROP VIEW IF EXISTS vw_Login_User_Role;

DROP PROCEDURE IF EXISTS sp_archive_closed_history;
DROP PROCEDURE IF EXISTS sp_change_item_status;
DROP PROCEDURE IF EXISTS sp_close_maintenance_ticket;
DROP PROCEDURE IF EXISTS sp_open_maintenance_ticket;
DROP PROCEDURE IF EXISTS sp_return_item;
DROP PROCEDURE IF EXISTS sp_borrow_item;
DROP PROCEDURE IF EXISTS sp_issue_consumable;

DROP TRIGGER IF EXISTS trg_maintenance_ticket_before_update_check;
DROP TRIGGER IF EXISTS trg_maintenance_ticket_before_insert_check;
DROP TRIGGER IF EXISTS trg_consume_before_insert_check;
DROP TRIGGER IF EXISTS trg_borrow_before_update_check;
DROP TRIGGER IF EXISTS trg_borrow_before_insert_check;
DROP TRIGGER IF EXISTS trg_consumable_detail_before_update_check;
DROP TRIGGER IF EXISTS trg_consumable_detail_before_insert_check;
DROP TRIGGER IF EXISTS trg_reusable_item_detail_before_update_check;
DROP TRIGGER IF EXISTS trg_reusable_item_detail_before_insert_check;
DROP TRIGGER IF EXISTS trg_controlled_item_detail_before_update_check;
DROP TRIGGER IF EXISTS trg_controlled_item_detail_before_insert_check;
DROP TRIGGER IF EXISTS trg_equipment_detail_before_update_check;
DROP TRIGGER IF EXISTS trg_equipment_detail_before_insert_check;
DROP TRIGGER IF EXISTS trg_item_before_update_guard;

DROP TABLE IF EXISTS ITEM_STATUS_HISTORY;
DROP TABLE IF EXISTS MAINTENANCE_ACTION;
DROP TABLE IF EXISTS MAINTENANCE_TICKET;
DROP TABLE IF EXISTS CONSUME_RECORD;
DROP TABLE IF EXISTS BORROW_RECORD;
DROP TABLE IF EXISTS CONSUMABLE_DETAIL;
DROP TABLE IF EXISTS REUSABLE_ITEM_DETAIL;
DROP TABLE IF EXISTS CONTROLLED_ITEM_DETAIL;
DROP TABLE IF EXISTS EQUIPMENT_DETAIL;
DROP TABLE IF EXISTS ITEM;
DROP TABLE IF EXISTS VENDOR;
DROP TABLE IF EXISTS SPACE;
DROP TABLE IF EXISTS USER_ROLE;
DROP TABLE IF EXISTS APP_USER;
DROP TABLE IF EXISTS BUSINESS_CODE_SEQUENCE;

/* Legacy Part III tables from earlier drafts. */
DROP TABLE IF EXISTS STATUS_HISTORY;
DROP TABLE IF EXISTS REUSABLE_EQUIPMENT;
DROP TABLE IF EXISTS ASSET_DETAIL;
DROP TABLE IF EXISTS DEPARTMENT_ADMINISTRATOR;
DROP TABLE IF EXISTS EQUIPMENT_SUPERVISOR;
DROP TABLE IF EXISTS `USER`;
DROP TABLE IF EXISTS ROLE;

DROP TABLE IF EXISTS MAINTENANCE_ACTION_TYPE_CODE;
DROP TABLE IF EXISTS SPACE_TYPE_CODE;
DROP TABLE IF EXISTS MAINTENANCE_STATUS_CODE;
DROP TABLE IF EXISTS BORROW_STATUS_CODE;
DROP TABLE IF EXISTS ITEM_STATUS_CODE;
DROP TABLE IF EXISTS ITEM_TYPE_CODE;
DROP TABLE IF EXISTS ROLE_CODE;

SET FOREIGN_KEY_CHECKS = 1;

/* =========================================================
   1. Code tables
   ========================================================= */

CREATE TABLE ROLE_CODE (
    role_code CHAR(3) PRIMARY KEY,
    role_name VARCHAR(30) NOT NULL UNIQUE,
    role_description VARCHAR(120) NOT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE ITEM_TYPE_CODE (
    item_type_code CHAR(3) PRIMARY KEY,
    type_name VARCHAR(40) NOT NULL UNIQUE,
    type_description VARCHAR(160) NOT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE ITEM_STATUS_CODE (
    item_status_code CHAR(3) PRIMARY KEY,
    status_name VARCHAR(30) NOT NULL UNIQUE,
    status_description VARCHAR(120) NOT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE BORROW_STATUS_CODE (
    borrow_status_code CHAR(3) PRIMARY KEY,
    status_name VARCHAR(30) NOT NULL UNIQUE,
    status_description VARCHAR(120) NOT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE MAINTENANCE_STATUS_CODE (
    maintenance_status_code CHAR(3) PRIMARY KEY,
    status_name VARCHAR(30) NOT NULL UNIQUE,
    status_description VARCHAR(120) NOT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE SPACE_TYPE_CODE (
    space_type_code CHAR(3) PRIMARY KEY,
    type_name VARCHAR(30) NOT NULL UNIQUE,
    type_description VARCHAR(120) NOT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE MAINTENANCE_ACTION_TYPE_CODE (
    action_type_code CHAR(3) PRIMARY KEY,
    action_type_name VARCHAR(30) NOT NULL UNIQUE,
    action_type_description VARCHAR(120) NOT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE BUSINESS_CODE_SEQUENCE (
    sequence_name VARCHAR(30) PRIMARY KEY,
    next_value BIGINT UNSIGNED NOT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

/* =========================================================
   2. Core tables
   ========================================================= */

CREATE TABLE APP_USER (
    user_id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    user_code CHAR(8) NOT NULL UNIQUE,
    user_name VARCHAR(50) NOT NULL,
    email VARCHAR(254) NOT NULL UNIQUE,
    phone VARCHAR(20) NULL,
    created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE USER_ROLE (
    user_id BIGINT UNSIGNED NOT NULL,
    role_code CHAR(3) NOT NULL,
    PRIMARY KEY (user_id, role_code),
    CONSTRAINT fk_user_role_user
        FOREIGN KEY (user_id) REFERENCES APP_USER(user_id)
        ON DELETE CASCADE,
    CONSTRAINT fk_user_role_role
        FOREIGN KEY (role_code) REFERENCES ROLE_CODE(role_code)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE SPACE (
    space_id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    space_code CHAR(6) NOT NULL UNIQUE,
    space_name VARCHAR(80) NOT NULL,
    space_type_code CHAR(3) NOT NULL,
    building_name VARCHAR(50) NOT NULL,
    room_no VARCHAR(20) NOT NULL,
    is_active CHAR(1) NOT NULL DEFAULT 'Y',
    CONSTRAINT fk_space_type
        FOREIGN KEY (space_type_code) REFERENCES SPACE_TYPE_CODE(space_type_code),
    CONSTRAINT ck_space_is_active CHECK (is_active IN ('Y','N'))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE VENDOR (
    vendor_id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    vendor_code CHAR(8) NOT NULL UNIQUE,
    vendor_name VARCHAR(100) NOT NULL,
    contact_name VARCHAR(50) NULL,
    phone VARCHAR(20) NOT NULL,
    email VARCHAR(254) NULL,
    is_active CHAR(1) NOT NULL DEFAULT 'Y',
    CONSTRAINT ck_vendor_is_active CHECK (is_active IN ('Y','N'))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE ITEM (
    item_id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    item_code CHAR(10) NOT NULL UNIQUE,
    item_name VARCHAR(100) NOT NULL,
    item_type_code CHAR(3) NOT NULL,
    current_status_code CHAR(3) NOT NULL,
    current_space_id BIGINT UNSIGNED NOT NULL,
    supervisor_user_id BIGINT UNSIGNED NOT NULL,
    created_by_user_id BIGINT UNSIGNED NOT NULL,
    created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    warranty_expiry_date DATE NULL,
    archived_at DATETIME NULL,
    CONSTRAINT fk_item_type
        FOREIGN KEY (item_type_code) REFERENCES ITEM_TYPE_CODE(item_type_code),
    CONSTRAINT fk_item_status
        FOREIGN KEY (current_status_code) REFERENCES ITEM_STATUS_CODE(item_status_code),
    CONSTRAINT fk_item_space
        FOREIGN KEY (current_space_id) REFERENCES SPACE(space_id),
    CONSTRAINT fk_item_supervisor
        FOREIGN KEY (supervisor_user_id) REFERENCES APP_USER(user_id),
    CONSTRAINT fk_item_created_by
        FOREIGN KEY (created_by_user_id) REFERENCES APP_USER(user_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

/* =========================================================
   3. Item subtype tables
   ========================================================= */

CREATE TABLE EQUIPMENT_DETAIL (
    item_id BIGINT UNSIGNED PRIMARY KEY,
    property_tag_no VARCHAR(30) NOT NULL UNIQUE,
    acquisition_date DATE NOT NULL,
    acquisition_amount DECIMAL(12,0) NOT NULL,
    lifespan_years SMALLINT UNSIGNED NOT NULL,
    fund_source VARCHAR(50) NOT NULL,
    custodian_user_id BIGINT UNSIGNED NOT NULL,
    CONSTRAINT fk_equipment_item
        FOREIGN KEY (item_id) REFERENCES ITEM(item_id)
        ON DELETE CASCADE,
    CONSTRAINT fk_equipment_custodian
        FOREIGN KEY (custodian_user_id) REFERENCES APP_USER(user_id),
    CONSTRAINT ck_equipment_amount CHECK (acquisition_amount >= 10000),
    CONSTRAINT ck_equipment_lifespan CHECK (lifespan_years > 0)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE CONTROLLED_ITEM_DETAIL (
    item_id BIGINT UNSIGNED PRIMARY KEY,
    control_tag_no VARCHAR(30) NOT NULL UNIQUE,
    acquisition_date DATE NOT NULL,
    acquisition_amount DECIMAL(12,0) NOT NULL,
    custodian_user_id BIGINT UNSIGNED NULL,
    CONSTRAINT fk_controlled_item
        FOREIGN KEY (item_id) REFERENCES ITEM(item_id)
        ON DELETE CASCADE,
    CONSTRAINT fk_controlled_custodian
        FOREIGN KEY (custodian_user_id) REFERENCES APP_USER(user_id),
    CONSTRAINT ck_controlled_amount CHECK (acquisition_amount >= 3000 AND acquisition_amount < 10000)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE REUSABLE_ITEM_DETAIL (
    item_id BIGINT UNSIGNED PRIMARY KEY,
    specification VARCHAR(200) NOT NULL,
    is_borrowable CHAR(1) NOT NULL,
    need_return CHAR(1) NOT NULL,
    CONSTRAINT fk_reusable_item
        FOREIGN KEY (item_id) REFERENCES ITEM(item_id)
        ON DELETE CASCADE,
    CONSTRAINT ck_reusable_borrowable CHECK (is_borrowable IN ('Y','N')),
    CONSTRAINT ck_reusable_need_return CHECK (need_return IN ('Y','N'))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE CONSUMABLE_DETAIL (
    item_id BIGINT UNSIGNED PRIMARY KEY,
    stock_quantity INT UNSIGNED NOT NULL,
    min_stock_quantity INT UNSIGNED NOT NULL,
    unit_name VARCHAR(20) NOT NULL,
    CONSTRAINT fk_consumable_item
        FOREIGN KEY (item_id) REFERENCES ITEM(item_id)
        ON DELETE CASCADE,
    CONSTRAINT ck_consumable_min_stock CHECK (min_stock_quantity >= 0),
    CONSTRAINT ck_consumable_stock CHECK (stock_quantity >= 0)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

/* =========================================================
   4. Transaction and history tables
   ========================================================= */

CREATE TABLE BORROW_RECORD (
    borrow_id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    borrow_code CHAR(10) NOT NULL UNIQUE,
    item_id BIGINT UNSIGNED NOT NULL,
    borrower_user_id BIGINT UNSIGNED NOT NULL,
    borrowed_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    expected_return_at DATETIME NULL,
    returned_at DATETIME NULL,
    borrow_status_code CHAR(3) NOT NULL,
    purpose VARCHAR(200) NULL,
    archived_at DATETIME NULL,
    archive_batch_code CHAR(12) NULL,
    CONSTRAINT fk_borrow_item
        FOREIGN KEY (item_id) REFERENCES ITEM(item_id),
    CONSTRAINT fk_borrow_user
        FOREIGN KEY (borrower_user_id) REFERENCES APP_USER(user_id),
    CONSTRAINT fk_borrow_status
        FOREIGN KEY (borrow_status_code) REFERENCES BORROW_STATUS_CODE(borrow_status_code),
    CONSTRAINT ck_borrow_expected_time CHECK (expected_return_at IS NULL OR expected_return_at > borrowed_at),
    CONSTRAINT ck_borrow_return_time CHECK (returned_at IS NULL OR returned_at >= borrowed_at)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE CONSUME_RECORD (
    consume_id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    consume_code CHAR(10) NOT NULL UNIQUE,
    item_id BIGINT UNSIGNED NOT NULL,
    consumer_user_id BIGINT UNSIGNED NOT NULL,
    consumed_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    amount INT UNSIGNED NOT NULL,
    purpose VARCHAR(200) NOT NULL,
    archived_at DATETIME NULL,
    archive_batch_code CHAR(12) NULL,
    CONSTRAINT fk_consume_item
        FOREIGN KEY (item_id) REFERENCES ITEM(item_id),
    CONSTRAINT fk_consume_user
        FOREIGN KEY (consumer_user_id) REFERENCES APP_USER(user_id),
    CONSTRAINT ck_consume_amount CHECK (amount > 0)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE MAINTENANCE_TICKET (
    ticket_id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    ticket_code CHAR(10) NOT NULL UNIQUE,
    item_id BIGINT UNSIGNED NOT NULL,
    reporter_user_id BIGINT UNSIGNED NOT NULL,
    assigned_handler_user_id BIGINT UNSIGNED NULL,
    current_maintenance_status_code CHAR(3) NOT NULL,
    reported_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    issue_description TEXT NOT NULL,
    closed_at DATETIME NULL,
    created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    archived_at DATETIME NULL,
    archive_batch_code CHAR(12) NULL,
    CONSTRAINT fk_ticket_item
        FOREIGN KEY (item_id) REFERENCES ITEM(item_id),
    CONSTRAINT fk_ticket_reporter
        FOREIGN KEY (reporter_user_id) REFERENCES APP_USER(user_id),
    CONSTRAINT fk_ticket_handler
        FOREIGN KEY (assigned_handler_user_id) REFERENCES APP_USER(user_id),
    CONSTRAINT fk_ticket_status
        FOREIGN KEY (current_maintenance_status_code)
        REFERENCES MAINTENANCE_STATUS_CODE(maintenance_status_code),
    CONSTRAINT ck_ticket_closed_time CHECK (closed_at IS NULL OR closed_at >= reported_at)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE MAINTENANCE_ACTION (
    action_id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    ticket_id BIGINT UNSIGNED NOT NULL,
    action_type_code CHAR(3) NOT NULL,
    operator_user_id BIGINT UNSIGNED NOT NULL,
    vendor_id BIGINT UNSIGNED NULL,
    action_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    previous_status_code CHAR(3) NULL,
    new_status_code CHAR(3) NULL,
    cost_amount DECIMAL(12,0) NULL,
    replaced_part_description TEXT NULL,
    next_maintenance_date DATE NULL,
    action_note TEXT NULL,
    archived_at DATETIME NULL,
    archive_batch_code CHAR(12) NULL,
    CONSTRAINT fk_action_ticket
        FOREIGN KEY (ticket_id) REFERENCES MAINTENANCE_TICKET(ticket_id)
        ON DELETE CASCADE,
    CONSTRAINT fk_action_type
        FOREIGN KEY (action_type_code) REFERENCES MAINTENANCE_ACTION_TYPE_CODE(action_type_code),
    CONSTRAINT fk_action_operator
        FOREIGN KEY (operator_user_id) REFERENCES APP_USER(user_id),
    CONSTRAINT fk_action_vendor
        FOREIGN KEY (vendor_id) REFERENCES VENDOR(vendor_id),
    CONSTRAINT fk_action_prev_status
        FOREIGN KEY (previous_status_code) REFERENCES MAINTENANCE_STATUS_CODE(maintenance_status_code),
    CONSTRAINT fk_action_new_status
        FOREIGN KEY (new_status_code) REFERENCES MAINTENANCE_STATUS_CODE(maintenance_status_code),
    CONSTRAINT ck_action_cost CHECK (cost_amount IS NULL OR cost_amount >= 0)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE ITEM_STATUS_HISTORY (
    history_id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    item_id BIGINT UNSIGNED NOT NULL,
    operator_user_id BIGINT UNSIGNED NOT NULL,
    changed_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    previous_status_code CHAR(3) NULL,
    new_status_code CHAR(3) NOT NULL,
    reason VARCHAR(200) NOT NULL,
    archived_at DATETIME NULL,
    archive_batch_code CHAR(12) NULL,
    CONSTRAINT fk_status_history_item
        FOREIGN KEY (item_id) REFERENCES ITEM(item_id),
    CONSTRAINT fk_status_history_operator
        FOREIGN KEY (operator_user_id) REFERENCES APP_USER(user_id),
    CONSTRAINT fk_status_history_prev_status
        FOREIGN KEY (previous_status_code) REFERENCES ITEM_STATUS_CODE(item_status_code),
    CONSTRAINT fk_status_history_new_status
        FOREIGN KEY (new_status_code) REFERENCES ITEM_STATUS_CODE(item_status_code)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE INDEX idx_item_type_status ON ITEM(item_type_code, current_status_code, archived_at);
CREATE INDEX idx_item_space ON ITEM(current_space_id);
CREATE INDEX idx_borrow_user_status ON BORROW_RECORD(borrower_user_id, borrow_status_code, returned_at, archived_at);
CREATE INDEX idx_borrow_item_status ON BORROW_RECORD(item_id, borrow_status_code, returned_at);
CREATE INDEX idx_consume_item_time ON CONSUME_RECORD(item_id, consumed_at, archived_at);
CREATE INDEX idx_ticket_handler_status ON MAINTENANCE_TICKET(assigned_handler_user_id, current_maintenance_status_code, archived_at);
CREATE INDEX idx_action_ticket_time ON MAINTENANCE_ACTION(ticket_id, action_at, archived_at);
CREATE INDEX idx_history_item_time ON ITEM_STATUS_HISTORY(item_id, changed_at, archived_at);

/* =========================================================
   5. Stored procedures
   ========================================================= */

DELIMITER //

CREATE PROCEDURE sp_issue_consumable (
    IN p_item_id BIGINT UNSIGNED,
    IN p_user_id BIGINT UNSIGNED,
    IN p_amount INT,
    IN p_purpose VARCHAR(200)
)
BEGIN
    DECLARE v_item_type_code CHAR(3);
    DECLARE v_status_code CHAR(3);
    DECLARE v_stock INT UNSIGNED;
    DECLARE v_seq BIGINT UNSIGNED;
    DECLARE v_consume_code CHAR(10);
    DECLARE v_not_found TINYINT DEFAULT 0;

    DECLARE CONTINUE HANDLER FOR NOT FOUND SET v_not_found = 1;
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        RESIGNAL;
    END;

    START TRANSACTION;

    SET v_not_found = 0;
    SELECT i.item_type_code, i.current_status_code, c.stock_quantity
      INTO v_item_type_code, v_status_code, v_stock
      FROM ITEM i
      JOIN CONSUMABLE_DETAIL c ON i.item_id = c.item_id
     WHERE i.item_id = p_item_id
       FOR UPDATE;

    IF v_not_found = 1 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = '查無可領用耗材資料';
    END IF;

    IF v_item_type_code <> 'CON' THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = '只有 CON 耗材可以領用';
    END IF;

    IF v_status_code <> 'AVL' THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = '耗材目前不是 AVL 可用狀態';
    END IF;

    IF p_amount IS NULL OR p_amount <= 0 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = '領用數量必須大於 0';
    END IF;

    IF v_stock < p_amount THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = '庫存不足，無法領用';
    END IF;

    IF p_purpose IS NULL OR TRIM(p_purpose) = '' THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = '領用用途不可空白';
    END IF;

    UPDATE BUSINESS_CODE_SEQUENCE
       SET next_value = LAST_INSERT_ID(next_value + 1)
     WHERE sequence_name = 'CONSUME';
    SET v_seq = LAST_INSERT_ID();
    SET v_consume_code = CONCAT('CSM', LPAD(v_seq, 7, '0'));

    UPDATE CONSUMABLE_DETAIL
       SET stock_quantity = stock_quantity - p_amount
     WHERE item_id = p_item_id;

    INSERT INTO CONSUME_RECORD (
        consume_code, item_id, consumer_user_id, consumed_at, amount, purpose
    ) VALUES (
        v_consume_code, p_item_id, p_user_id, CURRENT_TIMESTAMP, p_amount, p_purpose
    );

    COMMIT;
END//

CREATE PROCEDURE sp_borrow_item (
    IN p_item_id BIGINT UNSIGNED,
    IN p_user_id BIGINT UNSIGNED,
    IN p_expected_return_at DATETIME,
    IN p_purpose VARCHAR(200)
)
BEGIN
    DECLARE v_item_type_code CHAR(3);
    DECLARE v_status_code CHAR(3);
    DECLARE v_is_borrowable CHAR(1) DEFAULT 'Y';
    DECLARE v_open_count INT DEFAULT 0;
    DECLARE v_seq BIGINT UNSIGNED;
    DECLARE v_borrow_code CHAR(10);
    DECLARE v_not_found TINYINT DEFAULT 0;

    DECLARE CONTINUE HANDLER FOR NOT FOUND SET v_not_found = 1;
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        RESIGNAL;
    END;

    START TRANSACTION;

    SET v_not_found = 0;
    SELECT item_type_code, current_status_code
      INTO v_item_type_code, v_status_code
      FROM ITEM
     WHERE item_id = p_item_id
       FOR UPDATE;

    IF v_not_found = 1 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = '查無物品，無法借用';
    END IF;

    IF v_item_type_code = 'CON' THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'CON 耗材不得借用，請使用領用流程';
    END IF;

    IF v_item_type_code NOT IN ('EQP','CTL','RUS') THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = '此物品分類不可借用';
    END IF;

    IF v_status_code <> 'AVL' THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = '只有 AVL 可用物品可以借用';
    END IF;

    IF p_expected_return_at IS NOT NULL AND p_expected_return_at <= CURRENT_TIMESTAMP THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = '預計歸還時間必須晚於借用時間';
    END IF;

    IF v_item_type_code = 'RUS' THEN
        SET v_not_found = 0;
        SELECT is_borrowable
          INTO v_is_borrowable
          FROM REUSABLE_ITEM_DETAIL
         WHERE item_id = p_item_id;

        IF v_not_found = 1 OR v_is_borrowable <> 'Y' THEN
            SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = '此 RUS 物品設定為不可借用';
        END IF;
    END IF;

    SELECT COUNT(*)
      INTO v_open_count
      FROM BORROW_RECORD
     WHERE item_id = p_item_id
       AND borrow_status_code IN ('ACT','OVD')
       AND returned_at IS NULL;

    IF v_open_count > 0 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = '此物品已有未歸還借用紀錄';
    END IF;

    UPDATE BUSINESS_CODE_SEQUENCE
       SET next_value = LAST_INSERT_ID(next_value + 1)
     WHERE sequence_name = 'BORROW';
    SET v_seq = LAST_INSERT_ID();
    SET v_borrow_code = CONCAT('BRW', LPAD(v_seq, 7, '0'));

    INSERT INTO BORROW_RECORD (
        borrow_code, item_id, borrower_user_id, borrowed_at,
        expected_return_at, returned_at, borrow_status_code, purpose
    ) VALUES (
        v_borrow_code, p_item_id, p_user_id, CURRENT_TIMESTAMP,
        p_expected_return_at, NULL, 'ACT', p_purpose
    );

    UPDATE ITEM
       SET current_status_code = 'OUT'
     WHERE item_id = p_item_id;

    INSERT INTO ITEM_STATUS_HISTORY (
        item_id, operator_user_id, changed_at, previous_status_code, new_status_code, reason
    ) VALUES (
        p_item_id, p_user_id, CURRENT_TIMESTAMP, 'AVL', 'OUT', 'sp_borrow_item: 建立借用紀錄'
    );

    COMMIT;
END//

CREATE PROCEDURE sp_return_item (
    IN p_borrow_id BIGINT UNSIGNED,
    IN p_operator_user_id BIGINT UNSIGNED,
    IN p_is_damaged CHAR(1),
    IN p_issue_description TEXT
)
BEGIN
    DECLARE v_item_id BIGINT UNSIGNED;
    DECLARE v_item_status_code CHAR(3);
    DECLARE v_item_type_code CHAR(3);
    DECLARE v_borrow_status_code CHAR(3);
    DECLARE v_returned_at DATETIME;
    DECLARE v_handler_user_id BIGINT UNSIGNED;
    DECLARE v_seq BIGINT UNSIGNED;
    DECLARE v_ticket_code CHAR(10);
    DECLARE v_ticket_id BIGINT UNSIGNED;
    DECLARE v_not_found TINYINT DEFAULT 0;

    DECLARE CONTINUE HANDLER FOR NOT FOUND SET v_not_found = 1;
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        RESIGNAL;
    END;

    START TRANSACTION;

    SET v_not_found = 0;
    SELECT item_id, borrow_status_code, returned_at
      INTO v_item_id, v_borrow_status_code, v_returned_at
      FROM BORROW_RECORD
     WHERE borrow_id = p_borrow_id
       FOR UPDATE;

    IF v_not_found = 1 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = '查無借用紀錄，無法歸還';
    END IF;

    SET v_not_found = 0;
    SELECT item_type_code, current_status_code, supervisor_user_id
      INTO v_item_type_code, v_item_status_code, v_handler_user_id
      FROM ITEM
     WHERE item_id = v_item_id
       FOR UPDATE;

    IF v_not_found = 1 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = '借用紀錄對應物品不存在';
    END IF;

    IF v_borrow_status_code NOT IN ('ACT','OVD') OR v_returned_at IS NOT NULL THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = '此借用紀錄不是可歸還狀態';
    END IF;

    IF p_is_damaged NOT IN ('Y','N') THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'p_is_damaged 必須為 Y 或 N';
    END IF;

    UPDATE BORROW_RECORD
       SET returned_at = CURRENT_TIMESTAMP,
           borrow_status_code = 'RET'
     WHERE borrow_id = p_borrow_id;

    IF p_is_damaged = 'Y' THEN
        UPDATE BUSINESS_CODE_SEQUENCE
           SET next_value = LAST_INSERT_ID(next_value + 1)
         WHERE sequence_name = 'TICKET';
        SET v_seq = LAST_INSERT_ID();
        SET v_ticket_code = CONCAT('MNT', LPAD(v_seq, 7, '0'));

        INSERT INTO MAINTENANCE_TICKET (
            ticket_code, item_id, reporter_user_id, assigned_handler_user_id,
            current_maintenance_status_code, reported_at, issue_description
        ) VALUES (
            v_ticket_code, v_item_id, p_operator_user_id, v_handler_user_id,
            'NEW', CURRENT_TIMESTAMP,
            COALESCE(NULLIF(TRIM(p_issue_description), ''), '借用歸還時通報損壞')
        );

        SET v_ticket_id = LAST_INSERT_ID();

        INSERT INTO MAINTENANCE_ACTION (
            ticket_id, action_type_code, operator_user_id, action_at,
            previous_status_code, new_status_code, action_note
        ) VALUES (
            v_ticket_id, 'CRT', p_operator_user_id, CURRENT_TIMESTAMP,
            NULL, 'NEW', 'sp_return_item: 歸還時通報損壞，自動建立工單'
        );

        UPDATE ITEM
           SET current_status_code = 'MNT'
         WHERE item_id = v_item_id;

        INSERT INTO ITEM_STATUS_HISTORY (
            item_id, operator_user_id, changed_at, previous_status_code, new_status_code, reason
        ) VALUES (
            v_item_id, p_operator_user_id, CURRENT_TIMESTAMP, v_item_status_code, 'MNT',
            'sp_return_item: 歸還時通報損壞'
        );
    ELSE
        UPDATE ITEM
           SET current_status_code = 'AVL'
         WHERE item_id = v_item_id;

        INSERT INTO ITEM_STATUS_HISTORY (
            item_id, operator_user_id, changed_at, previous_status_code, new_status_code, reason
        ) VALUES (
            v_item_id, p_operator_user_id, CURRENT_TIMESTAMP, v_item_status_code, 'AVL',
            'sp_return_item: 正常歸還'
        );
    END IF;

    COMMIT;
END//

CREATE PROCEDURE sp_open_maintenance_ticket (
    IN p_item_id BIGINT UNSIGNED,
    IN p_reporter_user_id BIGINT UNSIGNED,
    IN p_handler_user_id BIGINT UNSIGNED,
    IN p_issue_description TEXT
)
BEGIN
    DECLARE v_item_type_code CHAR(3);
    DECLARE v_status_code CHAR(3);
    DECLARE v_handler_user_id BIGINT UNSIGNED;
    DECLARE v_open_count INT DEFAULT 0;
    DECLARE v_seq BIGINT UNSIGNED;
    DECLARE v_ticket_code CHAR(10);
    DECLARE v_ticket_id BIGINT UNSIGNED;
    DECLARE v_not_found TINYINT DEFAULT 0;

    DECLARE CONTINUE HANDLER FOR NOT FOUND SET v_not_found = 1;
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        RESIGNAL;
    END;

    START TRANSACTION;

    SET v_not_found = 0;
    SELECT item_type_code, current_status_code, supervisor_user_id
      INTO v_item_type_code, v_status_code, v_handler_user_id
      FROM ITEM
     WHERE item_id = p_item_id
       FOR UPDATE;

    IF v_not_found = 1 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = '查無物品，無法建立維修工單';
    END IF;

    IF v_item_type_code = 'CON' THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'CON 耗材不得建立維修工單';
    END IF;

    IF v_status_code = 'DSP' THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'DSP 報廢物品不得建立維修工單';
    END IF;

    IF p_issue_description IS NULL OR TRIM(p_issue_description) = '' THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = '故障描述不可空白';
    END IF;

    IF p_handler_user_id IS NOT NULL THEN
        SET v_handler_user_id = p_handler_user_id;
    END IF;

    SELECT COUNT(*)
      INTO v_open_count
      FROM USER_ROLE
     WHERE user_id = v_handler_user_id
       AND role_code = 'SUP';

    IF v_open_count = 0 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = '維修處理人必須具有 SUP 角色';
    END IF;

    SELECT COUNT(*)
      INTO v_open_count
      FROM MAINTENANCE_TICKET
     WHERE item_id = p_item_id
       AND current_maintenance_status_code IN ('NEW','ASN','IPR')
       AND archived_at IS NULL;

    IF v_open_count > 0 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = '此物品已有未結案維修工單';
    END IF;

    UPDATE BUSINESS_CODE_SEQUENCE
       SET next_value = LAST_INSERT_ID(next_value + 1)
     WHERE sequence_name = 'TICKET';
    SET v_seq = LAST_INSERT_ID();
    SET v_ticket_code = CONCAT('MNT', LPAD(v_seq, 7, '0'));

    INSERT INTO MAINTENANCE_TICKET (
        ticket_code, item_id, reporter_user_id, assigned_handler_user_id,
        current_maintenance_status_code, reported_at, issue_description
    ) VALUES (
        v_ticket_code, p_item_id, p_reporter_user_id, v_handler_user_id,
        'NEW', CURRENT_TIMESTAMP, p_issue_description
    );

    SET v_ticket_id = LAST_INSERT_ID();

    INSERT INTO MAINTENANCE_ACTION (
        ticket_id, action_type_code, operator_user_id, action_at,
        previous_status_code, new_status_code, action_note
    ) VALUES (
        v_ticket_id, 'CRT', p_reporter_user_id, CURRENT_TIMESTAMP,
        NULL, 'NEW', 'sp_open_maintenance_ticket: 建立工單'
    );

    IF v_status_code <> 'MNT' THEN
        UPDATE ITEM
           SET current_status_code = 'MNT'
         WHERE item_id = p_item_id;

        INSERT INTO ITEM_STATUS_HISTORY (
            item_id, operator_user_id, changed_at, previous_status_code, new_status_code, reason
        ) VALUES (
            p_item_id, p_reporter_user_id, CURRENT_TIMESTAMP, v_status_code, 'MNT',
            'sp_open_maintenance_ticket: 建立維修工單'
        );
    END IF;

    COMMIT;
END//

CREATE PROCEDURE sp_close_maintenance_ticket (
    IN p_ticket_id BIGINT UNSIGNED,
    IN p_operator_user_id BIGINT UNSIGNED,
    IN p_cost_amount DECIMAL(12,0),
    IN p_replaced_part_description TEXT,
    IN p_next_maintenance_date DATE,
    IN p_result TEXT,
    IN p_item_new_status_code CHAR(3)
)
BEGIN
    DECLARE v_item_id BIGINT UNSIGNED;
    DECLARE v_item_status_code CHAR(3);
    DECLARE v_ticket_status_code CHAR(3);
    DECLARE v_not_found TINYINT DEFAULT 0;

    DECLARE CONTINUE HANDLER FOR NOT FOUND SET v_not_found = 1;
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        RESIGNAL;
    END;

    START TRANSACTION;

    SET v_not_found = 0;
    SELECT item_id, current_maintenance_status_code
      INTO v_item_id, v_ticket_status_code
      FROM MAINTENANCE_TICKET
     WHERE ticket_id = p_ticket_id
       FOR UPDATE;

    IF v_not_found = 1 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = '查無維修工單，無法結案';
    END IF;

    SET v_not_found = 0;
    SELECT current_status_code
      INTO v_item_status_code
      FROM ITEM
     WHERE item_id = v_item_id
       FOR UPDATE;

    IF v_not_found = 1 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = '工單對應物品不存在';
    END IF;

    IF v_ticket_status_code IN ('CMP','CAN') THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = '維修工單已結束，不可重複結案';
    END IF;

    IF p_item_new_status_code NOT IN ('AVL','DIS','DSP') THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = '結案後物品狀態只能為 AVL、DIS 或 DSP';
    END IF;

    IF p_cost_amount IS NULL OR p_cost_amount < 0 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = '維修費用不可小於 0';
    END IF;

    IF p_result IS NULL OR TRIM(p_result) = '' THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = '維修結果不可空白';
    END IF;

    IF p_next_maintenance_date IS NOT NULL AND p_next_maintenance_date <= CURRENT_DATE THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = '下次保養日期必須晚於結案日期';
    END IF;

    UPDATE MAINTENANCE_TICKET
       SET current_maintenance_status_code = 'CMP',
           closed_at = CURRENT_TIMESTAMP,
           assigned_handler_user_id = COALESCE(assigned_handler_user_id, p_operator_user_id)
     WHERE ticket_id = p_ticket_id;

    INSERT INTO MAINTENANCE_ACTION (
        ticket_id, action_type_code, operator_user_id, action_at,
        previous_status_code, new_status_code, cost_amount,
        replaced_part_description, next_maintenance_date, action_note
    ) VALUES (
        p_ticket_id, 'CLS', p_operator_user_id, CURRENT_TIMESTAMP,
        v_ticket_status_code, 'CMP', p_cost_amount,
        p_replaced_part_description, p_next_maintenance_date, p_result
    );

    UPDATE ITEM
       SET current_status_code = p_item_new_status_code
     WHERE item_id = v_item_id;

    INSERT INTO ITEM_STATUS_HISTORY (
        item_id, operator_user_id, changed_at, previous_status_code, new_status_code, reason
    ) VALUES (
        v_item_id, p_operator_user_id, CURRENT_TIMESTAMP, v_item_status_code, p_item_new_status_code,
        'sp_close_maintenance_ticket: 維修結案'
    );

    COMMIT;
END//

CREATE PROCEDURE sp_change_item_status (
    IN p_item_id BIGINT UNSIGNED,
    IN p_new_status_code CHAR(3),
    IN p_operator_user_id BIGINT UNSIGNED,
    IN p_reason VARCHAR(200)
)
BEGIN
    DECLARE v_old_status_code CHAR(3);
    DECLARE v_not_found TINYINT DEFAULT 0;

    DECLARE CONTINUE HANDLER FOR NOT FOUND SET v_not_found = 1;
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        RESIGNAL;
    END;

    START TRANSACTION;

    SET v_not_found = 0;
    SELECT current_status_code
      INTO v_old_status_code
      FROM ITEM
     WHERE item_id = p_item_id
       FOR UPDATE;

    IF v_not_found = 1 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = '查無物品，無法異動狀態';
    END IF;

    IF p_reason IS NULL OR TRIM(p_reason) = '' THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = '狀態異動原因不可空白';
    END IF;

    IF v_old_status_code = p_new_status_code THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = '新狀態與目前狀態相同';
    END IF;

    IF v_old_status_code = 'DSP' AND p_new_status_code IN ('AVL','OUT','MNT') THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'DSP 報廢狀態不可改回 AVL、OUT 或 MNT';
    END IF;

    IF p_new_status_code = 'OUT' THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'OUT 借出中狀態只能由 sp_borrow_item 設定';
    END IF;

    IF v_old_status_code = 'OUT' AND p_new_status_code NOT IN ('AVL','MNT','LST') THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'OUT 狀態只能改為 AVL、MNT 或 LST';
    END IF;

    UPDATE ITEM
       SET current_status_code = p_new_status_code
     WHERE item_id = p_item_id;

    INSERT INTO ITEM_STATUS_HISTORY (
        item_id, operator_user_id, changed_at, previous_status_code, new_status_code, reason
    ) VALUES (
        p_item_id, p_operator_user_id, CURRENT_TIMESTAMP, v_old_status_code, p_new_status_code, p_reason
    );

    COMMIT;
END//

CREATE PROCEDURE sp_archive_closed_history (
    IN p_cutoff_date DATE,
    IN p_archive_batch_code CHAR(12)
)
BEGIN
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        RESIGNAL;
    END;

    IF p_cutoff_date IS NULL THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = '封存截止日期不可為空';
    END IF;

    IF p_archive_batch_code IS NULL OR CHAR_LENGTH(p_archive_batch_code) <> 12 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'archive batch code 必須為 CHAR(12)';
    END IF;

    START TRANSACTION;

    UPDATE BORROW_RECORD
       SET archived_at = CURRENT_TIMESTAMP,
           archive_batch_code = p_archive_batch_code
     WHERE archived_at IS NULL
       AND borrow_status_code IN ('RET','CAN')
       AND COALESCE(returned_at, borrowed_at) < p_cutoff_date;

    UPDATE CONSUME_RECORD
       SET archived_at = CURRENT_TIMESTAMP,
           archive_batch_code = p_archive_batch_code
     WHERE archived_at IS NULL
       AND consumed_at < p_cutoff_date;

    UPDATE MAINTENANCE_TICKET
       SET archived_at = CURRENT_TIMESTAMP,
           archive_batch_code = p_archive_batch_code
     WHERE archived_at IS NULL
       AND current_maintenance_status_code IN ('CMP','CAN')
       AND COALESCE(closed_at, reported_at) < p_cutoff_date;

    UPDATE MAINTENANCE_ACTION ma
    JOIN MAINTENANCE_TICKET mt ON ma.ticket_id = mt.ticket_id
       SET ma.archived_at = CURRENT_TIMESTAMP,
           ma.archive_batch_code = p_archive_batch_code
     WHERE ma.archived_at IS NULL
       AND mt.archive_batch_code = p_archive_batch_code;

    UPDATE ITEM_STATUS_HISTORY
       SET archived_at = CURRENT_TIMESTAMP,
           archive_batch_code = p_archive_batch_code
     WHERE archived_at IS NULL
       AND changed_at < p_cutoff_date;

    COMMIT;
END//

DELIMITER ;

/* =========================================================
   6. Triggers
   ========================================================= */

DELIMITER //

CREATE TRIGGER trg_item_before_update_guard
BEFORE UPDATE ON ITEM
FOR EACH ROW
BEGIN
    DECLARE v_subtype_count INT DEFAULT 0;

    IF OLD.current_status_code = 'DSP'
       AND NEW.current_status_code IN ('AVL','OUT','MNT') THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'DSP 報廢物品不可直接改回 AVL、OUT 或 MNT';
    END IF;

    IF OLD.item_type_code <> NEW.item_type_code THEN
        SELECT
            (SELECT COUNT(*) FROM EQUIPMENT_DETAIL WHERE item_id = OLD.item_id) +
            (SELECT COUNT(*) FROM CONTROLLED_ITEM_DETAIL WHERE item_id = OLD.item_id) +
            (SELECT COUNT(*) FROM REUSABLE_ITEM_DETAIL WHERE item_id = OLD.item_id) +
            (SELECT COUNT(*) FROM CONSUMABLE_DETAIL WHERE item_id = OLD.item_id)
        INTO v_subtype_count;

        IF v_subtype_count > 0 THEN
            SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = '已有 subtype 明細的物品不可直接改變 item_type_code';
        END IF;
    END IF;
END//

CREATE TRIGGER trg_equipment_detail_before_insert_check
BEFORE INSERT ON EQUIPMENT_DETAIL
FOR EACH ROW
BEGIN
    DECLARE v_item_type_code CHAR(3);
    DECLARE v_other_count INT DEFAULT 0;

    SELECT item_type_code INTO v_item_type_code FROM ITEM WHERE item_id = NEW.item_id;

    IF v_item_type_code <> 'EQP' THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'EQUIPMENT_DETAIL 只能對應 EQP 物品';
    END IF;

    SELECT
        (SELECT COUNT(*) FROM CONTROLLED_ITEM_DETAIL WHERE item_id = NEW.item_id) +
        (SELECT COUNT(*) FROM REUSABLE_ITEM_DETAIL WHERE item_id = NEW.item_id) +
        (SELECT COUNT(*) FROM CONSUMABLE_DETAIL WHERE item_id = NEW.item_id)
    INTO v_other_count;

    IF v_other_count > 0 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = '每筆 ITEM 只能有一種 subtype 明細';
    END IF;
END//

CREATE TRIGGER trg_equipment_detail_before_update_check
BEFORE UPDATE ON EQUIPMENT_DETAIL
FOR EACH ROW
BEGIN
    DECLARE v_item_type_code CHAR(3);

    SELECT item_type_code INTO v_item_type_code FROM ITEM WHERE item_id = NEW.item_id;

    IF v_item_type_code <> 'EQP' THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'EQUIPMENT_DETAIL 只能對應 EQP 物品';
    END IF;
END//

CREATE TRIGGER trg_controlled_item_detail_before_insert_check
BEFORE INSERT ON CONTROLLED_ITEM_DETAIL
FOR EACH ROW
BEGIN
    DECLARE v_item_type_code CHAR(3);
    DECLARE v_other_count INT DEFAULT 0;

    SELECT item_type_code INTO v_item_type_code FROM ITEM WHERE item_id = NEW.item_id;

    IF v_item_type_code <> 'CTL' THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'CONTROLLED_ITEM_DETAIL 只能對應 CTL 物品';
    END IF;

    SELECT
        (SELECT COUNT(*) FROM EQUIPMENT_DETAIL WHERE item_id = NEW.item_id) +
        (SELECT COUNT(*) FROM REUSABLE_ITEM_DETAIL WHERE item_id = NEW.item_id) +
        (SELECT COUNT(*) FROM CONSUMABLE_DETAIL WHERE item_id = NEW.item_id)
    INTO v_other_count;

    IF v_other_count > 0 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = '每筆 ITEM 只能有一種 subtype 明細';
    END IF;
END//

CREATE TRIGGER trg_controlled_item_detail_before_update_check
BEFORE UPDATE ON CONTROLLED_ITEM_DETAIL
FOR EACH ROW
BEGIN
    DECLARE v_item_type_code CHAR(3);

    SELECT item_type_code INTO v_item_type_code FROM ITEM WHERE item_id = NEW.item_id;

    IF v_item_type_code <> 'CTL' THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'CONTROLLED_ITEM_DETAIL 只能對應 CTL 物品';
    END IF;
END//

CREATE TRIGGER trg_reusable_item_detail_before_insert_check
BEFORE INSERT ON REUSABLE_ITEM_DETAIL
FOR EACH ROW
BEGIN
    DECLARE v_item_type_code CHAR(3);
    DECLARE v_other_count INT DEFAULT 0;

    SELECT item_type_code INTO v_item_type_code FROM ITEM WHERE item_id = NEW.item_id;

    IF v_item_type_code <> 'RUS' THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'REUSABLE_ITEM_DETAIL 只能對應 RUS 物品';
    END IF;

    SELECT
        (SELECT COUNT(*) FROM EQUIPMENT_DETAIL WHERE item_id = NEW.item_id) +
        (SELECT COUNT(*) FROM CONTROLLED_ITEM_DETAIL WHERE item_id = NEW.item_id) +
        (SELECT COUNT(*) FROM CONSUMABLE_DETAIL WHERE item_id = NEW.item_id)
    INTO v_other_count;

    IF v_other_count > 0 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = '每筆 ITEM 只能有一種 subtype 明細';
    END IF;
END//

CREATE TRIGGER trg_reusable_item_detail_before_update_check
BEFORE UPDATE ON REUSABLE_ITEM_DETAIL
FOR EACH ROW
BEGIN
    DECLARE v_item_type_code CHAR(3);

    SELECT item_type_code INTO v_item_type_code FROM ITEM WHERE item_id = NEW.item_id;

    IF v_item_type_code <> 'RUS' THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'REUSABLE_ITEM_DETAIL 只能對應 RUS 物品';
    END IF;
END//

CREATE TRIGGER trg_consumable_detail_before_insert_check
BEFORE INSERT ON CONSUMABLE_DETAIL
FOR EACH ROW
BEGIN
    DECLARE v_item_type_code CHAR(3);
    DECLARE v_other_count INT DEFAULT 0;

    SELECT item_type_code INTO v_item_type_code FROM ITEM WHERE item_id = NEW.item_id;

    IF v_item_type_code <> 'CON' THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'CONSUMABLE_DETAIL 只能對應 CON 物品';
    END IF;

    SELECT
        (SELECT COUNT(*) FROM EQUIPMENT_DETAIL WHERE item_id = NEW.item_id) +
        (SELECT COUNT(*) FROM CONTROLLED_ITEM_DETAIL WHERE item_id = NEW.item_id) +
        (SELECT COUNT(*) FROM REUSABLE_ITEM_DETAIL WHERE item_id = NEW.item_id)
    INTO v_other_count;

    IF v_other_count > 0 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = '每筆 ITEM 只能有一種 subtype 明細';
    END IF;
END//

CREATE TRIGGER trg_consumable_detail_before_update_check
BEFORE UPDATE ON CONSUMABLE_DETAIL
FOR EACH ROW
BEGIN
    DECLARE v_item_type_code CHAR(3);

    SELECT item_type_code INTO v_item_type_code FROM ITEM WHERE item_id = NEW.item_id;

    IF v_item_type_code <> 'CON' THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'CONSUMABLE_DETAIL 只能對應 CON 物品';
    END IF;
END//

CREATE TRIGGER trg_borrow_before_insert_check
BEFORE INSERT ON BORROW_RECORD
FOR EACH ROW
BEGIN
    DECLARE v_item_type_code CHAR(3);
    DECLARE v_status_code CHAR(3);
    DECLARE v_is_borrowable CHAR(1) DEFAULT 'Y';
    DECLARE v_open_count INT DEFAULT 0;

    SELECT item_type_code, current_status_code
      INTO v_item_type_code, v_status_code
      FROM ITEM
     WHERE item_id = NEW.item_id;

    IF v_item_type_code = 'CON' THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'CON 耗材不得建立借用紀錄';
    END IF;

    IF NEW.borrow_status_code IN ('ACT','OVD') THEN
        IF v_status_code <> 'AVL' THEN
            SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = '只有 AVL 可用物品可以建立借用紀錄';
        END IF;

        SELECT COUNT(*)
          INTO v_open_count
          FROM BORROW_RECORD
         WHERE item_id = NEW.item_id
           AND borrow_status_code IN ('ACT','OVD')
           AND returned_at IS NULL;

        IF v_open_count > 0 THEN
            SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = '此物品已有未歸還借用紀錄';
        END IF;
    END IF;

    IF v_item_type_code = 'RUS' THEN
        SELECT is_borrowable
          INTO v_is_borrowable
          FROM REUSABLE_ITEM_DETAIL
         WHERE item_id = NEW.item_id;

        IF v_is_borrowable <> 'Y' THEN
            SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = '此 RUS 物品設定為不可借用';
        END IF;
    END IF;
END//

CREATE TRIGGER trg_borrow_before_update_check
BEFORE UPDATE ON BORROW_RECORD
FOR EACH ROW
BEGIN
    IF NEW.returned_at IS NOT NULL AND NEW.returned_at < NEW.borrowed_at THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = '實際歸還時間不可早於借用時間';
    END IF;
END//

CREATE TRIGGER trg_consume_before_insert_check
BEFORE INSERT ON CONSUME_RECORD
FOR EACH ROW
BEGIN
    DECLARE v_item_type_code CHAR(3);

    SELECT item_type_code
      INTO v_item_type_code
      FROM ITEM
     WHERE item_id = NEW.item_id;

    IF v_item_type_code <> 'CON' THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = '只有 CON 耗材可以建立領用紀錄';
    END IF;

    IF NEW.amount <= 0 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = '領用數量必須大於 0';
    END IF;
END//

CREATE TRIGGER trg_maintenance_ticket_before_insert_check
BEFORE INSERT ON MAINTENANCE_TICKET
FOR EACH ROW
BEGIN
    DECLARE v_item_type_code CHAR(3);
    DECLARE v_status_code CHAR(3);
    DECLARE v_open_count INT DEFAULT 0;

    SELECT item_type_code, current_status_code
      INTO v_item_type_code, v_status_code
      FROM ITEM
     WHERE item_id = NEW.item_id;

    IF v_item_type_code = 'CON' THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'CON 耗材不得建立維修工單';
    END IF;

    IF v_status_code = 'DSP' THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'DSP 報廢物品不得建立維修工單';
    END IF;

    IF NEW.current_maintenance_status_code IN ('NEW','ASN','IPR') THEN
        SELECT COUNT(*)
          INTO v_open_count
          FROM MAINTENANCE_TICKET
         WHERE item_id = NEW.item_id
           AND current_maintenance_status_code IN ('NEW','ASN','IPR')
           AND archived_at IS NULL;

        IF v_open_count > 0 THEN
            SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = '此物品已有未結案維修工單';
        END IF;
    END IF;
END//

CREATE TRIGGER trg_maintenance_ticket_before_update_check
BEFORE UPDATE ON MAINTENANCE_TICKET
FOR EACH ROW
BEGIN
    IF NEW.closed_at IS NOT NULL AND NEW.closed_at < NEW.reported_at THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = '維修結案時間不可早於報修時間';
    END IF;
END//

DELIMITER ;

/* =========================================================
   7. Code table data
   ========================================================= */

INSERT INTO ROLE_CODE (role_code, role_name, role_description) VALUES
('ADM', '系所管理員', '建立物品、盤點、庫存管理、停用與報廢管理'),
('MEM', '一般師生使用者', '查詢、借用、領用與報修'),
('SUP', '空間/設備負責人', '查看並處理被指派之維修工單');

INSERT INTO ITEM_TYPE_CODE (item_type_code, type_name, type_description) VALUES
('EQP', '設備', '單價 >= 10000，耐用、可重複使用，需財產編號'),
('CTL', '列管耐用品', '單價 >= 3000 且 < 10000，耐用、可重複使用，需系所列管編號'),
('RUS', '非列管可重複使用物品', '單價 < 3000 且可重複使用，可設定是否可借用與是否需歸還'),
('CON', '耗材', '使用後消耗、不可歸還、以數量庫存管理');

INSERT INTO ITEM_STATUS_CODE (item_status_code, status_name, status_description) VALUES
('AVL', '可用', '可借用或可領用'),
('OUT', '借出中', '目前有未歸還借用紀錄'),
('MNT', '維修中', '維修或檢修處理中'),
('DIS', '停用', '暫停使用，不可借用'),
('DSP', '報廢', '已報廢，不可借用或維修'),
('LST', '遺失', '盤點或借用後未尋獲');

INSERT INTO BORROW_STATUS_CODE (borrow_status_code, status_name, status_description) VALUES
('ACT', '借用中', '尚未歸還'),
('RET', '已歸還', '已完成歸還'),
('OVD', '逾期', '超過預計歸還時間且未歸還'),
('CAN', '取消', '借用紀錄取消');

INSERT INTO MAINTENANCE_STATUS_CODE (maintenance_status_code, status_name, status_description) VALUES
('NEW', '待處理', '新建立工單，尚未開始'),
('ASN', '已指派', '已指派處理人'),
('IPR', '處理中', '維修處理中'),
('CMP', '已完成', '維修或處理完成'),
('CAN', '取消', '工單取消');

INSERT INTO SPACE_TYPE_CODE (space_type_code, type_name, type_description) VALUES
('LAB', '實驗室', '教學、研究或專題實驗室'),
('CLS', '教室', '一般教室或多媒體教室'),
('OFF', '辦公室', '系辦或教師辦公空間'),
('STO', '儲藏室', '物品或耗材儲藏空間');

INSERT INTO MAINTENANCE_ACTION_TYPE_CODE (action_type_code, action_type_name, action_type_description) VALUES
('CRT', '建立工單', '建立維修工單主檔'),
('ASN', '指派處理人', '指派或變更處理人'),
('UPD', '處理更新', '維修處理進度更新'),
('VND', '委外維修', '交由外部廠商處理'),
('RPL', '更換零件', '記錄零件更換'),
('CLS', '結案', '維修工單結案');

INSERT INTO BUSINESS_CODE_SEQUENCE (sequence_name, next_value) VALUES
('BORROW', 10),
('CONSUME', 10),
('TICKET', 10);

/* =========================================================
   8. Sample data
   ========================================================= */

INSERT INTO APP_USER (user_code, user_name, email, phone, created_at) VALUES
('U0000001', '林佳蓉', 'admin01@example.edu.tw', '0912-000-001', '2025-09-01 08:00:00'),
('U0000002', '陳柏宇', 'supervisor01@example.edu.tw', '0912-000-002', '2025-09-01 08:00:00'),
('U0000003', '王小明', 'student01@example.edu.tw', '0912-000-003', '2025-09-01 08:00:00'),
('U0000004', '李雅婷', 'student02@example.edu.tw', '0912-000-004', '2025-09-01 08:00:00'),
('U0000005', '張志豪', 'student03@example.edu.tw', '0912-000-005', '2025-09-01 08:00:00'),
('U0000006', '黃怡君', 'student04@example.edu.tw', '0912-000-006', '2025-09-01 08:00:00'),
('U0000007', '劉冠廷', 'student05@example.edu.tw', '0912-000-007', '2025-09-01 08:00:00'),
('U0000008', '蔡佩珊', 'student06@example.edu.tw', '0912-000-008', '2025-09-01 08:00:00'),
('U0000009', '吳承恩', 'student07@example.edu.tw', '0912-000-009', '2025-09-01 08:00:00'),
('U0000010', '鄭宇翔', 'student08@example.edu.tw', '0912-000-010', '2025-09-01 08:00:00');

INSERT INTO USER_ROLE (user_id, role_code) VALUES
(1, 'ADM'), (1, 'MEM'),
(2, 'SUP'), (2, 'MEM'),
(3, 'MEM'), (4, 'MEM'), (5, 'MEM'), (6, 'MEM'), (7, 'MEM'),
(8, 'MEM'), (9, 'MEM'), (10, 'MEM');

INSERT INTO SPACE (space_code, space_name, space_type_code, building_name, room_no, is_active) VALUES
('SPC001', '系辦公室', 'OFF', '資訊館', '201', 'Y'),
('SPC002', '資工系儲藏室 A', 'STO', '資訊館', 'B101', 'Y'),
('SPC003', '普通教室 101', 'CLS', '教學大樓', '101', 'Y'),
('SPC004', '普通教室 102', 'CLS', '教學大樓', '102', 'Y'),
('SPC005', '網路實驗室', 'LAB', '資訊館', '301', 'Y'),
('SPC006', '嵌入式系統實驗室', 'LAB', '資訊館', '302', 'Y'),
('SPC007', '人工智慧實驗室', 'LAB', '資訊館', '401', 'Y'),
('SPC008', '多媒體教室', 'CLS', '教學大樓', '201', 'Y'),
('SPC009', '教授專題實驗室', 'LAB', '資訊館', '501', 'Y'),
('SPC010', '系辦物資櫃', 'STO', '資訊館', '201-A', 'Y');

INSERT INTO VENDOR (vendor_code, vendor_name, contact_name, phone, email, is_active) VALUES
('VND00001', '宏達資訊維修', '許先生', '02-2345-1001', 'service01@example.com', 'Y'),
('VND00002', '聯科儀器服務', '周小姐', '02-2345-1002', 'service02@example.com', 'Y'),
('VND00003', '北區電腦維護', '鄭先生', '02-2345-1003', 'service03@example.com', 'Y'),
('VND00004', '精準投影設備', '林先生', '02-2345-1004', 'service04@example.com', 'Y'),
('VND00005', '雲端伺服器顧問', '陳小姐', '02-2345-1005', 'service05@example.com', 'Y'),
('VND00006', '創客電子材料', '何先生', '02-2345-1006', 'service06@example.com', 'Y'),
('VND00007', '展新網通工程', '邱小姐', '02-2345-1007', 'service07@example.com', 'Y'),
('VND00008', '教學設備整合', '高先生', '02-2345-1008', 'service08@example.com', 'Y'),
('VND00009', '校園事務機維護', '黃小姐', '02-2345-1009', 'service09@example.com', 'Y'),
('VND00010', '實驗室安全檢修', '羅先生', '02-2345-1010', 'service10@example.com', 'Y');

INSERT INTO ITEM (
    item_code, item_name, item_type_code, current_status_code,
    current_space_id, supervisor_user_id, created_by_user_id,
    created_at, warranty_expiry_date, archived_at
) VALUES
('EQP0000001', '高階 GPU 伺服器', 'EQP', 'AVL', 5, 2, 1, '2024-01-15 09:00:00', '2027-12-31', NULL),
('EQP0000002', '雷射投影機', 'EQP', 'AVL', 8, 2, 1, '2024-02-10 09:00:00', '2026-11-30', NULL),
('EQP0000003', '網路交換器', 'EQP', 'AVL', 5, 2, 1, '2024-03-12 09:00:00', '2026-06-30', NULL),
('EQP0000004', '3D 印表機', 'EQP', 'AVL', 6, 2, 1, '2023-08-20 09:00:00', '2025-12-31', NULL),
('EQP0000005', '高階示波器', 'EQP', 'AVL', 6, 2, 1, '2024-04-01 09:00:00', '2028-05-31', NULL),
('EQP0000006', '老舊投影機', 'EQP', 'DIS', 2, 2, 1, '2018-05-18 09:00:00', '2024-12-31', NULL),
('EQP0000007', '報廢筆記型電腦', 'EQP', 'DSP', 2, 2, 1, '2017-06-21 09:00:00', '2023-12-31', NULL),
('EQP0000008', '攝影機套組', 'EQP', 'AVL', 8, 2, 1, '2024-07-08 09:00:00', '2027-09-30', NULL),
('EQP0000009', 'NAS 儲存設備', 'EQP', 'AVL', 5, 2, 1, '2024-09-10 09:00:00', '2027-03-31', NULL),
('EQP0000010', '遺失平板電腦', 'EQP', 'LST', 2, 2, 1, '2023-10-05 09:00:00', '2026-01-31', NULL),

('CTL0000001', '文件投影機推車', 'CTL', 'AVL', 8, 2, 1, '2025-01-10 09:00:00', '2027-01-10', NULL),
('CTL0000002', '可攜式擴音機', 'CTL', 'AVL', 1, 2, 1, '2025-01-12 09:00:00', '2027-01-12', NULL),
('CTL0000003', '實驗室 UPS', 'CTL', 'AVL', 5, 2, 1, '2025-02-01 09:00:00', '2027-02-01', NULL),
('CTL0000004', '網路測線器', 'CTL', 'AVL', 5, 2, 1, '2025-02-05 09:00:00', '2027-02-05', NULL),
('CTL0000005', '教學錄音筆', 'CTL', 'AVL', 1, 2, 1, '2025-02-20 09:00:00', '2027-02-20', NULL),
('CTL0000006', '實驗室除濕機', 'CTL', 'DIS', 6, 2, 1, '2023-06-01 09:00:00', '2025-06-01', NULL),
('CTL0000007', '多媒體控制盒', 'CTL', 'AVL', 8, 2, 1, '2025-03-15 09:00:00', '2027-03-15', NULL),
('CTL0000008', '行動硬碟陣列', 'CTL', 'AVL', 7, 2, 1, '2025-04-05 09:00:00', '2027-04-05', NULL),
('CTL0000009', '教室無線麥克風組', 'CTL', 'AVL', 8, 2, 1, '2025-04-20 09:00:00', '2027-04-20', NULL),
('CTL0000010', '停用條碼掃描器', 'CTL', 'DIS', 2, 2, 1, '2022-09-10 09:00:00', '2024-09-10', NULL),

('RUS0000001', '簡報筆 A', 'RUS', 'AVL', 1, 2, 1, '2025-09-01 09:00:00', NULL, NULL),
('RUS0000002', 'HDMI 轉接頭 A', 'RUS', 'AVL', 1, 2, 1, '2025-09-01 09:00:00', NULL, NULL),
('RUS0000003', 'ESP32 開發板', 'RUS', 'AVL', 6, 2, 1, '2025-09-01 09:00:00', NULL, NULL),
('RUS0000004', 'Arduino 教學套件', 'RUS', 'AVL', 6, 2, 1, '2025-09-01 09:00:00', NULL, NULL),
('RUS0000005', '系辦推車', 'RUS', 'AVL', 1, 2, 1, '2025-09-01 09:00:00', NULL, NULL),
('RUS0000006', '行動白板', 'RUS', 'AVL', 3, 2, 1, '2025-09-01 09:00:00', NULL, NULL),
('RUS0000007', '舊款 USB Hub', 'RUS', 'DIS', 2, 2, 1, '2025-09-01 09:00:00', NULL, NULL),
('RUS0000008', '教學麥克風', 'RUS', 'AVL', 8, 2, 1, '2025-09-01 09:00:00', NULL, NULL),
('RUS0000009', '內部測試線材箱', 'RUS', 'AVL', 2, 2, 1, '2025-09-01 09:00:00', NULL, NULL),
('RUS0000010', '基礎維修工具箱', 'RUS', 'AVL', 6, 2, 1, '2025-09-01 09:00:00', NULL, NULL),

('CON0000001', '白板筆', 'CON', 'AVL', 10, 2, 1, '2025-09-01 09:00:00', NULL, NULL),
('CON0000002', '影印紙', 'CON', 'AVL', 10, 2, 1, '2025-09-01 09:00:00', NULL, NULL),
('CON0000003', '麵包板跳線', 'CON', 'AVL', 6, 2, 1, '2025-09-01 09:00:00', NULL, NULL),
('CON0000004', '電阻包', 'CON', 'AVL', 6, 2, 1, '2025-09-01 09:00:00', NULL, NULL),
('CON0000005', 'A4 標籤紙', 'CON', 'AVL', 10, 2, 1, '2025-09-01 09:00:00', NULL, NULL),
('CON0000006', '酒精棉片', 'CON', 'AVL', 2, 2, 1, '2025-09-01 09:00:00', NULL, NULL),
('CON0000007', '焊錫線', 'CON', 'AVL', 6, 2, 1, '2025-09-01 09:00:00', NULL, NULL),
('CON0000008', '杜邦線', 'CON', 'AVL', 6, 2, 1, '2025-09-01 09:00:00', NULL, NULL),
('CON0000009', '熱縮套管', 'CON', 'AVL', 6, 2, 1, '2025-09-01 09:00:00', NULL, NULL),
('CON0000010', '過期清潔劑', 'CON', 'DSP', 2, 2, 1, '2025-09-01 09:00:00', NULL, NULL);

INSERT INTO EQUIPMENT_DETAIL (item_id, property_tag_no, acquisition_date, acquisition_amount, lifespan_years, fund_source, custodian_user_id) VALUES
(1, 'P202400001', '2024-01-15', 180000, 5, '教育部教學設備補助', 1),
(2, 'P202400002', '2024-02-10', 45000, 5, '系所設備費', 1),
(3, 'P202400003', '2024-03-12', 38000, 5, '網路建置經費', 2),
(4, 'P202400004', '2023-08-20', 62000, 5, '實驗室設備費', 2),
(5, 'P202400005', '2024-04-01', 95000, 8, '教學卓越計畫', 2),
(6, 'P201800006', '2018-05-18', 32000, 5, '系所設備費', 1),
(7, 'P201700007', '2017-06-21', 35000, 5, '專題實驗室經費', 1),
(8, 'P202400008', '2024-07-08', 52000, 5, '多媒體教學經費', 2),
(9, 'P202400009', '2024-09-10', 70000, 5, '系所研究設備費', 2),
(10, 'P202300010', '2023-10-05', 18000, 4, '行動學習計畫', 1);

INSERT INTO CONTROLLED_ITEM_DETAIL (item_id, control_tag_no, acquisition_date, acquisition_amount, custodian_user_id) VALUES
(11, 'C202500001', '2025-01-10', 8500, 1),
(12, 'C202500002', '2025-01-12', 6200, 1),
(13, 'C202500003', '2025-02-01', 9200, 2),
(14, 'C202500004', '2025-02-05', 4800, 2),
(15, 'C202500005', '2025-02-20', 3600, 1),
(16, 'C202300006', '2023-06-01', 7800, 2),
(17, 'C202500007', '2025-03-15', 9700, 2),
(18, 'C202500008', '2025-04-05', 6500, 2),
(19, 'C202500009', '2025-04-20', 5400, 2),
(20, 'C202200010', '2022-09-10', 4300, 1);

INSERT INTO REUSABLE_ITEM_DETAIL (item_id, specification, is_borrowable, need_return) VALUES
(21, '2.4GHz 簡報筆，含雷射指示', 'Y', 'Y'),
(22, 'HDMI to Type-C 轉接頭', 'Y', 'Y'),
(23, 'ESP32 DevKit 開發板', 'Y', 'Y'),
(24, 'Arduino Uno 教學套件', 'Y', 'Y'),
(25, '折疊式系辦推車', 'Y', 'Y'),
(26, '可移動雙面白板', 'Y', 'Y'),
(27, 'USB 2.0 Hub 四埠，狀態不穩定', 'N', 'Y'),
(28, '無線教學麥克風', 'Y', 'Y'),
(29, '測試線材箱，不開放外借', 'N', 'Y'),
(30, '基礎維修工具箱', 'Y', 'Y');

INSERT INTO CONSUMABLE_DETAIL (item_id, stock_quantity, min_stock_quantity, unit_name) VALUES
(31, 80, 20, '支'),
(32, 5, 10, '包'),
(33, 120, 30, '條'),
(34, 0, 5, '包'),
(35, 25, 10, '包'),
(36, 8, 8, '盒'),
(37, 15, 5, '捲'),
(38, 100, 30, '條'),
(39, 40, 10, '包'),
(40, 3, 5, '瓶');

INSERT INTO CONSUME_RECORD (consume_code, item_id, consumer_user_id, consumed_at, amount, purpose) VALUES
('CSM0000001', 31, 3, '2026-01-05 09:10:00', 2, '教室白板書寫'),
('CSM0000002', 32, 4, '2026-01-06 10:20:00', 1, '課程講義列印'),
('CSM0000003', 33, 5, '2026-01-07 13:30:00', 20, '嵌入式系統實驗'),
('CSM0000004', 35, 6, '2026-01-08 11:15:00', 2, '文件標籤整理'),
('CSM0000005', 36, 7, '2026-01-09 14:40:00', 1, '實驗器材清潔'),
('CSM0000006', 37, 8, '2026-01-10 15:00:00', 1, '焊接練習'),
('CSM0000007', 38, 9, '2026-01-11 16:05:00', 15, '電路實作課'),
('CSM0000008', 39, 10, '2026-01-12 09:45:00', 5, '線材保護'),
('CSM0000009', 31, 4, '2026-01-13 10:30:00', 3, '研討教室使用'),
('CSM0000010', 33, 6, '2026-01-14 13:10:00', 10, '專題實作');

INSERT INTO BORROW_RECORD (borrow_code, item_id, borrower_user_id, borrowed_at, expected_return_at, returned_at, borrow_status_code, purpose) VALUES
('BRW0000001', 1, 3, '2025-12-01 09:00:00', '2025-12-03 17:00:00', '2025-12-03 15:30:00', 'RET', '深度學習課程測試'),
('BRW0000002', 2, 4, '2025-12-02 10:00:00', '2025-12-02 18:00:00', '2025-12-02 17:20:00', 'RET', '專題成果展示'),
('BRW0000003', 5, 6, '2025-12-06 13:00:00', '2025-12-07 17:00:00', '2025-12-07 16:50:00', 'RET', '電子電路實驗'),
('BRW0000004', 8, 7, '2025-12-08 11:00:00', '2025-12-09 17:00:00', '2025-12-09 16:30:00', 'RET', '教學錄影'),
('BRW0000005', 9, 8, '2025-12-10 09:00:00', '2025-12-11 17:00:00', '2025-12-11 14:40:00', 'RET', '資料備份測試'),
('BRW0000006', 21, 9, '2025-12-12 08:30:00', '2025-12-12 18:00:00', '2025-12-12 17:00:00', 'RET', '課堂簡報'),
('BRW0000007', 22, 10, '2025-12-13 10:00:00', '2025-12-13 18:00:00', '2025-12-13 17:40:00', 'RET', '教室投影轉接'),
('BRW0000008', 23, 3, '2025-12-14 09:20:00', '2025-12-15 17:00:00', '2025-12-15 16:00:00', 'RET', '物聯網實作'),
('BRW0000009', 25, 4, '2025-12-16 09:00:00', '2025-12-16 12:00:00', '2025-12-16 11:50:00', 'RET', '搬運課程材料'),
('BRW0000010', 3, 5, '2026-06-20 09:00:00', '2026-06-25 17:00:00', NULL, 'ACT', '網路課程臨時教學');

UPDATE ITEM SET current_status_code = 'OUT' WHERE item_id = 3;

INSERT INTO MAINTENANCE_TICKET (
    ticket_code, item_id, reporter_user_id, assigned_handler_user_id,
    current_maintenance_status_code, reported_at, issue_description, closed_at
) VALUES
('MNT0000001', 4, 3, 2, 'NEW', '2026-01-05 10:00:00', '3D 印表機噴頭堵塞', NULL),
('MNT0000002', 24, 4, 2, 'IPR', '2026-01-06 11:30:00', 'Arduino 套件缺少連接線', NULL),
('MNT0000003', 1, 5, 2, 'CMP', '2025-11-01 09:00:00', '伺服器風扇異音', '2025-11-02 16:00:00'),
('MNT0000004', 2, 6, 2, 'CMP', '2025-11-03 10:30:00', '投影亮度偏暗', '2025-11-04 14:20:00'),
('MNT0000005', 6, 7, 2, 'CMP', '2025-11-05 15:00:00', '舊投影機無法開機', '2025-11-06 13:00:00'),
('MNT0000006', 27, 8, 2, 'CMP', '2025-11-07 09:40:00', 'USB Hub 接觸不良', '2025-11-07 16:00:00'),
('MNT0000007', 10, 9, 2, 'CAN', '2025-11-08 13:20:00', '平板設備疑似遺失', NULL),
('MNT0000008', 21, 10, 2, 'CMP', '2025-11-09 10:10:00', '簡報筆按鍵不靈敏', '2025-11-09 15:30:00'),
('MNT0000009', 22, 3, 2, 'CMP', '2025-11-10 14:00:00', '轉接頭影像不穩', '2025-11-10 17:00:00'),
('MNT0000010', 23, 4, 2, 'CMP', '2025-11-11 09:50:00', '開發板燒錄失敗', '2025-11-12 11:40:00');

UPDATE ITEM SET current_status_code = 'MNT' WHERE item_id IN (4, 24);

INSERT INTO MAINTENANCE_ACTION (
    ticket_id, action_type_code, operator_user_id, vendor_id, action_at,
    previous_status_code, new_status_code, cost_amount,
    replaced_part_description, next_maintenance_date, action_note
) VALUES
(1, 'CRT', 3, NULL, '2026-01-05 10:00:00', NULL, 'NEW', NULL, NULL, NULL, '學生通報 3D 印表機噴頭堵塞'),
(2, 'CRT', 4, NULL, '2026-01-06 11:30:00', NULL, 'NEW', NULL, NULL, NULL, '學生通報 Arduino 套件缺少連接線'),
(2, 'UPD', 2, NULL, '2026-01-06 15:00:00', 'NEW', 'IPR', NULL, NULL, NULL, '已盤點套件內容並等待補線'),
(3, 'CRT', 5, NULL, '2025-11-01 09:00:00', NULL, 'NEW', NULL, NULL, NULL, '建立伺服器風扇異音工單'),
(3, 'VND', 2, 5, '2025-11-01 14:00:00', 'NEW', 'IPR', NULL, NULL, NULL, '委外檢測散熱模組'),
(3, 'CLS', 2, 5, '2025-11-02 16:00:00', 'IPR', 'CMP', 2500, '散熱風扇', '2026-05-02', '已更換風扇並完成壓力測試'),
(4, 'CRT', 6, NULL, '2025-11-03 10:30:00', NULL, 'NEW', NULL, NULL, NULL, '建立投影亮度偏暗工單'),
(4, 'CLS', 2, 4, '2025-11-04 14:20:00', 'IPR', 'CMP', 1800, '燈泡模組', '2026-05-04', '已更換燈泡模組'),
(5, 'CRT', 7, NULL, '2025-11-05 15:00:00', NULL, 'NEW', NULL, NULL, NULL, '建立舊投影機無法開機工單'),
(5, 'CLS', 2, 4, '2025-11-06 13:00:00', 'IPR', 'CMP', 0, NULL, '2026-05-06', '判定維修效益低，建議停用'),
(6, 'CRT', 8, NULL, '2025-11-07 09:40:00', NULL, 'NEW', NULL, NULL, NULL, '建立 USB Hub 接觸不良工單'),
(6, 'CLS', 2, 3, '2025-11-07 16:00:00', 'IPR', 'CMP', 300, 'USB 線材', '2026-05-07', '完成線材更換'),
(7, 'CRT', 9, NULL, '2025-11-08 13:20:00', NULL, 'NEW', NULL, NULL, NULL, '建立平板疑似遺失工單'),
(7, 'CLS', 2, NULL, '2025-11-08 13:40:00', 'NEW', 'CAN', 0, NULL, NULL, '改列遺失流程追蹤'),
(8, 'CRT', 10, NULL, '2025-11-09 10:10:00', NULL, 'NEW', NULL, NULL, NULL, '建立簡報筆按鍵不靈敏工單'),
(8, 'CLS', 2, 8, '2025-11-09 15:30:00', 'IPR', 'CMP', 200, '按鍵模組', '2026-05-09', '已清潔並更換按鍵'),
(9, 'CRT', 3, NULL, '2025-11-10 14:00:00', NULL, 'NEW', NULL, NULL, NULL, '建立轉接頭影像不穩工單'),
(9, 'CLS', 2, 8, '2025-11-10 17:00:00', 'IPR', 'CMP', 150, NULL, '2026-05-10', '測試後恢復正常'),
(10, 'CRT', 4, NULL, '2025-11-11 09:50:00', NULL, 'NEW', NULL, NULL, NULL, '建立開發板燒錄失敗工單'),
(10, 'CLS', 2, 6, '2025-11-12 11:40:00', 'IPR', 'CMP', 500, 'USB 介面晶片', '2026-05-12', '已更換並測試完成');

INSERT INTO ITEM_STATUS_HISTORY (item_id, operator_user_id, changed_at, previous_status_code, new_status_code, reason) VALUES
(3, 5, '2026-06-20 09:00:00', 'AVL', 'OUT', 'BRW0000010 借用建立'),
(4, 3, '2026-01-05 10:05:00', 'AVL', 'MNT', 'MNT0000001 建立維修工單'),
(24, 4, '2026-01-06 11:35:00', 'AVL', 'MNT', 'MNT0000002 建立維修工單'),
(6, 1, '2025-11-06 13:10:00', 'MNT', 'DIS', '維修效益過低，先停用'),
(7, 1, '2025-10-01 09:00:00', 'DIS', 'DSP', '已達報廢條件'),
(10, 1, '2025-11-08 13:30:00', 'AVL', 'LST', '盤點時未尋獲'),
(27, 2, '2025-11-07 16:10:00', 'MNT', 'DIS', '設備狀況不穩定'),
(40, 1, '2025-10-15 09:10:00', 'AVL', 'DSP', '耗材過期'),
(1, 2, '2025-11-02 16:05:00', 'MNT', 'AVL', '維修完成'),
(2, 2, '2025-11-04 14:30:00', 'MNT', 'AVL', '更換燈泡完成'),
(21, 2, '2025-11-09 15:40:00', 'MNT', 'AVL', '按鍵維修完成');

/* =========================================================
   9. Views
   ========================================================= */

CREATE OR REPLACE VIEW vw_Login_User_Role AS
SELECT
    u.user_id,
    u.user_code,
    u.user_name,
    u.email,
    ur.role_code,
    rc.role_name,
    CASE ur.role_code
        WHEN 'ADM' THEN 1
        WHEN 'SUP' THEN 2
        ELSE 3
    END AS role_priority
FROM APP_USER u
JOIN USER_ROLE ur ON u.user_id = ur.user_id
JOIN ROLE_CODE rc ON ur.role_code = rc.role_code;

CREATE OR REPLACE VIEW vw_Student_Available_Borrowable_Items AS
SELECT
    i.item_id,
    i.item_code,
    i.item_name,
    i.item_type_code,
    it.type_name AS item_type_name,
    i.current_status_code,
    isc.status_name AS current_status_name,
    s.space_id,
    s.space_code,
    s.space_name,
    st.type_name AS space_type_name,
    rid.specification,
    rid.need_return
FROM ITEM i
JOIN ITEM_TYPE_CODE it ON i.item_type_code = it.item_type_code
JOIN ITEM_STATUS_CODE isc ON i.current_status_code = isc.item_status_code
JOIN SPACE s ON i.current_space_id = s.space_id
JOIN SPACE_TYPE_CODE st ON s.space_type_code = st.space_type_code
LEFT JOIN REUSABLE_ITEM_DETAIL rid ON i.item_id = rid.item_id
WHERE i.archived_at IS NULL
  AND i.current_status_code = 'AVL'
  AND i.item_type_code IN ('EQP','CTL','RUS')
  AND (i.item_type_code <> 'RUS' OR rid.is_borrowable = 'Y');

CREATE OR REPLACE VIEW vw_Student_Available_Consumables AS
SELECT
    i.item_id,
    i.item_code,
    i.item_name,
    i.item_type_code,
    it.type_name AS item_type_name,
    i.current_status_code,
    isc.status_name AS current_status_name,
    s.space_id,
    s.space_code,
    s.space_name,
    st.type_name AS space_type_name,
    cd.stock_quantity,
    cd.unit_name
FROM ITEM i
JOIN ITEM_TYPE_CODE it ON i.item_type_code = it.item_type_code
JOIN ITEM_STATUS_CODE isc ON i.current_status_code = isc.item_status_code
JOIN CONSUMABLE_DETAIL cd ON i.item_id = cd.item_id
JOIN SPACE s ON i.current_space_id = s.space_id
JOIN SPACE_TYPE_CODE st ON s.space_type_code = st.space_type_code
WHERE i.archived_at IS NULL
  AND i.item_type_code = 'CON'
  AND i.current_status_code = 'AVL'
  AND cd.stock_quantity > 0;

CREATE OR REPLACE VIEW vw_Student_Current_Borrowed_Items AS
SELECT
    br.borrow_id,
    br.borrow_code,
    br.item_id,
    i.item_code,
    i.item_name,
    i.item_type_code,
    it.type_name AS item_type_name,
    i.current_status_code,
    isc.status_name AS current_status_name,
    s.space_code,
    s.space_name,
    rid.specification,
    rid.need_return,
    br.borrower_user_id,
    u.user_code AS borrower_user_code,
    u.user_name AS borrower_name,
    br.borrowed_at,
    br.expected_return_at,
    br.borrow_status_code,
    bsc.status_name AS borrow_status_name
FROM BORROW_RECORD br
JOIN ITEM i ON br.item_id = i.item_id
JOIN ITEM_TYPE_CODE it ON i.item_type_code = it.item_type_code
JOIN ITEM_STATUS_CODE isc ON i.current_status_code = isc.item_status_code
JOIN BORROW_STATUS_CODE bsc ON br.borrow_status_code = bsc.borrow_status_code
JOIN SPACE s ON i.current_space_id = s.space_id
JOIN APP_USER u ON br.borrower_user_id = u.user_id
LEFT JOIN REUSABLE_ITEM_DETAIL rid ON i.item_id = rid.item_id
WHERE br.archived_at IS NULL
  AND br.borrow_status_code IN ('ACT','OVD')
  AND br.returned_at IS NULL;

CREATE OR REPLACE VIEW vw_Student_Maintenance_Reportable_Items AS
SELECT
    i.item_id,
    i.item_code,
    i.item_name,
    i.item_type_code,
    it.type_name AS item_type_name,
    i.current_status_code,
    isc.status_name AS current_status_name,
    i.warranty_expiry_date,
    s.space_code,
    s.space_name,
    st.type_name AS space_type_name
FROM ITEM i
JOIN ITEM_TYPE_CODE it ON i.item_type_code = it.item_type_code
JOIN ITEM_STATUS_CODE isc ON i.current_status_code = isc.item_status_code
JOIN SPACE s ON i.current_space_id = s.space_id
JOIN SPACE_TYPE_CODE st ON s.space_type_code = st.space_type_code
WHERE i.archived_at IS NULL
  AND i.item_type_code IN ('EQP','CTL','RUS')
  AND i.current_status_code <> 'DSP'
  AND NOT EXISTS (
      SELECT 1
      FROM MAINTENANCE_TICKET mt
      WHERE mt.item_id = i.item_id
        AND mt.current_maintenance_status_code IN ('NEW','ASN','IPR')
        AND mt.archived_at IS NULL
  );

CREATE OR REPLACE VIEW vw_Student_Maintenance_Handlers AS
SELECT
    u.user_id AS handler_user_id,
    u.user_code AS handler_user_code,
    u.user_name AS handler_name
FROM APP_USER u
JOIN USER_ROLE ur ON u.user_id = ur.user_id
WHERE ur.role_code = 'SUP';

CREATE OR REPLACE VIEW vw_Supervisor_Assigned_Maintenance_Active AS
SELECT
    mt.ticket_id,
    mt.ticket_code,
    mt.item_id,
    i.item_code,
    i.item_name,
    i.current_status_code,
    isc.status_name AS current_status_name,
    s.space_code,
    s.space_name,
    mt.reporter_user_id,
    reporter.user_code AS reporter_user_code,
    reporter.user_name AS reporter_name,
    mt.assigned_handler_user_id,
    handler.user_code AS handler_user_code,
    handler.user_name AS handler_name,
    mt.current_maintenance_status_code,
    msc.status_name AS maintenance_status_name,
    mt.reported_at,
    mt.issue_description
FROM MAINTENANCE_TICKET mt
JOIN ITEM i ON mt.item_id = i.item_id
JOIN ITEM_STATUS_CODE isc ON i.current_status_code = isc.item_status_code
JOIN SPACE s ON i.current_space_id = s.space_id
JOIN APP_USER reporter ON mt.reporter_user_id = reporter.user_id
LEFT JOIN APP_USER handler ON mt.assigned_handler_user_id = handler.user_id
JOIN MAINTENANCE_STATUS_CODE msc
    ON mt.current_maintenance_status_code = msc.maintenance_status_code
WHERE mt.archived_at IS NULL
  AND mt.current_maintenance_status_code IN ('NEW','ASN','IPR');

CREATE OR REPLACE VIEW vw_Supervisor_Assigned_Maintenance_History AS
SELECT
    mt.ticket_id,
    mt.ticket_code,
    mt.item_id,
    i.item_code,
    i.item_name,
    i.current_status_code,
    isc.status_name AS current_status_name,
    s.space_code,
    s.space_name,
    mt.reporter_user_id,
    reporter.user_code AS reporter_user_code,
    reporter.user_name AS reporter_name,
    mt.assigned_handler_user_id,
    handler.user_code AS handler_user_code,
    handler.user_name AS handler_name,
    mt.current_maintenance_status_code,
    msc.status_name AS maintenance_status_name,
    mt.reported_at,
    mt.closed_at,
    mt.issue_description,
    last_action.cost_amount,
    last_action.replaced_part_description,
    last_action.next_maintenance_date,
    last_action.action_note AS result_note,
    mt.archived_at
FROM MAINTENANCE_TICKET mt
JOIN ITEM i ON mt.item_id = i.item_id
JOIN ITEM_STATUS_CODE isc ON i.current_status_code = isc.item_status_code
JOIN SPACE s ON i.current_space_id = s.space_id
JOIN APP_USER reporter ON mt.reporter_user_id = reporter.user_id
LEFT JOIN APP_USER handler ON mt.assigned_handler_user_id = handler.user_id
JOIN MAINTENANCE_STATUS_CODE msc
    ON mt.current_maintenance_status_code = msc.maintenance_status_code
LEFT JOIN (
    SELECT ma.*
    FROM MAINTENANCE_ACTION ma
    JOIN (
        SELECT ticket_id, MAX(action_id) AS max_action_id
        FROM MAINTENANCE_ACTION
        GROUP BY ticket_id
    ) latest ON ma.ticket_id = latest.ticket_id
            AND ma.action_id = latest.max_action_id
) last_action ON mt.ticket_id = last_action.ticket_id
WHERE mt.current_maintenance_status_code IN ('CMP','CAN')
   OR mt.archived_at IS NOT NULL;

CREATE OR REPLACE VIEW vw_Admin_Asset_Master AS
SELECT
    i.item_id,
    i.item_code,
    i.item_name,
    i.item_type_code,
    it.type_name AS item_type_name,
    i.current_status_code,
    isc.status_name AS current_status_name,
    s.space_code,
    s.space_name,
    ed.property_tag_no,
    cid.control_tag_no,
    COALESCE(ed.acquisition_date, cid.acquisition_date) AS acquisition_date,
    COALESCE(ed.acquisition_amount, cid.acquisition_amount) AS acquisition_amount,
    ed.lifespan_years,
    ed.fund_source,
    COALESCE(ed.custodian_user_id, cid.custodian_user_id) AS custodian_user_id,
    custodian.user_code AS custodian_user_code,
    custodian.user_name AS custodian_name,
    supervisor.user_code AS supervisor_user_code,
    supervisor.user_name AS supervisor_name,
    i.warranty_expiry_date,
    i.archived_at
FROM ITEM i
JOIN ITEM_TYPE_CODE it ON i.item_type_code = it.item_type_code
JOIN ITEM_STATUS_CODE isc ON i.current_status_code = isc.item_status_code
JOIN SPACE s ON i.current_space_id = s.space_id
LEFT JOIN EQUIPMENT_DETAIL ed ON i.item_id = ed.item_id
LEFT JOIN CONTROLLED_ITEM_DETAIL cid ON i.item_id = cid.item_id
LEFT JOIN APP_USER custodian ON COALESCE(ed.custodian_user_id, cid.custodian_user_id) = custodian.user_id
JOIN APP_USER supervisor ON i.supervisor_user_id = supervisor.user_id
WHERE i.item_type_code IN ('EQP','CTL');

CREATE OR REPLACE VIEW vw_Admin_Item_Management AS
SELECT
    i.item_id,
    i.item_code,
    i.item_name,
    i.item_type_code,
    it.type_name AS item_type_name,
    i.current_status_code,
    isc.status_name AS current_status_name,
    s.space_code,
    s.space_name,
    st.type_name AS space_type_name,
    ed.property_tag_no,
    cid.control_tag_no,
    rid.specification,
    rid.is_borrowable,
    rid.need_return,
    cd.stock_quantity,
    cd.min_stock_quantity,
    cd.unit_name,
    i.archived_at
FROM ITEM i
JOIN ITEM_TYPE_CODE it ON i.item_type_code = it.item_type_code
JOIN ITEM_STATUS_CODE isc ON i.current_status_code = isc.item_status_code
JOIN SPACE s ON i.current_space_id = s.space_id
JOIN SPACE_TYPE_CODE st ON s.space_type_code = st.space_type_code
LEFT JOIN EQUIPMENT_DETAIL ed ON i.item_id = ed.item_id
LEFT JOIN CONTROLLED_ITEM_DETAIL cid ON i.item_id = cid.item_id
LEFT JOIN REUSABLE_ITEM_DETAIL rid ON i.item_id = rid.item_id
LEFT JOIN CONSUMABLE_DETAIL cd ON i.item_id = cd.item_id;

CREATE OR REPLACE VIEW vw_Admin_Consumable_Alert AS
SELECT
    i.item_id,
    i.item_code,
    i.item_name,
    i.current_status_code,
    isc.status_name AS current_status_name,
    s.space_code,
    s.space_name,
    cd.stock_quantity,
    cd.min_stock_quantity,
    cd.unit_name,
    CASE
        WHEN cd.stock_quantity = 0 THEN 'ZERO'
        WHEN cd.stock_quantity <= cd.min_stock_quantity THEN 'LOW'
        ELSE 'OK'
    END AS alert_level_code
FROM ITEM i
JOIN ITEM_STATUS_CODE isc ON i.current_status_code = isc.item_status_code
JOIN CONSUMABLE_DETAIL cd ON i.item_id = cd.item_id
JOIN SPACE s ON i.current_space_id = s.space_id
WHERE i.archived_at IS NULL
  AND i.item_type_code = 'CON'
  AND i.current_status_code <> 'DSP'
  AND cd.stock_quantity <= cd.min_stock_quantity;

CREATE OR REPLACE VIEW vw_Admin_Consumable_Master AS
SELECT
    i.item_id,
    i.item_code,
    i.item_name,
    i.current_status_code,
    isc.status_name AS current_status_name,
    s.space_code,
    s.space_name,
    st.type_name AS space_type_name,
    cd.stock_quantity,
    cd.min_stock_quantity,
    cd.unit_name,
    CASE
        WHEN cd.stock_quantity = 0 THEN 'ZERO'
        WHEN cd.stock_quantity <= cd.min_stock_quantity THEN 'LOW'
        ELSE 'OK'
    END AS alert_level_code
FROM ITEM i
JOIN ITEM_STATUS_CODE isc ON i.current_status_code = isc.item_status_code
JOIN CONSUMABLE_DETAIL cd ON i.item_id = cd.item_id
JOIN SPACE s ON i.current_space_id = s.space_id
JOIN SPACE_TYPE_CODE st ON s.space_type_code = st.space_type_code
WHERE i.item_type_code = 'CON';

CREATE OR REPLACE VIEW vw_Admin_Maintenance_Ticket_Master AS
SELECT
    mt.ticket_id,
    mt.ticket_code,
    mt.item_id,
    i.item_code,
    i.item_name,
    i.item_type_code,
    it.type_name AS item_type_name,
    i.current_status_code,
    isc.status_name AS current_status_name,
    s.space_code,
    s.space_name,
    mt.reporter_user_id,
    reporter.user_code AS reporter_user_code,
    reporter.user_name AS reporter_name,
    mt.assigned_handler_user_id,
    handler.user_code AS handler_user_code,
    handler.user_name AS handler_name,
    mt.current_maintenance_status_code,
    msc.status_name AS maintenance_status_name,
    mt.reported_at,
    mt.closed_at,
    mt.issue_description,
    last_action.cost_amount,
    last_action.replaced_part_description,
    last_action.next_maintenance_date,
    last_action.action_note AS result_note,
    mt.archived_at
FROM MAINTENANCE_TICKET mt
JOIN ITEM i ON mt.item_id = i.item_id
JOIN ITEM_TYPE_CODE it ON i.item_type_code = it.item_type_code
JOIN ITEM_STATUS_CODE isc ON i.current_status_code = isc.item_status_code
JOIN SPACE s ON i.current_space_id = s.space_id
JOIN APP_USER reporter ON mt.reporter_user_id = reporter.user_id
LEFT JOIN APP_USER handler ON mt.assigned_handler_user_id = handler.user_id
JOIN MAINTENANCE_STATUS_CODE msc
    ON mt.current_maintenance_status_code = msc.maintenance_status_code
LEFT JOIN (
    SELECT ma.*
    FROM MAINTENANCE_ACTION ma
    JOIN (
        SELECT ticket_id, MAX(action_id) AS max_action_id
        FROM MAINTENANCE_ACTION
        GROUP BY ticket_id
    ) latest ON ma.ticket_id = latest.ticket_id
            AND ma.action_id = latest.max_action_id
) last_action ON mt.ticket_id = last_action.ticket_id;

CREATE OR REPLACE VIEW vw_Admin_Audit_Trail AS
SELECT
    i.item_code,
    i.item_name,
    'STH' AS event_type_code,
    ish.changed_at AS event_time,
    op.user_code AS actor_user_code,
    op.user_name AS actor_name,
    CONCAT(IFNULL(ish.previous_status_code, 'NULL'), '->', ish.new_status_code, ': ', ish.reason) AS detail,
    ish.archived_at
FROM ITEM_STATUS_HISTORY ish
JOIN ITEM i ON ish.item_id = i.item_id
JOIN APP_USER op ON ish.operator_user_id = op.user_id

UNION ALL

SELECT
    i.item_code,
    i.item_name,
    'BRW' AS event_type_code,
    br.borrowed_at AS event_time,
    u.user_code AS actor_user_code,
    u.user_name AS actor_name,
    CONCAT('borrow_code=', br.borrow_code, '; status=', br.borrow_status_code,
           '; expected_return=', IFNULL(DATE_FORMAT(br.expected_return_at, '%Y-%m-%d %H:%i:%s'), 'NULL'),
           '; returned_at=', IFNULL(DATE_FORMAT(br.returned_at, '%Y-%m-%d %H:%i:%s'), 'NULL')) AS detail,
    br.archived_at
FROM BORROW_RECORD br
JOIN ITEM i ON br.item_id = i.item_id
JOIN APP_USER u ON br.borrower_user_id = u.user_id

UNION ALL

SELECT
    i.item_code,
    i.item_name,
    'CON' AS event_type_code,
    cr.consumed_at AS event_time,
    u.user_code AS actor_user_code,
    u.user_name AS actor_name,
    CONCAT('consume_code=', cr.consume_code, '; amount=', cr.amount, '; purpose=', cr.purpose) AS detail,
    cr.archived_at
FROM CONSUME_RECORD cr
JOIN ITEM i ON cr.item_id = i.item_id
JOIN APP_USER u ON cr.consumer_user_id = u.user_id

UNION ALL

SELECT
    i.item_code,
    i.item_name,
    'MNT' AS event_type_code,
    ma.action_at AS event_time,
    u.user_code AS actor_user_code,
    u.user_name AS actor_name,
    CONCAT('ticket_code=', mt.ticket_code, '; action=', ma.action_type_code,
           '; status=', IFNULL(ma.previous_status_code, 'NULL'), '->', IFNULL(ma.new_status_code, 'NULL'),
           '; note=', IFNULL(ma.action_note, '')) AS detail,
    ma.archived_at
FROM MAINTENANCE_ACTION ma
JOIN MAINTENANCE_TICKET mt ON ma.ticket_id = mt.ticket_id
JOIN ITEM i ON mt.item_id = i.item_id
JOIN APP_USER u ON ma.operator_user_id = u.user_id;

CREATE OR REPLACE VIEW vw_Admin_Overdue_Borrows AS
SELECT
    br.borrow_id,
    br.borrow_code,
    i.item_code,
    i.item_name,
    u.user_code AS borrower_user_code,
    u.user_name AS borrower_name,
    br.borrowed_at,
    br.expected_return_at,
    br.borrow_status_code
FROM BORROW_RECORD br
JOIN ITEM i ON br.item_id = i.item_id
JOIN APP_USER u ON br.borrower_user_id = u.user_id
WHERE br.archived_at IS NULL
  AND br.returned_at IS NULL
  AND br.borrow_status_code IN ('ACT','OVD')
  AND br.expected_return_at < CURRENT_TIMESTAMP;

CREATE OR REPLACE VIEW vw_Admin_Archived_History AS
SELECT
    item_code,
    item_name,
    event_type_code,
    event_time,
    actor_user_code,
    actor_name,
    detail,
    archived_at
FROM vw_Admin_Audit_Trail
WHERE archived_at IS NOT NULL;

/* =========================================================
   10. Verification SELECT
   ========================================================= */

SELECT 'Final Project Part III schema loaded' AS section;

SELECT 'table row counts' AS section;
SELECT 'ROLE_CODE' AS table_name, COUNT(*) AS row_count FROM ROLE_CODE
UNION ALL SELECT 'ITEM_TYPE_CODE', COUNT(*) FROM ITEM_TYPE_CODE
UNION ALL SELECT 'ITEM_STATUS_CODE', COUNT(*) FROM ITEM_STATUS_CODE
UNION ALL SELECT 'BORROW_STATUS_CODE', COUNT(*) FROM BORROW_STATUS_CODE
UNION ALL SELECT 'MAINTENANCE_STATUS_CODE', COUNT(*) FROM MAINTENANCE_STATUS_CODE
UNION ALL SELECT 'SPACE_TYPE_CODE', COUNT(*) FROM SPACE_TYPE_CODE
UNION ALL SELECT 'MAINTENANCE_ACTION_TYPE_CODE', COUNT(*) FROM MAINTENANCE_ACTION_TYPE_CODE
UNION ALL SELECT 'APP_USER', COUNT(*) FROM APP_USER
UNION ALL SELECT 'USER_ROLE', COUNT(*) FROM USER_ROLE
UNION ALL SELECT 'SPACE', COUNT(*) FROM SPACE
UNION ALL SELECT 'VENDOR', COUNT(*) FROM VENDOR
UNION ALL SELECT 'ITEM', COUNT(*) FROM ITEM
UNION ALL SELECT 'EQUIPMENT_DETAIL', COUNT(*) FROM EQUIPMENT_DETAIL
UNION ALL SELECT 'CONTROLLED_ITEM_DETAIL', COUNT(*) FROM CONTROLLED_ITEM_DETAIL
UNION ALL SELECT 'REUSABLE_ITEM_DETAIL', COUNT(*) FROM REUSABLE_ITEM_DETAIL
UNION ALL SELECT 'CONSUMABLE_DETAIL', COUNT(*) FROM CONSUMABLE_DETAIL
UNION ALL SELECT 'BORROW_RECORD', COUNT(*) FROM BORROW_RECORD
UNION ALL SELECT 'CONSUME_RECORD', COUNT(*) FROM CONSUME_RECORD
UNION ALL SELECT 'MAINTENANCE_TICKET', COUNT(*) FROM MAINTENANCE_TICKET
UNION ALL SELECT 'MAINTENANCE_ACTION', COUNT(*) FROM MAINTENANCE_ACTION
UNION ALL SELECT 'ITEM_STATUS_HISTORY', COUNT(*) FROM ITEM_STATUS_HISTORY;

SELECT 'subtype completeness check - expected 0 rows' AS section;
SELECT
    i.item_code,
    i.item_type_code,
    (
      (CASE WHEN ed.item_id IS NULL THEN 0 ELSE 1 END) +
      (CASE WHEN cid.item_id IS NULL THEN 0 ELSE 1 END) +
      (CASE WHEN rid.item_id IS NULL THEN 0 ELSE 1 END) +
      (CASE WHEN cd.item_id IS NULL THEN 0 ELSE 1 END)
    ) AS subtype_count
FROM ITEM i
LEFT JOIN EQUIPMENT_DETAIL ed ON i.item_id = ed.item_id
LEFT JOIN CONTROLLED_ITEM_DETAIL cid ON i.item_id = cid.item_id
LEFT JOIN REUSABLE_ITEM_DETAIL rid ON i.item_id = rid.item_id
LEFT JOIN CONSUMABLE_DETAIL cd ON i.item_id = cd.item_id
WHERE (
      (CASE WHEN ed.item_id IS NULL THEN 0 ELSE 1 END) +
      (CASE WHEN cid.item_id IS NULL THEN 0 ELSE 1 END) +
      (CASE WHEN rid.item_id IS NULL THEN 0 ELSE 1 END) +
      (CASE WHEN cd.item_id IS NULL THEN 0 ELSE 1 END)
    ) <> 1;

SELECT 'view row counts' AS section;
SELECT 'vw_Login_User_Role' AS view_name, COUNT(*) AS row_count FROM vw_Login_User_Role
UNION ALL SELECT 'vw_Student_Available_Borrowable_Items', COUNT(*) FROM vw_Student_Available_Borrowable_Items
UNION ALL SELECT 'vw_Student_Available_Consumables', COUNT(*) FROM vw_Student_Available_Consumables
UNION ALL SELECT 'vw_Student_Current_Borrowed_Items', COUNT(*) FROM vw_Student_Current_Borrowed_Items
UNION ALL SELECT 'vw_Student_Maintenance_Reportable_Items', COUNT(*) FROM vw_Student_Maintenance_Reportable_Items
UNION ALL SELECT 'vw_Student_Maintenance_Handlers', COUNT(*) FROM vw_Student_Maintenance_Handlers
UNION ALL SELECT 'vw_Supervisor_Assigned_Maintenance_Active', COUNT(*) FROM vw_Supervisor_Assigned_Maintenance_Active
UNION ALL SELECT 'vw_Supervisor_Assigned_Maintenance_History', COUNT(*) FROM vw_Supervisor_Assigned_Maintenance_History
UNION ALL SELECT 'vw_Admin_Asset_Master', COUNT(*) FROM vw_Admin_Asset_Master
UNION ALL SELECT 'vw_Admin_Item_Management', COUNT(*) FROM vw_Admin_Item_Management
UNION ALL SELECT 'vw_Admin_Consumable_Alert', COUNT(*) FROM vw_Admin_Consumable_Alert
UNION ALL SELECT 'vw_Admin_Consumable_Master', COUNT(*) FROM vw_Admin_Consumable_Master
UNION ALL SELECT 'vw_Admin_Maintenance_Ticket_Master', COUNT(*) FROM vw_Admin_Maintenance_Ticket_Master
UNION ALL SELECT 'vw_Admin_Audit_Trail', COUNT(*) FROM vw_Admin_Audit_Trail
UNION ALL SELECT 'vw_Admin_Overdue_Borrows', COUNT(*) FROM vw_Admin_Overdue_Borrows
UNION ALL SELECT 'vw_Admin_Archived_History', COUNT(*) FROM vw_Admin_Archived_History;

SELECT 'successful procedure smoke tests' AS section;
CALL sp_borrow_item(2, 3, '2026-12-31 17:00:00', 'verification borrow');
CALL sp_return_item(11, 3, 'N', NULL);
CALL sp_issue_consumable(31, 3, 1, 'verification consumable issue');
CALL sp_open_maintenance_ticket(5, 3, 2, 'verification maintenance ticket');
CALL sp_close_maintenance_ticket(11, 2, 1200, '校正模組', '2026-12-31', 'verification maintenance close', 'AVL');

SELECT 'post-smoke key rows' AS section;
SELECT borrow_code, borrow_status_code, returned_at FROM BORROW_RECORD WHERE borrow_id = 11;
SELECT consume_code, amount, purpose FROM CONSUME_RECORD WHERE consume_id = 11;
SELECT ticket_code, current_maintenance_status_code, closed_at FROM MAINTENANCE_TICKET WHERE ticket_id = 11;

/* =========================================================
   11. Manual negative tests
   These are intentionally commented out because they should fail.
   Uncomment one at a time during grading if needed.
   ========================================================= */

-- Borrowing a consumable should fail.
-- CALL sp_borrow_item(31, 3, '2026-12-31 17:00:00', 'negative test');

-- Borrowing an already borrowed item should fail.
-- CALL sp_borrow_item(3, 4, '2026-12-31 17:00:00', 'negative test');

-- Borrowing a scrapped item should fail.
-- CALL sp_borrow_item(7, 4, '2026-12-31 17:00:00', 'negative test');

-- Opening maintenance for a consumable should fail.
-- CALL sp_open_maintenance_ticket(31, 3, 2, 'negative test');

-- Opening maintenance for a scrapped item should fail.
-- CALL sp_open_maintenance_ticket(7, 3, 2, 'negative test');

-- Issuing more consumables than current stock should fail.
-- CALL sp_issue_consumable(32, 3, 999, 'negative test');

-- Issuing zero or negative amount should fail.
-- CALL sp_issue_consumable(31, 3, 0, 'negative test');
-- CALL sp_issue_consumable(31, 3, -1, 'negative test');

-- Return time earlier than borrow time should fail at CHECK / trigger level.
-- UPDATE BORROW_RECORD SET returned_at = '2020-01-01 00:00:00' WHERE borrow_id = 10;

-- Duplicate property tag should fail.
-- INSERT INTO EQUIPMENT_DETAIL (item_id, property_tag_no, acquisition_date, acquisition_amount, lifespan_years, fund_source, custodian_user_id)
-- VALUES (2, 'P202400001', '2026-01-01', 20000, 5, 'negative test', 1);

-- Nonexistent FK should fail.
-- INSERT INTO USER_ROLE (user_id, role_code) VALUES (999999, 'MEM');
