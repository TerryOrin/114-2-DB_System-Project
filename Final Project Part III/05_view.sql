/* =========================================================
   Equipment Management System - 05_view.sql
   Role-based views
   Target: MySQL 8.0 / MariaDB
   ========================================================= */

SET NAMES utf8mb4;

DROP VIEW IF EXISTS vw_Admin_Audit_Trail;
DROP VIEW IF EXISTS vw_Admin_Maintenance_Ticket_Master;
DROP VIEW IF EXISTS vw_Admin_Consumable_Alert;
DROP VIEW IF EXISTS vw_Admin_Asset_Master;
DROP VIEW IF EXISTS vw_Supervisor_Maintenance_History;
DROP VIEW IF EXISTS vw_Supervisor_Assigned_Maintenance_Tasks;
DROP VIEW IF EXISTS vw_Student_Maintenance_Handlers;
DROP VIEW IF EXISTS vw_Student_Maintenance_Reportable_Items;
DROP VIEW IF EXISTS vw_Student_Current_Borrowed_Items;
DROP VIEW IF EXISTS vw_Student_Available_Consumables;
DROP VIEW IF EXISTS vw_Student_Available_Borrowable_Items;

CREATE OR REPLACE VIEW vw_Student_Available_Borrowable_Items AS
SELECT
    i.item_id,
    i.item_code,
    i.item_name,
    i.item_type,
    i.current_status,
    s.space_id,
    s.space_code,
    s.space_name,
    s.space_type,
    r.specification,
    r.quantity,
    r.need_return,
    CASE
        WHEN i.item_type = 1 THEN i.is_borrowable
        WHEN i.item_type = 2 THEN r.is_borrowable
        ELSE 0
    END AS is_borrowable
FROM item i
JOIN space s
    ON i.space_id = s.space_id
LEFT JOIN reusable_equipment r
    ON i.item_id = r.item_id
WHERE i.current_status = 1
  AND (
        (i.item_type = 1 AND i.is_borrowable = 1)
        OR
        (i.item_type = 2 AND r.is_borrowable = 1)
      );

CREATE OR REPLACE VIEW vw_Student_Available_Consumables AS
SELECT
    i.item_id,
    i.item_code,
    i.item_name,
    i.item_type,
    i.current_status,
    s.space_id,
    s.space_code,
    s.space_name,
    s.space_type,
    c.stock_quantity,
    c.min_stock,
    c.unit_code
FROM item i
JOIN consumable_detail c
    ON i.item_id = c.item_id
JOIN space s
    ON i.space_id = s.space_id
WHERE i.item_type = 3
  AND i.current_status = 1
  AND c.stock_quantity > 0;

CREATE OR REPLACE VIEW vw_Student_Current_Borrowed_Items AS
SELECT
    br.borrow_id,
    br.item_id,
    i.item_code,
    i.item_name,
    i.item_type,
    i.current_status,
    s.space_id,
    s.space_code,
    s.space_name,
    s.space_type,
    r.specification,
    r.need_return,
    br.user_id,
    u.user_code,
    u.user_name,
    br.borrow_time,
    br.expected_return_time,
    br.actual_return_time,
    br.borrow_status
FROM borrow_record br
JOIN item i
    ON br.item_id = i.item_id
JOIN space s
    ON i.space_id = s.space_id
JOIN app_user u
    ON br.user_id = u.user_id
LEFT JOIN reusable_equipment r
    ON i.item_id = r.item_id
WHERE br.borrow_status IN (1, 3)
  AND br.actual_return_time IS NULL;

CREATE OR REPLACE VIEW vw_Student_Maintenance_Reportable_Items AS
SELECT
    i.item_id,
    i.item_code,
    i.item_name,
    i.item_type,
    i.current_status,
    i.warranty_expiry,
    s.space_id,
    s.space_code,
    s.space_name,
    s.space_type
FROM item i
JOIN space s
    ON i.space_id = s.space_id
WHERE i.item_type IN (1, 2)
  AND i.current_status <> 5
  AND NOT EXISTS (
      SELECT 1
      FROM maintenance_ticket mt
      WHERE mt.item_id = i.item_id
        AND mt.maintenance_status IN (1, 2)
  );

CREATE OR REPLACE VIEW vw_Student_Maintenance_Handlers AS
SELECT
    u.user_id AS handler_id,
    u.user_code AS handler_code,
    u.user_name AS handler_name
FROM app_user u
JOIN role_type r
    ON u.role_id = r.role_id
WHERE r.role_id = 3
  AND u.is_active = 1;

