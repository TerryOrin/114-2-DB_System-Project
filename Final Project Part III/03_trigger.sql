/* =========================================================
   Equipment Management System - 03_trigger.sql
   Database-level guardrails and audit logging
   Target: MySQL 8.0 / MariaDB
   ========================================================= */

SET NAMES utf8mb4;

DROP TRIGGER IF EXISTS trg_item_before_update_state_lock;
DROP TRIGGER IF EXISTS trg_item_after_update_status_audit;
DROP TRIGGER IF EXISTS trg_borrow_before_insert_check;
DROP TRIGGER IF EXISTS trg_maintenance_before_insert_check;

DELIMITER //

/* ---------------------------------------------------------
   1. State machine lock
   Rule: once an item is scrapped, it cannot leave scrapped state.
   --------------------------------------------------------- */
CREATE TRIGGER trg_item_before_update_state_lock
BEFORE UPDATE ON ITEM
FOR EACH ROW
BEGIN
    IF OLD.current_status = '報廢'
       AND NEW.current_status <> '報廢' THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = '已報廢物品不可更改為其他狀態';
    END IF;
END//

/* ---------------------------------------------------------
   2. Status change audit log
   Rule: every status change must be written to STATUS_HISTORY.

   Before updating ITEM.current_status directly, set:
   SET @app_user_id = 'U001';
   SET @status_reason = 'your reason';
   --------------------------------------------------------- */
CREATE TRIGGER trg_item_after_update_status_audit
AFTER UPDATE ON ITEM
FOR EACH ROW
BEGIN
    IF OLD.current_status <> NEW.current_status THEN

        IF @app_user_id IS NULL OR TRIM(@app_user_id) = '' THEN
            SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = '狀態異動必須指定操作者 @app_user_id';
        END IF;

        IF @status_reason IS NULL OR TRIM(@status_reason) = '' THEN
            SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = '狀態異動必須填寫異動原因 @status_reason';
        END IF;

        INSERT INTO STATUS_HISTORY (
            internal_id,
            operator_id,
            old_status,
            new_status,
            reason
        ) VALUES (
            NEW.internal_id,
            @app_user_id,
            OLD.current_status,
            NEW.current_status,
            @status_reason
        );
    END IF;
END//

/* ---------------------------------------------------------
   3. Borrowing interceptor
   Rule: consumables cannot be borrowed; active borrowing requires item availability.
   --------------------------------------------------------- */
CREATE TRIGGER trg_borrow_before_insert_check
BEFORE INSERT ON BORROW_RECORD
FOR EACH ROW
BEGIN
    DECLARE v_status VARCHAR(50);
    DECLARE v_manage_type VARCHAR(50);
    DECLARE v_is_borrowable BOOLEAN DEFAULT TRUE;
    DECLARE v_open_borrow_count INT DEFAULT 0;

    SELECT current_status, manage_type
    INTO v_status, v_manage_type
    FROM ITEM
    WHERE internal_id = NEW.internal_id;

    IF v_manage_type = '耗材' THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = '耗材不得建立借用紀錄';
    END IF;

    IF NEW.status IN ('借用中', '逾期') THEN
        IF v_status <> '可用' THEN
            SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = '該物品目前不可借用';
        END IF;

        SELECT COUNT(*)
        INTO v_open_borrow_count
        FROM BORROW_RECORD
        WHERE internal_id = NEW.internal_id
          AND status IN ('借用中', '逾期')
          AND actual_return IS NULL;

        IF v_open_borrow_count > 0 THEN
            SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = '該物品已有未歸還借用紀錄';
        END IF;
    END IF;

    IF v_manage_type = '非列管設備' THEN
        SELECT is_borrowable
        INTO v_is_borrowable
        FROM REUSABLE_EQUIPMENT
        WHERE internal_id = NEW.internal_id;

        IF v_is_borrowable = FALSE THEN
            SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = '該非列管設備設定為不可借用';
        END IF;
    END IF;
END//

/* ---------------------------------------------------------
   4. Maintenance interceptor
   Rule: scrapped items and consumables cannot create maintenance tickets.
   --------------------------------------------------------- */
CREATE TRIGGER trg_maintenance_before_insert_check
BEFORE INSERT ON MAINTENANCE_TICKET
FOR EACH ROW
BEGIN
    DECLARE v_status VARCHAR(50);
    DECLARE v_manage_type VARCHAR(50);
    DECLARE v_open_ticket_count INT DEFAULT 0;

    SELECT current_status, manage_type
    INTO v_status, v_manage_type
    FROM ITEM
    WHERE internal_id = NEW.internal_id;

    IF v_status = '報廢' THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = '該設備已報廢，無法建立維修工單';
    END IF;

    IF v_manage_type = '耗材' THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = '耗材不得建立維修工單';
    END IF;

    IF NEW.maint_status IN ('待處理', '處理中') THEN
        SELECT COUNT(*)
        INTO v_open_ticket_count
        FROM MAINTENANCE_TICKET
        WHERE internal_id = NEW.internal_id
          AND maint_status IN ('待處理', '處理中');

        IF v_open_ticket_count > 0 THEN
            SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = '該設備已有未結案維修工單';
        END IF;
    END IF;
END//

DELIMITER ;
