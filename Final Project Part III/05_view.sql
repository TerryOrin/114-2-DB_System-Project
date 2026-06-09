/* =========================================================
   Equipment Management System - 05_view.sql
   External schema / role-based views
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

/* ---------------------------------------------------------
   1. 全系師生：可借用設備清單
   - Only available borrowable equipment
   - Excludes consumables
   - Hides asset cost, fund source, and custodian information
   --------------------------------------------------------- */
CREATE OR REPLACE VIEW vw_Student_Available_Borrowable_Items AS
SELECT
    i.internal_id,
    i.item_name,
    i.manage_type,
    i.current_status,
    s.space_name,
    r.specification,
    r.need_return
FROM ITEM i
JOIN SPACE s
    ON i.space_id = s.space_id
LEFT JOIN REUSABLE_EQUIPMENT r
    ON i.internal_id = r.internal_id
WHERE i.current_status = '可用'
  AND i.manage_type IN ('財產設備', '非列管設備')
  AND (
        i.manage_type = '財產設備'
        OR r.is_borrowable = TRUE
      );

/* ---------------------------------------------------------
   2. 全系師生：可領用耗材清單
   - Only available consumables with positive stock
   - Hides procurement and management-only fields
   --------------------------------------------------------- */
CREATE OR REPLACE VIEW vw_Student_Available_Consumables AS
SELECT
    i.internal_id,
    i.item_name,
    i.manage_type,
    i.current_status,
    s.space_id,
    s.space_name,
    s.location_type,
    c.stock_quantity,
    c.unit
FROM ITEM i
JOIN CONSUMABLE_DETAIL c
    ON i.internal_id = c.internal_id
JOIN SPACE s
    ON i.space_id = s.space_id
WHERE i.manage_type = '耗材'
  AND i.current_status = '可用'
  AND c.stock_quantity > 0;

/* ---------------------------------------------------------
   3. 全系師生：目前借用中設備清單
   - Used by return workflow
   - Application must filter by user_id for the login user
   --------------------------------------------------------- */
CREATE OR REPLACE VIEW vw_Student_Current_Borrowed_Items AS
SELECT
    br.record_id,
    br.internal_id,
    i.item_name,
    i.manage_type,
    i.current_status,
    s.space_id,
    s.space_name,
    s.location_type,
    r.specification,
    r.need_return,
    br.user_id,
    u.user_name,
    br.borrow_time,
    br.expected_return,
    br.status
FROM BORROW_RECORD br
JOIN ITEM i
    ON br.internal_id = i.internal_id
JOIN SPACE s
    ON i.space_id = s.space_id
JOIN `USER` u
    ON br.user_id = u.user_id
LEFT JOIN REUSABLE_EQUIPMENT r
    ON i.internal_id = r.internal_id
WHERE br.status IN ('借用中', '逾期')
  AND br.actual_return IS NULL;

/* ---------------------------------------------------------
   4. 全系師生：可回報維修設備清單
   - Excludes consumables and scrapped items
   - Excludes items that already have an open maintenance ticket
   - Hides financial and custodian fields
   --------------------------------------------------------- */
CREATE OR REPLACE VIEW vw_Student_Maintenance_Reportable_Items AS
SELECT
    i.internal_id,
    i.item_name,
    i.manage_type,
    i.current_status,
    i.warranty_expiry,
    s.space_id,
    s.space_name,
    s.location_type
FROM ITEM i
JOIN SPACE s
    ON i.space_id = s.space_id
WHERE i.manage_type IN ('財產設備', '非列管設備')
  AND i.current_status <> '報廢'
  AND NOT EXISTS (
      SELECT 1
      FROM MAINTENANCE_TICKET mt
      WHERE mt.internal_id = i.internal_id
        AND mt.maint_status IN ('待處理', '處理中')
  );

/* ---------------------------------------------------------
   5. 全系師生：可指派設備負責人清單
   - Used by maintenance reporting form
   --------------------------------------------------------- */
CREATE OR REPLACE VIEW vw_Student_Maintenance_Handlers AS
SELECT
    u.user_id AS handler_id,
    u.user_name AS handler_name
