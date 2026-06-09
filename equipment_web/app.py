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

from db import fetch_all, format_db_error, get_connection, get_login_user


load_dotenv()

app = Flask(__name__)
app.secret_key = os.getenv("FLASK_SECRET_KEY", "dev_only_replace_this_secret_key")


ROLE_STUDENT = "全系師生"
ROLE_SUPERVISOR = "設備負責人"
ROLE_ADMIN = "系所管理員"


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


@app.route("/")
def index():
    if "user_id" in session:
        return redirect(dashboard_url(session.get("role_name")))
    return redirect(url_for("login"))


@app.route("/login", methods=["GET", "POST"])
def login():
    if request.method == "POST":
        user_id = request.form.get("user_id", "").strip()
        if not user_id:
            flash("請輸入 user_id。", "warning")
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
    return render_template("supervisor_tasks.html", rows=rows)


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
        "CALL sp_close_maintenance_ticket(%s, %s, %s, %s, %s, %s, %s)",
        (
            ticket_id,
            session["user_id"],
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


@app.route("/admin/consumables")
@role_required(ROLE_ADMIN)
def admin_consumables():
    rows = fetch_all(
        """
        SELECT *
        FROM vw_Admin_Consumable_Alert
        ORDER BY alert_level, internal_id
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
