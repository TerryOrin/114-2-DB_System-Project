import os

import pymysql
from dotenv import load_dotenv


load_dotenv()


def get_connection():
    return pymysql.connect(
        host=os.getenv("DB_HOST", "localhost"),
        port=int(os.getenv("DB_PORT", "3306")),
        user=os.getenv("DB_USER", "root"),
        password=os.getenv("DB_PASSWORD", ""),
        database=os.getenv("DB_NAME", "equipment_management"),
        charset="utf8mb4",
        cursorclass=pymysql.cursors.DictCursor,
        autocommit=False,
        ssl_disabled=True
    )


def fetch_all(sql, params=None):
    conn = get_connection()
    try:
        with conn.cursor() as cursor:
            cursor.execute(sql, params or ())
            return cursor.fetchall()
    finally:
        conn.close()


def fetch_one(sql, params=None):
    conn = get_connection()
    try:
        with conn.cursor() as cursor:
            cursor.execute(sql, params or ())
            return cursor.fetchone()
    finally:
        conn.close()


def view_exists(view_name):
    row = fetch_one(
        """
        SELECT COUNT(*) AS view_count
        FROM information_schema.VIEWS
        WHERE TABLE_SCHEMA = DATABASE()
          AND TABLE_NAME = %s
        """,
        (view_name,),
    )
    return bool(row and row["view_count"] > 0)


def get_login_user(user_id):
    if view_exists("vw_Login_User_Role"):
        return fetch_one(
            """
            SELECT user_id, user_name, role_name
            FROM vw_Login_User_Role
            WHERE user_id = %s
            """,
            (user_id,),
        )

    # 暫時性例外：目前 05_view.sql 尚未提供 vw_Login_User_Role。
    # 依作業 Prompt 規定，登入階段可先使用 USER JOIN ROLE 查詢身分。
    return fetch_one(
        """
        SELECT u.user_id, u.user_name, r.role_name
        FROM `USER` u
        JOIN ROLE r ON u.role_id = r.role_id
        WHERE u.user_id = %s
        """,
        (user_id,),
    )


def format_db_error(error):
    if getattr(error, "args", None):
        if len(error.args) >= 2:
            return str(error.args[1])
        return str(error.args[0])
    return str(error)
