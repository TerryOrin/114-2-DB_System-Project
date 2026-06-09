/* =========================================================
   Equipment Management System - 06_verify.sql
   Purpose:
   Show all inserted seed data in the SAME order as 04_test_seed_data.sql.
   Target: MySQL 8.0 / MariaDB
   ========================================================= */
USE equipment_management;
SET NAMES utf8mb4;

SELECT 'Row counts in the same table order as 04_test_seed_data.sql' AS section;

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

SELECT '1. ROLE - inserted seed data' AS section;
SELECT *
FROM ROLE
ORDER BY role_id;

SELECT '2. SPACE - inserted seed data' AS section;
SELECT *
FROM SPACE
ORDER BY space_id;

SELECT '3. VENDOR - inserted seed data' AS section;
SELECT *
FROM VENDOR
ORDER BY vendor_id;

SELECT '4. USER - inserted seed data' AS section;
SELECT *
FROM `USER`
ORDER BY user_id;

SELECT '4-1. DEPARTMENT_ADMINISTRATOR - inserted seed data' AS section;
SELECT *
FROM DEPARTMENT_ADMINISTRATOR
ORDER BY user_id;

SELECT '4-2. EQUIPMENT_SUPERVISOR - inserted seed data' AS section;
SELECT *
FROM EQUIPMENT_SUPERVISOR
ORDER BY user_id;

SELECT '5. ITEM - inserted seed data' AS section;
SELECT *
FROM ITEM
ORDER BY FIELD(
    internal_id,
    'A001','A002','A003','A004','A005','A006','A007','A008','A009','A010',
    'R001','R002','R003','R004','R005','R006','R007','R008','R009','R010',
    'C001','C002','C003','C004','C005','C006','C007','C008','C009','C010'
);

SELECT '6. ASSET_DETAIL - inserted seed data' AS section;
SELECT *
FROM ASSET_DETAIL
ORDER BY asset_id;

SELECT '7. REUSABLE_EQUIPMENT - inserted seed data' AS section;
SELECT *
FROM REUSABLE_EQUIPMENT
ORDER BY internal_id;

SELECT '8. CONSUMABLE_DETAIL - inserted seed data' AS section;
SELECT *
FROM CONSUMABLE_DETAIL
ORDER BY internal_id;

SELECT '9. CONSUME_RECORD - inserted seed data' AS section;
SELECT *
FROM CONSUME_RECORD
ORDER BY record_id;

SELECT '10. BORROW_RECORD - inserted seed data' AS section;
SELECT *
FROM BORROW_RECORD
ORDER BY record_id;

SELECT '11. MAINTENANCE_TICKET - inserted seed data' AS section;
SELECT *
FROM MAINTENANCE_TICKET
ORDER BY ticket_id;

SELECT '12. STATUS_HISTORY - inserted seed data' AS section;
SELECT *
FROM STATUS_HISTORY
ORDER BY log_id;

SELECT 'View check - optional result preview' AS section;

SELECT 'vw_Student_Available_Borrowable_Items' AS view_name;
SELECT *
FROM vw_Student_Available_Borrowable_Items
ORDER BY internal_id;

SELECT 'vw_Student_Available_Consumables' AS view_name;
SELECT *
FROM vw_Student_Available_Consumables
ORDER BY internal_id;

SELECT 'vw_Student_Current_Borrowed_Items' AS view_name;
SELECT *
FROM vw_Student_Current_Borrowed_Items
ORDER BY user_id, borrow_time DESC, record_id DESC;

SELECT 'vw_Student_Current_Borrowed_Items invalid rows - expected empty' AS view_name;
SELECT *
FROM vw_Student_Current_Borrowed_Items
WHERE status NOT IN ('借用中', '逾期');

SELECT 'vw_Student_Maintenance_Reportable_Items' AS view_name;
SELECT *
FROM vw_Student_Maintenance_Reportable_Items
ORDER BY internal_id;

SELECT 'vw_Student_Maintenance_Handlers' AS view_name;
SELECT *
FROM vw_Student_Maintenance_Handlers
ORDER BY handler_id;

SELECT 'vw_Supervisor_Assigned_Maintenance_Tasks' AS view_name;
SELECT *
FROM vw_Supervisor_Assigned_Maintenance_Tasks
ORDER BY ticket_id;

SELECT 'vw_Supervisor_Maintenance_History' AS view_name;
SELECT *
FROM vw_Supervisor_Maintenance_History
ORDER BY resolved_time DESC, ticket_id DESC;

SELECT 'vw_Admin_Asset_Master' AS view_name;
SELECT *
FROM vw_Admin_Asset_Master
ORDER BY internal_id;

SELECT 'vw_Admin_Consumable_Alert' AS view_name;
SELECT *
FROM vw_Admin_Consumable_Alert
ORDER BY internal_id;

SELECT 'vw_Admin_Maintenance_Ticket_Master' AS view_name;
SELECT *
FROM vw_Admin_Maintenance_Ticket_Master
ORDER BY repair_time DESC, ticket_id DESC;

SELECT 'vw_Admin_Audit_Trail' AS view_name;
SELECT *
FROM vw_Admin_Audit_Trail
ORDER BY event_time DESC, internal_id;