FROM `USER` u
JOIN ROLE r
    ON u.role_id = r.role_id
WHERE r.role_name = '設備負責人';

/* ---------------------------------------------------------
   6. 設備負責人：被指派維修待辦工單
   - Shows pending / processing tickets
   - Keeps handler_id so application can filter by login user
   --------------------------------------------------------- */
CREATE OR REPLACE VIEW vw_Supervisor_Assigned_Maintenance_Tasks AS
SELECT
    mt.ticket_id,
    mt.internal_id,
    i.item_name,
    i.current_status,
    s.space_id,
    s.space_name,
    s.location_type,
    mt.reporter_id,
    reporter.user_name AS reporter_name,
    mt.handler_id,
    handler.user_name AS handler_name,
    mt.vendor_id,
    v.vendor_name,
    mt.repair_time,
    mt.issue_desc,
    mt.maint_status,
    mt.resolved_time,
    mt.replaced_parts,
    mt.next_maint_date,
    mt.result
FROM MAINTENANCE_TICKET mt
JOIN ITEM i
    ON mt.internal_id = i.internal_id
JOIN SPACE s
    ON i.space_id = s.space_id
JOIN `USER` reporter
    ON mt.reporter_id = reporter.user_id
LEFT JOIN `USER` handler
    ON mt.handler_id = handler.user_id
LEFT JOIN VENDOR v
    ON mt.vendor_id = v.vendor_id
WHERE mt.maint_status IN ('待處理', '處理中');

/* ---------------------------------------------------------
   7. 設備負責人：被指派維修歷史工單
   - Shows completed / cancelled tickets
   - Application must filter by handler_id for the login user
   --------------------------------------------------------- */
CREATE OR REPLACE VIEW vw_Supervisor_Maintenance_History AS
SELECT
    mt.ticket_id,
    mt.internal_id,
    i.item_name,
    i.current_status,
    s.space_id,
    s.space_name,
    s.location_type,
    mt.reporter_id,
    reporter.user_name AS reporter_name,
    mt.handler_id,
    handler.user_name AS handler_name,
    mt.vendor_id,
    v.vendor_name,
    mt.repair_time,
    mt.issue_desc,
    mt.maint_status,
    mt.repair_cost,
    mt.resolved_time,
    mt.replaced_parts,
    mt.next_maint_date,
    mt.result
FROM MAINTENANCE_TICKET mt
JOIN ITEM i
    ON mt.internal_id = i.internal_id
JOIN SPACE s
    ON i.space_id = s.space_id
JOIN `USER` reporter
    ON mt.reporter_id = reporter.user_id
LEFT JOIN `USER` handler
    ON mt.handler_id = handler.user_id
LEFT JOIN VENDOR v
    ON mt.vendor_id = v.vendor_id
WHERE mt.maint_status IN ('已完成', '取消');

/* ---------------------------------------------------------
   8. 系所管理員：全系財產設備資產總覽
   --------------------------------------------------------- */
CREATE OR REPLACE VIEW vw_Admin_Asset_Master AS
SELECT
    i.internal_id,
    i.item_name,
    i.manage_type,
    i.current_status,
    i.warranty_expiry,
    s.space_id,
    s.space_name,
    s.location_type,
    a.asset_id,
    a.fund_source,
    a.acquired_date,
    a.acquired_cost,
    a.lifespan_years,
    a.custodian_id,
    u.user_name AS custodian_name,
    u.email AS custodian_email
FROM ITEM i
JOIN ASSET_DETAIL a
    ON i.internal_id = a.internal_id
JOIN SPACE s
    ON i.space_id = s.space_id
JOIN `USER` u
    ON a.custodian_id = u.user_id
WHERE i.manage_type = '財產設備';

/* ---------------------------------------------------------
   9. 系所管理員：低庫存耗材預警
   --------------------------------------------------------- */
