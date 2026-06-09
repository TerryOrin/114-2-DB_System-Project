/* =========================================================
   Equipment Management System - 02_transaction.sql
   Stored procedures implementing transaction workflows
   Target: MySQL 8.0 / MariaDB
   ========================================================= */

SET NAMES utf8mb4;

DROP PROCEDURE IF EXISTS sp_consume_item;
DROP PROCEDURE IF EXISTS sp_borrow_item;
DROP PROCEDURE IF EXISTS sp_return_item;
DROP PROCEDURE IF EXISTS sp_create_maintenance_ticket;
DROP PROCEDURE IF EXISTS sp_close_maintenance_ticket;

DELIMITER //

/* ---------------------------------------------------------
   1. Consumable usage transaction
   Goal: prevent over-issuing stock under concurrent requests.
   --------------------------------------------------------- */
CREATE PROCEDURE sp_consume_item (
    IN p_internal_id VARCHAR(50),
    IN p_user_id VARCHAR(50),
    IN p_amount INT,
    IN p_purpose VARCHAR(255)
)
BEGIN
    DECLARE v_stock INT DEFAULT 0;
    DECLARE v_manage_type VARCHAR(50);

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        RESIGNAL;
    END;

    START TRANSACTION;

    SELECT i.manage_type, c.stock_quantity
    INTO v_manage_type, v_stock
    FROM CONSUMABLE_DETAIL c
    JOIN ITEM i ON c.internal_id = i.internal_id
    WHERE c.internal_id = p_internal_id
    FOR UPDATE;

    IF v_manage_type <> '耗材' THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = '只有耗材可以進行領用';
    END IF;

    IF p_amount <= 0 THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = '領用數量必須為正整數';
    END IF;

    IF v_stock < p_amount THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = '庫存不足，無法領用';
    END IF;

    UPDATE CONSUMABLE_DETAIL
    SET stock_quantity = stock_quantity - p_amount
    WHERE internal_id = p_internal_id;

    INSERT INTO CONSUME_RECORD (
        internal_id,
        user_id,
        consume_time,
        amount,
        purpose
    ) VALUES (
        p_internal_id,
        p_user_id,
        CURRENT_TIMESTAMP,
        p_amount,
        p_purpose
    );

    COMMIT;
END//

/* ---------------------------------------------------------
   2. Borrow transaction
   Goal: prevent double borrowing and synchronize ITEM status.
   --------------------------------------------------------- */
CREATE PROCEDURE sp_borrow_item (
    IN p_internal_id VARCHAR(50),
    IN p_user_id VARCHAR(50),
    IN p_expected_return TIMESTAMP
)
BEGIN
    DECLARE v_status VARCHAR(50);
    DECLARE v_manage_type VARCHAR(50);
    DECLARE v_is_borrowable BOOLEAN DEFAULT TRUE;
    DECLARE v_open_borrow_count INT DEFAULT 0;

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        SET @app_user_id = NULL;
        SET @status_reason = NULL;
        RESIGNAL;
    END;

    START TRANSACTION;

    SELECT current_status, manage_type
    INTO v_status, v_manage_type
    FROM ITEM
    WHERE internal_id = p_internal_id
    FOR UPDATE;

    IF v_manage_type = '耗材' THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = '耗材不得借用，請使用領用流程';
    END IF;

    IF v_status <> '可用' THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = '設備目前不可借用';
    END IF;

    IF v_manage_type = '非列管設備' THEN
        SELECT is_borrowable
        INTO v_is_borrowable
        FROM REUSABLE_EQUIPMENT
        WHERE internal_id = p_internal_id;

        IF v_is_borrowable = FALSE THEN
            SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = '該非列管設備設定為不可借用';
        END IF;
    END IF;

    SELECT COUNT(*)
    INTO v_open_borrow_count
    FROM BORROW_RECORD
    WHERE internal_id = p_internal_id
      AND status IN ('借用中', '逾期')
      AND actual_return IS NULL;

    IF v_open_borrow_count > 0 THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = '該設備已有未歸還借用紀錄';
    END IF;

    INSERT INTO BORROW_RECORD (
        internal_id,
        user_id,
        borrow_time,
        expected_return,
        actual_return,
        status
    ) VALUES (
        p_internal_id,
        p_user_id,
        CURRENT_TIMESTAMP,
        p_expected_return,
        NULL,
        '借用中'
    );

    SET @app_user_id = p_user_id;
    SET @status_reason = '設備借用，狀態改為借出中';

    UPDATE ITEM
    SET current_status = '借出中'
    WHERE internal_id = p_internal_id;

    COMMIT;

    SET @app_user_id = NULL;
    SET @status_reason = NULL;
