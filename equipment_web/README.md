# 設備管理與維護系統 Web 前端

本專案是資料庫系統期末專題的 Flask + MariaDB Web 前端。系統不重新設計資料庫 Schema，而是接上既有 SQL 檔案中的 View、Stored Procedure、Trigger 與 Transaction。

## 1. 啟動 conda 環境

```powershell
conda activate db
```

## 2. 安裝套件

```powershell
cd D:\code\114-2-DB_System-Project\equipment_web
pip install -r requirements.txt
```

## 3. 設定 `.env`

請複製 `.env.example` 為 `.env`，並確認密碼為 `305305`。

```powershell
Copy-Item -Force .env.example .env
```

`.env` 內容範例：

```env
DB_HOST=localhost
DB_PORT=3306
DB_USER=root
DB_PASSWORD=305305
DB_NAME=equipment_management
FLASK_SECRET_KEY=replace_this_secret_key
```

注意：`.env` 內含資料庫密碼，不要加入版本控制。

## 4. 初始化資料庫

請先切到 SQL 檔案所在目錄：

```powershell
cd "D:\code\114-2-DB_System-Project\Final Project Part III"
```

依序執行：

```powershell
mysql -u root -p < 00_create_database.sql
mysql -u root -p equipment_management < 01_schema.sql
mysql -u root -p equipment_management < 02_transaction.sql
mysql -u root -p equipment_management < 04_test_seed_data.sql
mysql -u root -p equipment_management < 03_trigger.sql
mysql -u root -p equipment_management < 05_view.sql
mysql -u root -p equipment_management < 06_verify.sql
```

如果 `mysql` 不在 PATH，可以改用 MariaDB 安裝目錄的完整路徑：

```powershell
& "C:\Program Files\MariaDB 12.3\bin\mysql.exe" -u root -p < 00_create_database.sql
```

Seed Data 先於 Trigger 匯入，是為了避免初始化資料被正式 Trigger 規則攔截。

## 5. 啟動 Web 系統

```powershell
cd D:\code\114-2-DB_System-Project\equipment_web
conda activate db
python app.py
```

開啟瀏覽器：

```text
http://127.0.0.1:5000
```

## 6. 測試帳號

| user_id | 使用者 | 角色 |
| --- | --- | --- |
| U001 | 林佳蓉 | 系所管理員 |
| U002 | 陳柏宇 | 設備負責人 |
| U003 | 王小明 | 全系師生 |

測試登入密碼皆為 `0000`，但登入頁不顯示密碼提示。

## 7. 實際使用的資料庫物件

主要查詢頁面使用 View：

| 頁面 | View |
| --- | --- |
| 可借用設備 | `vw_Student_Available_Borrowable_Items` |
| 我的借用 | `vw_Student_Current_Borrowed_Items` |
| 可領用耗材 | `vw_Student_Available_Consumables` |
| 回報維修設備 | `vw_Student_Maintenance_Reportable_Items` |
| 可指派設備負責人 | `vw_Student_Maintenance_Handlers` |
| 設備負責人待辦工單 | `vw_Supervisor_Assigned_Maintenance_Tasks` |
| 設備負責人歷史工單 | `vw_Supervisor_Maintenance_History` |
| 全系資產盤點 | `vw_Admin_Asset_Master` |
| 全系維修工單 | `vw_Admin_Maintenance_Ticket_Master` |
| 審計軌跡 | `vw_Admin_Audit_Trail` |

寫入操作使用 Stored Procedure：

| 功能 | Stored Procedure |
| --- | --- |
| 借用設備 | `sp_borrow_item(p_internal_id, p_user_id, p_expected_return)` |
| 歸還設備 | `sp_return_item(p_record_id, p_operator_id, p_is_damaged)` |
| 領用耗材 | `sp_consume_item(p_internal_id, p_user_id, p_amount, p_purpose)` |
| 回報維修 | `sp_create_maintenance_ticket(p_internal_id, p_reporter_id, p_handler_id, p_vendor_id, p_issue_desc)` |
| 維修工單結案 | `sp_close_maintenance_ticket(p_ticket_id, p_operator_id, p_vendor_id, p_repair_cost, p_replaced_parts, p_next_maint_date, p_result, p_item_new_status)` |

目前 SQL 檔案尚未提供：

- `vw_Login_User_Role`：登入階段已依 Prompt 要求暫時使用 `USER JOIN ROLE`，並在程式註解標明。

新增 View：