CREATE OR REPLACE VIEW vw_Admin_Consumable_Alert AS
SELECT
    i.internal_id,
    i.item_name,
    i.current_status,
    s.space_id,
    s.space_name,
    s.location_type,
    c.stock_quantity,
    c.min_stock,
    c.unit,
    CASE
        WHEN c.stock_quantity = 0 THEN '已無庫存'
        WHEN c.stock_quantity <= c.min_stock THEN '低於安全庫存'
        ELSE '正常'
    END AS alert_level
FROM CONSUMABLE_DETAIL c
JOIN ITEM i
    ON c.internal_id = i.internal_id
JOIN SPACE s
    ON i.space_id = s.space_id
WHERE i.manage_type = '耗材'
  AND i.current_status <> '報廢'
  AND c.stock_quantity <= c.min_stock;

/* ---------------------------------------------------------
   10. 系所管理員：全系維修工單總覽
   - Shows all maintenance ticket statuses
   - Complements audit trail; does not replace event history
   --------------------------------------------------------- */
CREATE OR REPLACE VIEW vw_Admin_Maintenance_Ticket_Master AS
SELECT
    mt.ticket_id,
    mt.internal_id,
    i.item_name,
    i.manage_type,
    i.current_status,
    s.space_id,
    s.space_name,
    s.location_type,
    mt.reporter_id,
    reporter.user_name AS reporter_name,
    mt.handler_id,
    handler.user_name AS handler_name,
    mt.vendor_id,
    v.vendor_name,
    mt.repair_time,
    mt.issue_desc,
    mt.maint_status,
    mt.repair_cost,
    mt.resolved_time,
    mt.replaced_parts,
    mt.next_maint_date,
    mt.result
FROM MAINTENANCE_TICKET mt
JOIN ITEM i
    ON mt.internal_id = i.internal_id
JOIN SPACE s
    ON i.space_id = s.space_id
JOIN `USER` reporter
    ON mt.reporter_id = reporter.user_id
LEFT JOIN `USER` handler
    ON mt.handler_id = handler.user_id
LEFT JOIN VENDOR v
    ON mt.vendor_id = v.vendor_id;

/* ---------------------------------------------------------
   11. 系所管理員：審計軌跡 / 使用歷程追蹤
   - Integrates status history, borrow records, and maintenance tickets
   --------------------------------------------------------- */
CREATE OR REPLACE VIEW vw_Admin_Audit_Trail AS
SELECT
    i.internal_id AS internal_id,
    i.item_name AS item_name,
    '狀態異動' AS event_type,
    sh.change_time AS event_time,
    op.user_id AS actor_id,
    op.user_name AS actor_name,
    CONCAT(sh.old_status, ' → ', sh.new_status) AS event_detail,
    sh.reason AS note
FROM STATUS_HISTORY sh
JOIN ITEM i
    ON sh.internal_id = i.internal_id
JOIN `USER` op
    ON sh.operator_id = op.user_id

UNION ALL

SELECT
    i.internal_id AS internal_id,
    i.item_name AS item_name,
    '設備借用' AS event_type,
    br.borrow_time AS event_time,
    u.user_id AS actor_id,
    u.user_name AS actor_name,
    CONCAT('借用狀態：', br.status) AS event_detail,
    CONCAT(
        '預計歸還：',
        IFNULL(DATE_FORMAT(br.expected_return, '%Y-%m-%d %H:%i:%s'), '未填寫'),
        '；實際歸還：',
        IFNULL(DATE_FORMAT(br.actual_return, '%Y-%m-%d %H:%i:%s'), '尚未歸還')
    ) AS note
FROM BORROW_RECORD br
JOIN ITEM i
    ON br.internal_id = i.internal_id
JOIN `USER` u
    ON br.user_id = u.user_id

UNION ALL

SELECT
    i.internal_id AS internal_id,
    i.item_name AS item_name,
    '維修報修' AS event_type,
    mt.repair_time AS event_time,
    reporter.user_id AS actor_id,
    reporter.user_name AS actor_name,
    CONCAT('維修狀態：', mt.maint_status) AS event_detail,
    mt.issue_desc AS note
FROM MAINTENANCE_TICKET mt
JOIN ITEM i
    ON mt.internal_id = i.internal_id
JOIN `USER` reporter
    ON mt.reporter_id = reporter.user_id;