END//

/* ---------------------------------------------------------
   3. Return transaction
   Goal: synchronize BORROW_RECORD and ITEM status.
   --------------------------------------------------------- */
CREATE PROCEDURE sp_return_item (
    IN p_record_id INT,
    IN p_operator_id VARCHAR(50),
    IN p_is_damaged BOOLEAN,
    IN p_handler_id VARCHAR(50),
    IN p_vendor_id INT
)
BEGIN
    DECLARE v_internal_id VARCHAR(50);
    DECLARE v_borrow_status VARCHAR(50);
    DECLARE v_actual_return TIMESTAMP;
    DECLARE v_new_status VARCHAR(50);
    DECLARE v_handler_count INT DEFAULT 0;
    DECLARE v_vendor_count INT DEFAULT 0;

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        SET @app_user_id = NULL;
        SET @status_reason = NULL;
        RESIGNAL;
    END;

    START TRANSACTION;

    SELECT internal_id, status, actual_return
    INTO v_internal_id, v_borrow_status, v_actual_return
    FROM BORROW_RECORD
    WHERE record_id = p_record_id
    FOR UPDATE;

    SELECT current_status
    INTO @locked_item_status
    FROM ITEM
    WHERE internal_id = v_internal_id
    FOR UPDATE;

    IF v_borrow_status NOT IN ('借用中', '逾期')
       OR v_actual_return IS NOT NULL THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = '該借用紀錄已非借用中，不能重複歸還';
    END IF;

    UPDATE BORROW_RECORD
    SET actual_return = CURRENT_TIMESTAMP,
        status = '已歸還'
    WHERE record_id = p_record_id;

    IF p_is_damaged THEN
        IF p_handler_id IS NULL OR TRIM(p_handler_id) = '' THEN
            SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = '歸還時通報損壞必須指定設備負責人';
        END IF;

        IF p_vendor_id IS NULL THEN
            SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = '歸還時通報損壞必須指定委託廠商';
        END IF;

        SELECT COUNT(*)
        INTO v_handler_count
        FROM EQUIPMENT_SUPERVISOR
        WHERE user_id = p_handler_id;

        IF v_handler_count = 0 THEN
            SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = '查無此設備負責人';
        END IF;

        SELECT COUNT(*)
        INTO v_vendor_count
        FROM VENDOR
        WHERE vendor_id = p_vendor_id;

        IF v_vendor_count = 0 THEN
            SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = '查無此維護廠商';
        END IF;

        SET v_new_status = '維修中';
        SET @status_reason = '設備歸還時通報損壞，狀態改為維修中';
    ELSE
        SET v_new_status = '可用';
        SET @status_reason = '設備歸還完成，狀態改回可用';
    END IF;

    SET @app_user_id = p_operator_id;

    UPDATE ITEM
    SET current_status = v_new_status
    WHERE internal_id = v_internal_id;

    IF p_is_damaged THEN
        INSERT INTO MAINTENANCE_TICKET (
            internal_id,
            reporter_id,
            handler_id,
            vendor_id,
            repair_time,
            issue_desc,
            maint_status,
            repair_cost,
            resolved_time,
            replaced_parts,
            next_maint_date,
            result
        ) VALUES (
            v_internal_id,
            p_operator_id,
            p_handler_id,
            p_vendor_id,
            CURRENT_TIMESTAMP,
            '設備歸還時通報損壞',
            '待處理',
            0,
            NULL,
            NULL,
            NULL,
            NULL
        );
    END IF;

    COMMIT;

    SET @app_user_id = NULL;
    SET @status_reason = NULL;
END//

/* ---------------------------------------------------------
   4. Maintenance ticket creation transaction
   Goal: take equipment offline immediately after ticket creation.
   --------------------------------------------------------- */
