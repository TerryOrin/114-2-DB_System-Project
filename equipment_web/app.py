from datetime import datetime
import os
from functools import wraps

import pymysql
from dotenv import load_dotenv
from flask import (
    Flask,
    abort,
    flash,
    redirect,
    render_template,
    request,
    session,
    url_for,
)

from db import fetch_all, fetch_one, format_db_error, get_connection, get_login_user


load_dotenv()

app = Flask(__name__)
app.secret_key = os.getenv("FLASK_SECRET_KEY", "dev_only_replace_this_secret_key")


ROLE_STUDENT = "全系師生"
ROLE_SUPERVISOR = "設備負責人"
ROLE_ADMIN = "系所管理員"
TEST_LOGIN_PASSWORD = "0000"
ITEM_STATUSES = ["可用", "借出中", "維修中", "停用", "報廢", "遺失"]
ADMIN_CREATE_STATUSES = ["可用", "停用"]
ADMIN_STATUS_ACTIONS = {"停用", "報廢"}


def dashboard_url(role_name):
    if role_name == ROLE_ADMIN:
        return url_for("admin_assets")
    if role_name == ROLE_SUPERVISOR:
        return url_for("supervisor_tasks")
    return url_for("student_items")


def login_required(view_func):
    @wraps(view_func)
    def wrapper(*args, **kwargs):
        if "user_id" not in session:
            flash("請先登入系統。", "warning")
            return redirect(url_for("login"))
        return view_func(*args, **kwargs)

    return wrapper


def role_required(*allowed_roles):
    def decorator(view_func):
        @wraps(view_func)
        def wrapper(*args, **kwargs):
            if "user_id" not in session:
                flash("請先登入系統。", "warning")
                return redirect(url_for("login"))

            role_name = session.get("role_name")
            if role_name in allowed_roles:
                return view_func(*args, **kwargs)

            abort(403)

        return wrapper

    return decorator


def normalize_datetime_local(value):
    if not value:
        return None
    try:
        parsed = datetime.strptime(value, "%Y-%m-%dT%H:%M")
        return parsed.strftime("%Y-%m-%d %H:%M:%S")
    except ValueError:
        return value.replace("T", " ")


def normalize_blank(value):
    if value is None:
        return None
    value = value.strip()
    return value or None


def parse_int_form(name, label, min_value=None, required=True):
    raw_value = request.form.get(name, "").strip()
    if not raw_value:
        if required:
            raise ValueError(f"{label}為必填。")
        return None
    try:
        value = int(raw_value)
    except ValueError as exc:
        raise ValueError(f"{label}必須是整數。") from exc
    if min_value is not None and value < min_value:
        raise ValueError(f"{label}不可小於 {min_value}。")
    return value


def call_procedure(sql, params, success_message, redirect_endpoint, **redirect_values):
    conn = get_connection()
    try:
        with conn.cursor() as cursor:
            cursor.execute(sql, params)
        conn.commit()
        flash(success_message, "success")
    except pymysql.err.MySQLError as error:
        conn.rollback()
        flash(f"操作失敗：{format_db_error(error)}", "danger")
    finally:
        conn.close()
    return redirect(url_for(redirect_endpoint, **redirect_values))


def load_admin_form_options():
    spaces = fetch_all(
        """
        SELECT space_id, space_name, location_type
        FROM SPACE
        ORDER BY space_id
        """
    )
    users = fetch_all(
        """
        SELECT user_id, user_name
        FROM `USER`
        ORDER BY user_id
        """
    )
    return spaces, users


def load_vendors():
    return fetch_all(
        """
        SELECT vendor_id, vendor_name, vendor_contact
        FROM VENDOR
        ORDER BY vendor_id
        """
    )


@app.route("/")
def index():
    if "user_id" in session:
        return redirect(dashboard_url(session.get("role_name")))
    return redirect(url_for("login"))


@app.route("/login", methods=["GET", "POST"])
def login():
    if request.method == "POST":
        user_id = request.form.get("user_id", "").strip()
        password = request.form.get("password", "")
        if not user_id:
            flash("請輸入 user_id。", "warning")
            return render_template("login.html")

        if password != TEST_LOGIN_PASSWORD:
            flash("密碼錯誤。", "danger")
            return render_template("login.html")

        try:
            user = get_login_user(user_id)
        except pymysql.err.MySQLError as error:
            flash(f"登入失敗：{format_db_error(error)}", "danger")
            return render_template("login.html")

        if not user:
            flash("查無此使用者。", "danger")
            return render_template("login.html")

        session.clear()
        session["user_id"] = user["user_id"]
        session["user_name"] = user["user_name"]
        session["role_name"] = user["role_name"]
        flash("登入成功。", "success")
        return redirect(dashboard_url(user["role_name"]))

    return render_template("login.html")