CREATE OR REPLACE VIEW vw_Supervisor_Assigned_Maintenance_Tasks AS
SELECT
    mt.ticket_id,
    mt.item_id,
    i.item_code,
    i.item_name,
    i.current_status,
    s.space_id,
    s.space_code,
    s.space_name,
    s.space_type,
    mt.reporter_user_id,
    reporter.user_code AS reporter_code,
    reporter.user_name AS reporter_name,
    mt.handler_user_id AS handler_id,
    handler.user_code AS handler_code,
    handler.user_name AS handler_name,
    latest_process.process_id,
    latest_process.vendor_id,
    v.vendor_name,
    mt.reported_time,
    mt.issue_desc,
    mt.maintenance_status,
    latest_process.process_time,
    latest_process.completed_time,
    latest_process.repair_cost,
    latest_process.replaced_parts,
    latest_process.next_maintenance_date,
    latest_process.repair_result
FROM maintenance_ticket mt
JOIN item i
    ON mt.item_id = i.item_id
JOIN space s
    ON i.space_id = s.space_id
JOIN app_user reporter
    ON mt.reporter_user_id = reporter.user_id
LEFT JOIN app_user handler
    ON mt.handler_user_id = handler.user_id
LEFT JOIN (
    SELECT p1.*
    FROM maintenance_process_record p1
    JOIN (
        SELECT ticket_id, MAX(process_id) AS process_id
        FROM maintenance_process_record
        GROUP BY ticket_id
    ) latest
        ON p1.ticket_id = latest.ticket_id
       AND p1.process_id = latest.process_id
) latest_process
    ON mt.ticket_id = latest_process.ticket_id
LEFT JOIN vendor v
    ON latest_process.vendor_id = v.vendor_id
WHERE mt.maintenance_status IN (1, 2);

CREATE OR REPLACE VIEW vw_Supervisor_Maintenance_History AS
SELECT
    mt.ticket_id,
    mt.item_id,
    i.item_code,
    i.item_name,
    i.current_status,
    s.space_id,
    s.space_code,
    s.space_name,
    s.space_type,
    mt.reporter_user_id,
    reporter.user_code AS reporter_code,
    reporter.user_name AS reporter_name,
    mt.handler_user_id AS handler_id,
    handler.user_code AS handler_code,
    handler.user_name AS handler_name,
    latest_process.process_id,
    latest_process.vendor_id,
    v.vendor_name,
    mt.reported_time,
    mt.issue_desc,
    mt.maintenance_status,
    latest_process.process_time,
    latest_process.completed_time,
    latest_process.repair_cost,
    latest_process.replaced_parts,
    latest_process.next_maintenance_date,
    latest_process.repair_result
FROM maintenance_ticket mt
JOIN item i
    ON mt.item_id = i.item_id
JOIN space s
    ON i.space_id = s.space_id
JOIN app_user reporter
    ON mt.reporter_user_id = reporter.user_id
LEFT JOIN app_user handler
    ON mt.handler_user_id = handler.user_id
LEFT JOIN (
    SELECT p1.*
    FROM maintenance_process_record p1
    JOIN (
        SELECT ticket_id, MAX(process_id) AS process_id
        FROM maintenance_process_record
        GROUP BY ticket_id
    ) latest
        ON p1.ticket_id = latest.ticket_id
       AND p1.process_id = latest.process_id
) latest_process
    ON mt.ticket_id = latest_process.ticket_id
LEFT JOIN vendor v
    ON latest_process.vendor_id = v.vendor_id
WHERE mt.maintenance_status IN (3, 4);

CREATE OR REPLACE VIEW vw_Admin_Asset_Master AS
SELECT
    i.item_id,
    i.item_code,
    i.item_name,
    i.item_type,
    i.current_status,
    i.warranty_expiry,
    s.space_id,
    s.space_code,
    s.space_name,
    s.space_type,
    a.asset_code,
    a.fund_source_code,
    a.fund_source_note,
    a.acquired_date,
    a.acquired_cost,
    a.useful_life_years,
    a.custodian_user_id,
    custodian.user_code AS custodian_code,
    custodian.user_name AS custodian_name,
    custodian.email AS custodian_email
FROM item i
JOIN asset_detail a
    ON i.item_id = a.item_id
JOIN space s
    ON i.space_id = s.space_id
JOIN app_user custodian
    ON a.custodian_user_id = custodian.user_id
WHERE i.item_type = 1;