CREATE PROCEDURE sp_create_maintenance_ticket (
    IN p_internal_id VARCHAR(50),
    IN p_reporter_id VARCHAR(50),
    IN p_handler_id VARCHAR(50),
    IN p_vendor_id INT,
    IN p_issue_desc TEXT
)
BEGIN
    DECLARE v_status VARCHAR(50);
    DECLARE v_manage_type VARCHAR(50);

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        SET @app_user_id = NULL;
        SET @status_reason = NULL;
        RESIGNAL;
    END;

    START TRANSACTION;

    SELECT current_status, manage_type
    INTO v_status, v_manage_type
    FROM ITEM
    WHERE internal_id = p_internal_id
    FOR UPDATE;

    IF v_status = '報廢' THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = '該設備已報廢，無法建立維修工單';
    END IF;

    IF v_manage_type = '耗材' THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = '耗材不得建立維修工單';
    END IF;

    INSERT INTO MAINTENANCE_TICKET (
        internal_id,
        reporter_id,
        handler_id,
        vendor_id,
        repair_time,
        issue_desc,
        maint_status,
        repair_cost,
        resolved_time,
        replaced_parts,
        next_maint_date,
        result
    ) VALUES (
        p_internal_id,
        p_reporter_id,
        p_handler_id,
        p_vendor_id,
        CURRENT_TIMESTAMP,
        p_issue_desc,
        '待處理',
        0,
        NULL,
        NULL,
        NULL,
        NULL
    );

    SET @app_user_id = p_reporter_id;
    SET @status_reason = '建立維修工單，設備狀態改為維修中';

    UPDATE ITEM
    SET current_status = '維修中'
    WHERE internal_id = p_internal_id;

    COMMIT;

    SET @app_user_id = NULL;
    SET @status_reason = NULL;
END//

/* ---------------------------------------------------------
   5. Maintenance close transaction
   Goal: synchronize ticket result and ITEM status.
   --------------------------------------------------------- */
CREATE PROCEDURE sp_close_maintenance_ticket (
    IN p_ticket_id INT,
    IN p_operator_id VARCHAR(50),
    IN p_vendor_id INT,
    IN p_repair_cost INT,
    IN p_replaced_parts VARCHAR(255),
    IN p_next_maint_date DATE,
    IN p_result TEXT,
    IN p_item_new_status VARCHAR(50)
)
BEGIN
    DECLARE v_internal_id VARCHAR(50);
    DECLARE v_maint_status VARCHAR(50);
    DECLARE v_vendor_count INT DEFAULT 0;

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        SET @app_user_id = NULL;
        SET @status_reason = NULL;
        RESIGNAL;
    END;

    START TRANSACTION;

    SELECT internal_id, maint_status
    INTO v_internal_id, v_maint_status
    FROM MAINTENANCE_TICKET
    WHERE ticket_id = p_ticket_id
    FOR UPDATE;

    SELECT current_status
    INTO @locked_item_status
    FROM ITEM
    WHERE internal_id = v_internal_id
    FOR UPDATE;

    IF v_maint_status = '已完成' THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = '該維修工單已結案';
    END IF;

    IF p_item_new_status NOT IN ('可用', '停用') THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = '維修結案後設備狀態只能改為可用或停用';
    END IF;

    IF p_vendor_id IS NULL THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = '維修工單必須指定委託廠商';
    END IF;

    SELECT COUNT(*)
    INTO v_vendor_count
    FROM VENDOR
    WHERE vendor_id = p_vendor_id;

    IF v_vendor_count = 0 THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = '查無此維護廠商';
    END IF;

    UPDATE MAINTENANCE_TICKET
    SET maint_status = '已完成',
        vendor_id = p_vendor_id,
        repair_cost = p_repair_cost,
        resolved_time = CURRENT_TIMESTAMP,
        replaced_parts = p_replaced_parts,
        next_maint_date = p_next_maint_date,
        result = p_result,
        handler_id = p_operator_id
    WHERE ticket_id = p_ticket_id;

    SET @app_user_id = p_operator_id;
    SET @status_reason = CONCAT('維修結案，設備狀態改為', p_item_new_status);

    UPDATE ITEM
    SET current_status = p_item_new_status
    WHERE internal_id = v_internal_id;

    COMMIT;

    SET @app_user_id = NULL;
    SET @status_reason = NULL;
END//

DELIMITER ;