@app.route("/logout")
def logout():
    session.clear()
    flash("已登出系統。", "info")
    return redirect(url_for("login"))


@app.route("/student/items")
@role_required(ROLE_STUDENT)
def student_items():
    rows = fetch_all(
        """
        SELECT *
        FROM vw_Student_Available_Borrowable_Items
        ORDER BY internal_id
        """
    )
    return render_template("student_items.html", rows=rows)


@app.route("/student/borrow/<internal_id>", methods=["POST"])
@role_required(ROLE_STUDENT)
def borrow_item(internal_id):
    expected_return = normalize_datetime_local(request.form.get("expected_return"))
    return call_procedure(
        "CALL sp_borrow_item(%s, %s, %s)",
        (internal_id, session["user_id"], expected_return),
        "借用申請已完成，資料庫交易已提交。",
        "student_items",
    )


@app.route("/student/returns")
@role_required(ROLE_STUDENT)
def student_returns():
    rows = fetch_all(
        """
        SELECT *
        FROM vw_Student_Current_Borrowed_Items
        WHERE user_id = %s
        ORDER BY borrow_time DESC, record_id DESC
        """,
        (session["user_id"],),
    )
    return render_template("student_returns.html", rows=rows)


@app.route("/student/return/<int:record_id>", methods=["POST"])
@role_required(ROLE_STUDENT)
def return_item(record_id):
    borrowed = fetch_one(
        """
        SELECT record_id
        FROM vw_Student_Current_Borrowed_Items
        WHERE record_id = %s
          AND user_id = %s
        """,
        (record_id, session["user_id"]),
    )
    if not borrowed:
        flash("查無可歸還的借用紀錄，或此紀錄不屬於目前登入者。", "danger")
        return redirect(url_for("student_returns"))

    is_damaged = 1 if request.form.get("is_damaged") == "1" else 0
    return call_procedure(
        "CALL sp_return_item(%s, %s, %s)",
        (record_id, session["user_id"], is_damaged),
        "歸還完成，設備狀態已由資料庫交易同步更新。",
        "student_returns",
    )


@app.route("/student/consumables")
@role_required(ROLE_STUDENT)
def student_consumables():
    rows = fetch_all(
        """
        SELECT *
        FROM vw_Student_Available_Consumables
        ORDER BY internal_id
        """
    )
    return render_template("student_consumables.html", rows=rows)


@app.route("/student/consume/<internal_id>", methods=["POST"])
@role_required(ROLE_STUDENT)
def consume_item(internal_id):
    try:
        amount = int(request.form.get("amount", "0"))
    except ValueError:
        flash("領用數量必須是整數。", "danger")
        return redirect(url_for("student_consumables"))

    purpose = request.form.get("purpose", "").strip()
    if not purpose:
        flash("請填寫領用用途。", "warning")
        return redirect(url_for("student_consumables"))

    return call_procedure(
        "CALL sp_consume_item(%s, %s, %s, %s)",
        (internal_id, session["user_id"], amount, purpose),
        "耗材領用已完成，庫存已由資料庫交易同步更新。",
        "student_consumables",
    )


@app.route("/student/maintenance/report")
@role_required(ROLE_STUDENT)
def student_maintenance_report():
    rows = fetch_all(
        """
        SELECT *
        FROM vw_Student_Maintenance_Reportable_Items
        ORDER BY internal_id
        """
    )
    handlers = fetch_all(
        """
        SELECT *
        FROM vw_Student_Maintenance_Handlers
        ORDER BY handler_id
        """
    )
    vendors = load_vendors()
    return render_template(
        "student_maintenance_report.html",
        rows=rows,
        handlers=handlers,
        vendors=vendors,
    )