- `vw_Student_Available_Consumables`：學生可領用耗材，只顯示耗材、可用、庫存量大於 0 的資料。
- `vw_Student_Current_Borrowed_Items`：學生目前借用中或逾期未歸還的設備，前端用 `user_id = session user_id` 篩選目前登入者。
- `vw_Student_Maintenance_Reportable_Items`：學生可回報維修設備，只顯示非耗材、非報廢、沒有未結案維修工單的設備。
- `vw_Student_Maintenance_Handlers`：學生報修時可指派的設備負責人清單。
- `vw_Supervisor_Maintenance_History`：設備負責人被指派的歷史工單，只包含已完成、取消。
- `vw_Admin_Maintenance_Ticket_Master`：系所管理員全系維修工單總覽，包含所有工單狀態。

維修工單 View 分工：

- `vw_Supervisor_Assigned_Maintenance_Tasks`：待辦工單，只顯示待處理、處理中，前端再用 `handler_id = session user_id` 篩選目前負責人。
- `vw_Supervisor_Maintenance_History`：歷史工單，只顯示已完成、取消，前端同樣用 `handler_id = session user_id` 篩選。
- `vw_Admin_Maintenance_Ticket_Master`：管理員全系維修工單總覽，顯示待處理、處理中、已完成、取消，可用狀態篩選。

耗材領用設計：

- 學生頁只查 `vw_Student_Available_Consumables`。
- 領用時只呼叫 `sp_consume_item`。
- Web 不直接 `UPDATE CONSUMABLE_DETAIL`，也不直接 `INSERT CONSUME_RECORD`。

設備歸還設計：

- 學生頁只查 `vw_Student_Current_Borrowed_Items`。
- 歸還前先用 View 確認 `record_id` 屬於目前登入者。
- 歸還時只呼叫 `sp_return_item`。
- Web 不直接 `UPDATE BORROW_RECORD`，也不直接 `UPDATE ITEM`。
- 若勾選「歸還時損壞」，Procedure 會把設備狀態改為 `維修中`，並同步建立 `待處理` 維修工單；未勾選則改回 `可用`。

學生回報維修設計：

- 學生頁只查 `vw_Student_Maintenance_Reportable_Items` 與 `vw_Student_Maintenance_Handlers`。
- 回報時只呼叫 `sp_create_maintenance_ticket`。
- Web 不直接 `INSERT MAINTENANCE_TICKET`，也不直接 `UPDATE ITEM`。
- 資料庫 Trigger / Procedure 會攔截耗材、報廢設備與重複未結案維修工單。

管理員補齊功能：

- 物品管理查詢既有 `ITEM`、`SPACE`、`ASSET_DETAIL`、`REUSABLE_EQUIPMENT`、`CONSUMABLE_DETAIL`，支援管理類型與狀態篩選。
- 耗材管理顯示全部耗材，不再只顯示低庫存耗材。
- 新增物品可建立財產設備、非列管設備、耗材三種資料，透過既有資料表寫入，不新增任何 DDL。
- 停用 / 報廢由管理員頁面更新 `ITEM.current_status`，並沿用既有 Trigger 寫入狀態異動審計紀錄。

## 8. 系統架構說明

- 查詢優先使用 View：學生、設備負責人與管理員盤點 / 工單 / 審計頁仍以 View 作為 ANSI-SPARC 外部層，負責欄位遮蔽與角色導向資料呈現。
- 管理員物品管理與完整耗材管理是本次「不修改資料庫、不新增 DDL」限制下的前端補齊功能，因此使用既有 Base Tables 與既有 Trigger 完成管理操作。
- 寫入使用 Stored Procedure：借用、領用、結案都透過 Procedure，Web 不直接 `INSERT`、`UPDATE`、`DELETE` Base Tables。
- Trigger 負責資料庫層商業規則攔截：例如耗材不可借用、報廢設備不可維修、狀態異動必須留下審計紀錄。
- Transaction / `FOR UPDATE` 負責併發一致性：借用、領用、結案流程在資料庫層使用交易與悲觀鎖，避免高併發下重複借用或庫存超發。
- Flask 使用 Session 模擬登入，測試階段以後端常數密碼 `0000` 驗證，登入頁不公開提示密碼。
- SQL 查詢使用參數化查詢，不使用 ORM。

## 9. 錄影測試步驟

以下步驟可以直接作為錄影展示流程。

若重錄管理員新增示範，請先重新初始化資料庫，或把 `DEMO-C001`、`DEMO-R001` 換成尚未使用過的新編號，避免主鍵重複。

### A. 展示資料庫初始化

1. 開啟 PowerShell。
2. 執行：

```powershell
cd "D:\code\114-2-DB_System-Project\Final Project Part III"
mysql -u root -p < 00_create_database.sql
mysql -u root -p equipment_management < 01_schema.sql
mysql -u root -p equipment_management < 02_transaction.sql
mysql -u root -p equipment_management < 04_test_seed_data.sql
mysql -u root -p equipment_management < 03_trigger.sql
mysql -u root -p equipment_management < 05_view.sql
mysql -u root -p equipment_management < 06_verify.sql
```

