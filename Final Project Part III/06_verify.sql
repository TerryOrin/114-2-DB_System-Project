-- 06_verify.sql
-- Equipment Management System verification queries

USE equipment_management;
SET NAMES utf8mb4;

-- 1. Check all base table row counts
SELECT 'ROLE' AS table_name, COUNT(*) AS row_count FROM ROLE
UNION ALL SELECT 'SPACE', COUNT(*) FROM SPACE
UNION ALL SELECT 'VENDOR', COUNT(*) FROM VENDOR
UNION ALL SELECT 'USER', COUNT(*) FROM `USER`
UNION ALL SELECT 'DEPARTMENT_ADMINISTRATOR', COUNT(*) FROM DEPARTMENT_ADMINISTRATOR
UNION ALL SELECT 'EQUIPMENT_SUPERVISOR', COUNT(*) FROM EQUIPMENT_SUPERVISOR
UNION ALL SELECT 'ITEM', COUNT(*) FROM ITEM
UNION ALL SELECT 'ASSET_DETAIL', COUNT(*) FROM ASSET_DETAIL
UNION ALL SELECT 'REUSABLE_EQUIPMENT', COUNT(*) FROM REUSABLE_EQUIPMENT
UNION ALL SELECT 'CONSUMABLE_DETAIL', COUNT(*) FROM CONSUMABLE_DETAIL
UNION ALL SELECT 'CONSUME_RECORD', COUNT(*) FROM CONSUME_RECORD
UNION ALL SELECT 'BORROW_RECORD', COUNT(*) FROM BORROW_RECORD
UNION ALL SELECT 'MAINTENANCE_TICKET', COUNT(*) FROM MAINTENANCE_TICKET
UNION ALL SELECT 'STATUS_HISTORY', COUNT(*) FROM STATUS_HISTORY;

-- 2. Check role data
SELECT * FROM ROLE ORDER BY role_id;

-- 3. Check users and their roles
SELECT u.user_id, u.user_name, u.email, r.role_name
FROM `USER` u
JOIN ROLE r ON u.role_id = r.role_id
ORDER BY u.user_id;

-- 4. Check ITEM category distribution
SELECT manage_type, current_status, COUNT(*) AS item_count
FROM ITEM
GROUP BY manage_type, current_status
ORDER BY manage_type, current_status;

-- 5. Check child-table integrity counts
SELECT '財產設備 child rows' AS check_name, COUNT(*) AS cnt
FROM ITEM i JOIN ASSET_DETAIL a ON i.internal_id = a.internal_id
WHERE i.manage_type = '財產設備'
UNION ALL
SELECT '非列管設備 child rows', COUNT(*)
FROM ITEM i JOIN REUSABLE_EQUIPMENT r ON i.internal_id = r.internal_id
WHERE i.manage_type = '非列管設備'
UNION ALL
SELECT '耗材 child rows', COUNT(*)
FROM ITEM i JOIN CONSUMABLE_DETAIL c ON i.internal_id = c.internal_id
WHERE i.manage_type = '耗材';

-- 6. Check invalid consumable borrow records. Expected: 0 rows.
SELECT br.*
FROM BORROW_RECORD br
JOIN ITEM i ON br.internal_id = i.internal_id
WHERE i.manage_type = '耗材';

-- 7. Check invalid maintenance tickets for consumables or disposed items. Expected: 0 rows.
SELECT mt.ticket_id, mt.internal_id, i.item_name, i.manage_type, i.current_status, mt.maint_status
FROM MAINTENANCE_TICKET mt
JOIN ITEM i ON mt.internal_id = i.internal_id
WHERE i.manage_type = '耗材'
   OR i.current_status = '報廢';

-- 8. Check consume records do not exceed current stock plus consumed amount.
-- This detects obviously inconsistent negative or impossible values. Expected: 0 rows.
SELECT cr.record_id, cr.internal_id, cr.amount, cd.stock_quantity
FROM CONSUME_RECORD cr
JOIN CONSUMABLE_DETAIL cd ON cr.internal_id = cd.internal_id
WHERE cr.amount <= 0 OR cd.stock_quantity < 0;

-- 9. Check borrow time constraints. Expected: 0 rows.
SELECT *
FROM BORROW_RECORD
WHERE (expected_return IS NOT NULL AND expected_return <= borrow_time)
   OR (actual_return IS NOT NULL AND actual_return < borrow_time);

-- 10. Check maintenance time constraints. Expected: 0 rows.
SELECT *
FROM MAINTENANCE_TICKET
WHERE (resolved_time IS NOT NULL AND resolved_time < repair_time)
   OR (next_maint_date IS NOT NULL AND resolved_time IS NOT NULL AND next_maint_date <= DATE(resolved_time))
   OR (next_maint_date IS NOT NULL AND resolved_time IS NULL AND next_maint_date <= DATE(repair_time));

-- 11. Check available views after 05_view.sql is sourced
SHOW FULL TABLES WHERE Table_type = 'VIEW';

-- 12. Sample view outputs
SELECT * FROM vw_Student_Available_Borrowable_Items LIMIT 10;
SELECT * FROM vw_Student_Available_Consumables;
SELECT * FROM vw_Supervisor_Assigned_Maintenance_Tasks LIMIT 10;
SELECT * FROM vw_Supervisor_Maintenance_History ORDER BY resolved_time DESC;
SELECT * FROM vw_Admin_Asset_Master LIMIT 10;
SELECT * FROM vw_Admin_Consumable_Alert LIMIT 10;
SELECT * FROM vw_Admin_Maintenance_Ticket_Master ORDER BY repair_time DESC;
SELECT * FROM vw_Admin_Audit_Trail ORDER BY event_time DESC LIMIT 20;

-- 13. Verify student consumable view. Expected: 0 rows.
SELECT *
FROM vw_Student_Available_Consumables
WHERE manage_type <> '耗材'
   OR current_status <> '可用'
   OR stock_quantity <= 0;

-- 14. Verify supervisor maintenance history view.
SELECT *
FROM vw_Supervisor_Maintenance_History
ORDER BY resolved_time DESC;

SELECT *
FROM vw_Supervisor_Maintenance_History
WHERE handler_id = 'U002'
ORDER BY resolved_time DESC;

-- 15. Verify administrator maintenance ticket master view.
SELECT *
FROM vw_Admin_Maintenance_Ticket_Master
ORDER BY repair_time DESC;

SELECT *
FROM vw_Admin_Maintenance_Ticket_Master
WHERE maint_status = '已完成'
ORDER BY resolved_time DESC;