@app.route("/student/maintenance/report/<internal_id>", methods=["POST"])
@role_required(ROLE_STUDENT)
def create_maintenance_ticket(internal_id):
    handler_id = request.form.get("handler_id", "").strip()
    try:
        vendor_id = parse_int_form("vendor_id", "委託廠商", min_value=1)
    except ValueError as error:
        flash(str(error), "warning")
        return redirect(url_for("student_maintenance_report"))

    issue_desc = request.form.get("issue_desc", "").strip()

    if not handler_id:
        flash("請選擇設備負責人。", "warning")
        return redirect(url_for("student_maintenance_report"))

    if not issue_desc:
        flash("請填寫故障描述。", "warning")
        return redirect(url_for("student_maintenance_report"))

    return call_procedure(
        "CALL sp_create_maintenance_ticket(%s, %s, %s, %s, %s)",
        (internal_id, session["user_id"], handler_id, vendor_id, issue_desc),
        "維修工單已送出，設備狀態已由資料庫交易同步更新。",
        "student_maintenance_report",
    )


@app.route("/supervisor/tasks")
@role_required(ROLE_SUPERVISOR)
def supervisor_tasks():
    rows = fetch_all(
        """
        SELECT *
        FROM vw_Supervisor_Assigned_Maintenance_Tasks
        WHERE handler_id = %s
        ORDER BY repair_time DESC, ticket_id DESC
        """,
        (session["user_id"],),
    )
    vendors = load_vendors()
    return render_template("supervisor_tasks.html", rows=rows, vendors=vendors)


@app.route("/supervisor/history")
@role_required(ROLE_SUPERVISOR)
def supervisor_history():
    rows = fetch_all(
        """
        SELECT *
        FROM vw_Supervisor_Maintenance_History
        WHERE handler_id = %s
        ORDER BY resolved_time DESC, ticket_id DESC
        """,
        (session["user_id"],),
    )
    return render_template("supervisor_history.html", rows=rows)


@app.route("/supervisor/tasks/<int:ticket_id>/close", methods=["POST"])
@role_required(ROLE_SUPERVISOR)
def close_maintenance_ticket(ticket_id):
    try:
        vendor_id = parse_int_form("vendor_id", "委託廠商", min_value=1)
    except ValueError as error:
        flash(str(error), "warning")
        return redirect(url_for("supervisor_tasks"))

    try:
        repair_cost = int(request.form.get("repair_cost", "0") or 0)
    except ValueError:
        flash("維修費用必須是整數。", "danger")
        return redirect(url_for("supervisor_tasks"))

    replaced_parts = request.form.get("replaced_parts", "").strip() or None
    next_maint_date = request.form.get("next_maint_date", "").strip() or None
    result = request.form.get("result", "").strip()
    item_new_status = request.form.get("item_new_status", "可用").strip()

    if not result:
        flash("請填寫維修結果。", "warning")
        return redirect(url_for("supervisor_tasks"))

    return call_procedure(
        "CALL sp_close_maintenance_ticket(%s, %s, %s, %s, %s, %s, %s, %s)",
        (
            ticket_id,
            session["user_id"],
            vendor_id,
            repair_cost,
            replaced_parts,
            next_maint_date,
            result,
            item_new_status,
        ),
        "維修工單已結案，設備狀態已由資料庫交易同步更新。",
        "supervisor_tasks",
    )


@app.route("/admin/assets")
@role_required(ROLE_ADMIN)
def admin_assets():
    rows = fetch_all(
        """
        SELECT *
        FROM vw_Admin_Asset_Master
        ORDER BY internal_id
        """
    )
    return render_template("admin_assets.html", rows=rows)


@app.route("/admin/items")
@role_required(ROLE_ADMIN)
def admin_items():
    manage_type = request.args.get("type", "").strip()
    status = request.args.get("status", "").strip()

    conditions = []
    params = []
    if manage_type in {"財產設備", "非列管設備", "耗材"}:
        conditions.append("i.manage_type = %s")
        params.append(manage_type)
    else:
        manage_type = ""

    if status in ITEM_STATUSES:
        conditions.append("i.current_status = %s")
        params.append(status)
    else:
        status = ""

    where_clause = ""
    if conditions:
        where_clause = "WHERE " + " AND ".join(conditions)

    rows = fetch_all(
        f"""
        SELECT
            i.internal_id,
            i.item_name,
            i.manage_type,
            i.current_status,
            i.warranty_expiry,
            s.space_name,
            s.location_type,
            a.asset_id,
            c.stock_quantity,
            c.min_stock,
            c.unit,
            r.quantity,
            r.is_borrowable,
            r.need_return
        FROM ITEM i
        JOIN SPACE s ON i.space_id = s.space_id
        LEFT JOIN ASSET_DETAIL a ON i.internal_id = a.internal_id
        LEFT JOIN CONSUMABLE_DETAIL c ON i.internal_id = c.internal_id
        LEFT JOIN REUSABLE_EQUIPMENT r ON i.internal_id = r.internal_id
        {where_clause}
        ORDER BY i.manage_type, i.internal_id
        """,
        tuple(params),
    )
    return render_template(
        "admin_items.html",
        rows=rows,
        selected_type=manage_type,
        selected_status=status,
        manage_types=["財產設備", "非列管設備", "耗材"],
        statuses=ITEM_STATUSES,
    )