CREATE OR REPLACE VIEW vw_Admin_Consumable_Alert AS
SELECT
    i.item_id,
    i.item_code,
    i.item_name,
    i.current_status,
    s.space_id,
    s.space_code,
    s.space_name,
    s.space_type,
    c.stock_quantity,
    c.min_stock,
    c.unit_code,
    CASE
        WHEN c.stock_quantity = 0 THEN '已無庫存'
        WHEN c.stock_quantity <= c.min_stock THEN '低於安全庫存'
        ELSE '正常'
    END AS alert_level
FROM consumable_detail c
JOIN item i
    ON c.item_id = i.item_id
JOIN space s
    ON i.space_id = s.space_id
WHERE i.item_type = 3
  AND i.current_status <> 5
  AND c.stock_quantity <= c.min_stock;

CREATE OR REPLACE VIEW vw_Admin_Maintenance_Ticket_Master AS
SELECT
    mt.ticket_id,
    mt.item_id,
    i.item_code,
    i.item_name,
    i.item_type,
    i.current_status,
    s.space_id,
    s.space_code,
    s.space_name,
    s.space_type,
    mt.reporter_user_id,
    reporter.user_code AS reporter_code,
    reporter.user_name AS reporter_name,
    mt.handler_user_id AS handler_id,
    handler.user_code AS handler_code,
    handler.user_name AS handler_name,
    latest_process.process_id,
    latest_process.vendor_id,
    v.vendor_name,
    mt.reported_time,
    mt.issue_desc,
    mt.maintenance_status,
    latest_process.process_time,
    latest_process.completed_time,
    latest_process.repair_cost,
    latest_process.replaced_parts,
    latest_process.next_maintenance_date,
    latest_process.repair_result
FROM maintenance_ticket mt
JOIN item i
    ON mt.item_id = i.item_id
JOIN space s
    ON i.space_id = s.space_id
JOIN app_user reporter
    ON mt.reporter_user_id = reporter.user_id
LEFT JOIN app_user handler
    ON mt.handler_user_id = handler.user_id
LEFT JOIN (
    SELECT p1.*
    FROM maintenance_process_record p1
    JOIN (
        SELECT ticket_id, MAX(process_id) AS process_id
        FROM maintenance_process_record
        GROUP BY ticket_id
    ) latest
        ON p1.ticket_id = latest.ticket_id
       AND p1.process_id = latest.process_id
) latest_process
    ON mt.ticket_id = latest_process.ticket_id
LEFT JOIN vendor v
    ON latest_process.vendor_id = v.vendor_id;

CREATE OR REPLACE VIEW vw_Admin_Audit_Trail AS
SELECT
    i.item_id AS item_id,
    i.item_code AS item_code,
    i.item_name AS item_name,
    '狀態異動' AS event_type,
    sh.changed_time AS event_time,
    op.user_id AS actor_id,
    op.user_code AS actor_code,
    op.user_name AS actor_name,
    CONCAT('狀態代碼：', sh.old_status, ' → ', sh.new_status) AS event_detail,
    sh.reason AS note
FROM status_history sh
JOIN item i
    ON sh.item_id = i.item_id
JOIN app_user op
    ON sh.operator_user_id = op.user_id

UNION ALL

SELECT
    i.item_id AS item_id,
    i.item_code AS item_code,
    i.item_name AS item_name,
    '設備借用' AS event_type,
    br.borrow_time AS event_time,
    u.user_id AS actor_id,
    u.user_code AS actor_code,
    u.user_name AS actor_name,
    CONCAT('借用狀態代碼：', br.borrow_status) AS event_detail,
    CONCAT(
        '預計歸還：',
        IFNULL(DATE_FORMAT(br.expected_return_time, '%Y-%m-%d %H:%i:%s'), '未填寫'),
        '；實際歸還：',
        IFNULL(DATE_FORMAT(br.actual_return_time, '%Y-%m-%d %H:%i:%s'), '尚未歸還')
    ) AS note
FROM borrow_record br
JOIN item i
    ON br.item_id = i.item_id
JOIN app_user u
    ON br.user_id = u.user_id

UNION ALL

SELECT
    i.item_id AS item_id,
    i.item_code AS item_code,
    i.item_name AS item_name,
    '維修報修' AS event_type,
    mt.reported_time AS event_time,
    reporter.user_id AS actor_id,
    reporter.user_code AS actor_code,
    reporter.user_name AS actor_name,
    CONCAT('維修狀態代碼：', mt.maintenance_status) AS event_detail,
    mt.issue_desc AS note
FROM maintenance_ticket mt
JOIN item i
    ON mt.item_id = i.item_id
JOIN app_user reporter
    ON mt.reporter_user_id = reporter.user_id;
