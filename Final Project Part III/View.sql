/* =========================================================
   Equipment Management System - Views
   MariaDB executable version
   ========================================================= */

/* ---------------------------------------------------------
   1. 全系師生：可借用設備清單
   目的：
   - 只顯示狀態為「可用」的可借設備
   - 排除耗材
   - 隱藏財產取得金額、經費來源、保管人等敏感欄位
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
   2. 設備負責人：被指派維修工單
   目的：
   - 顯示待處理、處理中的維修工單
   - 保留 handler_id，讓後端可用登入者 ID 過濾
   - 不顯示財產取得金額、經費來源等財務欄位

   實際查詢範例：
   SELECT *
   FROM vw_Supervisor_Assigned_Maintenance_Tasks
   WHERE handler_id = '目前登入者的 user_id';
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
   3. 系所管理員：全系財產設備資產總覽
   目的：
   - 提供系所管理員做全系資產盤點、報廢審查
   - 管理員可查看財產編號、經費來源、取得金額、保管人
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
   4. 系所管理員：低庫存耗材預警
   目的：
   - 只顯示庫存量小於或等於最低庫存量的耗材
   - 排除已報廢耗材
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
   5. 系所管理員：審計軌跡 / 使用歷程追蹤
   目的：
   - 將狀態異動、設備借用、維修報修整合成統一事件格式
   - 支援設備流向追蹤與責任溯源

   注意：
   UNION ALL 的每個 SELECT 欄位數量與型別必須一致。
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


/* ---------------------------------------------------------
   Optional test queries
   --------------------------------------------------------- */

SELECT * FROM vw_Student_Available_Borrowable_Items;

SELECT * FROM vw_Supervisor_Assigned_Maintenance_Tasks;

SELECT * FROM vw_Admin_Asset_Master;

SELECT * FROM vw_Admin_Consumable_Alert;

SELECT *
FROM vw_Admin_Audit_Trail
ORDER BY event_time DESC;