@app.route("/admin/items/new", methods=["GET", "POST"])
@role_required(ROLE_ADMIN)
def admin_item_new():
    spaces, users = load_admin_form_options()

    if request.method == "POST":
        manage_type = request.form.get("manage_type", "").strip()
        internal_id = request.form.get("internal_id", "").strip()
        item_name = request.form.get("item_name", "").strip()
        current_status = request.form.get("current_status", "可用").strip()
        warranty_expiry = normalize_blank(request.form.get("warranty_expiry"))
        space_id = request.form.get("space_id", "").strip()

        if manage_type not in {"財產設備", "非列管設備", "耗材"}:
            flash("管理類型不正確。", "danger")
            return redirect(url_for("admin_item_new"))
        if current_status not in ADMIN_CREATE_STATUSES:
            flash("新增物品時狀態只能是可用或停用。", "danger")
            return redirect(url_for("admin_item_new"))
        if not internal_id or not item_name or not space_id:
            flash("內部唯一編號、物品名稱與存放空間皆為必填。", "warning")
            return redirect(url_for("admin_item_new"))

        conn = get_connection()
        try:
            with conn.cursor() as cursor:
                cursor.execute(
                    """
                    INSERT INTO ITEM (
                        internal_id, item_name, manage_type, current_status,
                        warranty_expiry, space_id, created_by_user_id
                    ) VALUES (%s, %s, %s, %s, %s, %s, %s)
                    """,
                    (
                        internal_id,
                        item_name,
                        manage_type,
                        current_status,
                        warranty_expiry,
                        space_id,
                        session["user_id"],
                    ),
                )

                if manage_type == "財產設備":
                    asset_id = request.form.get("asset_id", "").strip()
                    custodian_id = request.form.get("custodian_id", "").strip()
                    if not asset_id or not custodian_id:
                        raise ValueError("財產編號與保管人皆為必填。")

                    acquired_cost = parse_int_form("acquired_cost", "取得金額", min_value=3000)
                    lifespan_years = parse_int_form("lifespan_years", "耐用年限", min_value=1)
                    cursor.execute(
                        """
                        INSERT INTO ASSET_DETAIL (
                            asset_id, internal_id, fund_source, acquired_date,
                            acquired_cost, lifespan_years, custodian_id
                        ) VALUES (%s, %s, %s, %s, %s, %s, %s)
                        """,
                        (
                            asset_id,
                            internal_id,
                            normalize_blank(request.form.get("fund_source")),
                            normalize_blank(request.form.get("acquired_date")),
                            acquired_cost,
                            lifespan_years,
                            custodian_id,
                        ),
                    )
                elif manage_type == "非列管設備":
                    specification = request.form.get("specification", "").strip()
                    if not specification:
                        raise ValueError("規格為必填。")

                    quantity = parse_int_form("quantity", "數量", min_value=0)
                    cursor.execute(
                        """
                        INSERT INTO REUSABLE_EQUIPMENT (
                            internal_id, specification, quantity,
                            is_borrowable, need_return
                        ) VALUES (%s, %s, %s, %s, %s)
                        """,
                        (
                            internal_id,
                            specification,
                            quantity,
                            1 if request.form.get("is_borrowable") == "1" else 0,
                            1 if request.form.get("need_return") == "1" else 0,
                        ),
                    )
                else:
                    unit = request.form.get("unit", "").strip()
                    if not unit:
                        raise ValueError("單位為必填。")

                    stock_quantity = parse_int_form("stock_quantity", "目前庫存", min_value=0)
                    min_stock = parse_int_form("min_stock", "最低庫存", min_value=0)
                    cursor.execute(
                        """
                        INSERT INTO CONSUMABLE_DETAIL (
                            internal_id, stock_quantity, min_stock, unit
                        ) VALUES (%s, %s, %s, %s)
                        """,
                        (
                            internal_id,
                            stock_quantity,
                            min_stock,
                            unit,
                        ),
                    )
            conn.commit()
            flash("物品已建立。", "success")
            return redirect(url_for("admin_items"))
        except ValueError as error:
            conn.rollback()
            flash(str(error), "danger")
        except pymysql.err.MySQLError as error:
            conn.rollback()
            flash(f"建立失敗：{format_db_error(error)}", "danger")
        finally:
            conn.close()

    return render_template(
        "admin_item_new.html",
        spaces=spaces,
        users=users,
        statuses=ADMIN_CREATE_STATUSES,
    )