3. 說明：`02_transaction.sql` 建立 Stored Procedure，`03_trigger.sql` 建立 Trigger，`05_view.sql` 建立外部查詢 View。

若只更新 View 與驗證查詢，可執行：

```powershell
mysql -u root -p equipment_management < 05_view.sql
mysql -u root -p equipment_management < 06_verify.sql
```

### B. 展示啟動 Flask

1. 執行：

```powershell
cd D:\code\114-2-DB_System-Project\equipment_web
conda activate db
Copy-Item -Force .env.example .env
python app.py
```

2. 開啟 `http://127.0.0.1:5000`。

### C. 展示系所管理員

1. 在登入頁輸入 `U001`，密碼輸入 `0000`；確認登入頁沒有顯示測試密碼提示。
2. 進入「資產盤點」，確認管理員可看財產設備盤點清單。
3. 點選「物品管理」，使用「管理類型」與「狀態」篩選，確認可看到財產設備、非列管設備、耗材與各種狀態。
4. 點選「耗材管理」，確認畫面顯示全部耗材，正常庫存與低庫存都會出現。
5. 點選「新增物品」，在「新增耗材」區塊填入 `DEMO-C001`、`錄影測試耗材`、空間、目前庫存 `30`、最低庫存 `5`、單位 `包`，按下「新增耗材」。
6. 回到「耗材管理」，確認 `DEMO-C001` 出現在完整耗材清單。
7. 回到「物品管理」，找到 `DEMO-C001`，狀態異動選擇「停用」，原因填入 `錄影測試停用`，按下「套用」。
8. 點選「新增物品」，在「新增非列管設備」區塊填入 `DEMO-R001`、`錄影測試非列管設備`、規格 `錄影測試規格`、數量 `1`，按下「新增非列管設備」。
9. 回到「物品管理」，找到 `DEMO-R001`，狀態異動選擇「報廢」，原因填入 `錄影測試報廢`，按下「套用」。
10. 點選「維修工單」，使用狀態篩選「已完成」，確認管理員可看到已結案工單。
11. 點選「審計軌跡」，確認停用 / 報廢狀態異動留下紀錄。
12. 登出。

### D. 展示設備負責人結案

1. 使用 `U002` 登入，密碼輸入 `0000`。
2. 進入「待辦工單」。
3. 先點選「歷史工單」，展示已完成、取消工單來自 `vw_Supervisor_Maintenance_History`。
4. 回到「待辦工單」，找到工單 `1` 或任一待處理工單。
5. 填入：
   - 費用：`1200`
   - 更換零件：`噴頭模組`
   - 下次維護日期：`2026-12-31`
   - 狀態：`可用`
   - 維修結果：`已完成清潔與測試`
6. 按下「結案」。
7. 說明：Web 只呼叫 `sp_close_maintenance_ticket`，由 Procedure 內部 Transaction 與 Trigger 同步維修狀態、設備狀態與審計紀錄。
8. 再進入「歷史工單」，確認剛結案的工單出現在歷史清單。
9. 登出。

### E. 展示全系師生借用、領用與報修

1. 使用 `U003` 登入，密碼輸入 `0000`。
2. 進入「可借用設備」。
3. 選擇 `R001` 或任一列表中的可用設備。
4. 預計歸還時間填入未來時間，例如 `2027-12-31 17:00`。
5. 按下「借用」。
6. 說明：Web 只呼叫 `sp_borrow_item`，資料庫使用 `FOR UPDATE` 鎖定設備列，避免多人同時借到同一項設備。
7. 點選「我的借用」，展示剛借出的設備來自 `vw_Student_Current_Borrowed_Items`。
8. 不勾選「歸還時損壞」，按下「歸還」。
9. 說明：Web 只呼叫 `sp_return_item`，由資料庫交易把借用紀錄設為已歸還，並把設備狀態改回可用。
10. 點選「可領用耗材」，展示資料來自 `vw_Student_Available_Consumables`。
11. 選擇一筆耗材，填入數量 `1` 與用途 `課程測試`，按下「領用」。
12. 說明：Web 只呼叫 `sp_consume_item`，不直接更新庫存表。
13. 點選「回報維修」，展示資料來自 `vw_Student_Maintenance_Reportable_Items`。
14. 選擇一項可報修設備，例如 `A002`。
15. 選擇設備負責人 `U002`，故障描述填入 `畫面閃爍，請協助檢查`。
16. 按下「送出」。
17. 說明：Web 只呼叫 `sp_create_maintenance_ticket`，由資料庫交易建立工單並同步設備狀態為維修中。

### F. 展示權限控管

1. 保持 `U003` 登入。
2. 在網址列輸入 `http://127.0.0.1:5000/admin/assets`。
3. 系統會回傳 403，頁面顯示「權限不足」。