@app.route("/admin/items/<internal_id>/status", methods=["POST"])
@role_required(ROLE_ADMIN)
def admin_update_item_status(internal_id):
    new_status = request.form.get("status", "").strip()
    reason = request.form.get("reason", "").strip()

    if new_status not in ADMIN_STATUS_ACTIONS:
        flash("狀態異動只能選擇停用或報廢。", "danger")
        return redirect(url_for("admin_items"))

    if not reason:
        reason = f"管理員將物品狀態改為{new_status}"

    conn = get_connection()
    try:
        with conn.cursor() as cursor:
            cursor.execute(
                """
                SELECT current_status
                FROM ITEM
                WHERE internal_id = %s
                FOR UPDATE
                """,
                (internal_id,),
            )
            item = cursor.fetchone()
            if not item:
                flash("查無此物品。", "danger")
                conn.rollback()
                return redirect(url_for("admin_items"))

            if item["current_status"] == new_status:
                flash("物品已是該狀態，未進行異動。", "info")
                conn.rollback()
                return redirect(url_for("admin_items"))

            cursor.execute("SET @app_user_id = %s", (session["user_id"],))
            cursor.execute("SET @status_reason = %s", (reason,))
            cursor.execute(
                """
                UPDATE ITEM
                SET current_status = %s
                WHERE internal_id = %s
                """,
                (new_status, internal_id),
            )
            conn.commit()
            flash(f"物品已改為{new_status}。", "success")
    except pymysql.err.MySQLError as error:
        conn.rollback()
        flash(f"狀態異動失敗：{format_db_error(error)}", "danger")
    finally:
        conn.close()

    return redirect(url_for("admin_items"))


@app.route("/admin/consumables")
@role_required(ROLE_ADMIN)
def admin_consumables():
    rows = fetch_all(
        """
        SELECT
            i.internal_id,
            i.item_name,
            i.current_status,
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
        JOIN ITEM i ON c.internal_id = i.internal_id
        JOIN SPACE s ON i.space_id = s.space_id
        ORDER BY i.current_status, i.internal_id
        """
    )
    return render_template("admin_consumables.html", rows=rows)


@app.route("/admin/maintenance")
@role_required(ROLE_ADMIN)
def admin_maintenance():
    status = request.args.get("status", "").strip()
    allowed_statuses = {"待處理", "處理中", "已完成", "取消"}

    if status and status not in allowed_statuses:
        flash("維修狀態篩選條件不正確，已顯示全部工單。", "warning")
        status = ""

    if status:
        rows = fetch_all(
            """
            SELECT *
            FROM vw_Admin_Maintenance_Ticket_Master
            WHERE maint_status = %s
            ORDER BY repair_time DESC, ticket_id DESC
            """,
            (status,),
        )
    else:
        rows = fetch_all(
            """
            SELECT *
            FROM vw_Admin_Maintenance_Ticket_Master
            ORDER BY repair_time DESC, ticket_id DESC
            """
        )

    return render_template(
        "admin_maintenance.html",
        rows=rows,
        selected_status=status,
        statuses=["待處理", "處理中", "已完成", "取消"],
    )


@app.route("/admin/audit")
@role_required(ROLE_ADMIN)
def admin_audit():
    rows = fetch_all(
        """
        SELECT *
        FROM vw_Admin_Audit_Trail
        ORDER BY event_time DESC
        """
    )
    return render_template("admin_audit.html", rows=rows)


@app.errorhandler(pymysql.err.MySQLError)
def handle_database_error(error):
    flash(f"資料庫錯誤：{format_db_error(error)}", "danger")
    return redirect(url_for("index"))


@app.errorhandler(403)
def handle_forbidden(error):
    return render_template("403.html"), 403


if __name__ == "__main__":
    app.run(host="127.0.0.1", port=5000, debug=False)
