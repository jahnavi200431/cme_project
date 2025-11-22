from flask import Flask, jsonify, request
import logging
import sys
import json
import psycopg2
import os

app = Flask(__name__)

# --------------------------
# JSON Logging (Cloud-friendly)
# --------------------------
class JsonFormatter(logging.Formatter):
    def format(self, record):
        log = {
            "severity": record.levelname,
            "app": "my-project-app-477009",
            "version": "1.0.0",
        }
        if isinstance(record.msg, dict):
            log.update(record.msg)
        else:
            log["message"] = record.getMessage()
        return json.dumps(log)

json_handler = logging.StreamHandler(sys.stdout)
json_handler.setFormatter(JsonFormatter())

root = logging.getLogger()
root.setLevel(logging.INFO)
root.handlers = []
root.addHandler(json_handler)

logger = logging.getLogger("my-project-app-477009")
logger.setLevel(logging.INFO)
logger.handlers = [json_handler]

# --------------------------
# DB and API key (direct)
# --------------------------
DB_HOST = os.getenv("DB_HOST", "127.0.0.1")  # connect via Cloud SQL Proxy
DB_PORT = int(os.getenv("DB_PORT", 5432))
DB_NAME = os.getenv("DB_NAME", "appdb")
DB_USER = os.getenv("DB_USER", "user1")
DB_PASS = os.getenv("DB_PASS", "postgres")  # direct password
API_KEY = os.getenv("API_KEY", "restapi123")  # direct API key

# --------------------------
# Database Connection
# --------------------------
def get_db_connection(check_only=False):
    try:
        conn = psycopg2.connect(
            host=DB_HOST,
            database=DB_NAME,
            user=DB_USER,
            password=DB_PASS,
            port=DB_PORT,
            connect_timeout=5
        )
        if not check_only:
            logger.info({"event": "db_connection_ok"})
        return conn
    except Exception as e:
        logger.error({"event": "db_connection_failed", "error": str(e)}, exc_info=True)
        return None

# --------------------------
# Table creation
# --------------------------
def create_table_if_not_exists():
    conn = get_db_connection()
    if not conn:
        logger.error({"event": "db_not_available_table_creation"})
        return
    try:
        cur = conn.cursor()
        cur.execute("""
            CREATE TABLE IF NOT EXISTS product (
                id SERIAL PRIMARY KEY,
                name VARCHAR(100) NOT NULL,
                description TEXT,
                price NUMERIC(10,2) NOT NULL,
                quantity INT DEFAULT 0,
                created_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP,
                updated_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP
            );
        """)
        conn.commit()

        # Insert initial products if empty
        cur.execute("SELECT COUNT(*) FROM product;")
        count = cur.fetchone()[0]
        if count == 0:
            cur.execute("""
                INSERT INTO product (name, description, price, quantity)
                VALUES
                ('Product A', 'First product', 10.50, 5),
                ('Product B', 'Second product', 20.00, 3);
            """)
            conn.commit()
            logger.info({"event": "initial_products_inserted"})
        logger.info({"event": "table_created_or_exists"})
    except Exception as e:
        logger.error({"event": "table_creation_error", "error": str(e)}, exc_info=True)
    finally:
        cur.close()
        conn.close()

# --------------------------
# API Key Check
# --------------------------
def require_api_key():
    provided_key = (
        request.headers.get("X-API-KEY")
        or request.headers.get("x-api-key")
        or request.headers.get("Authorization")
    )
    if API_KEY is None:
        logger.error({"event": "api_key_missing"})
        return False
    if provided_key != API_KEY:
        logger.warning({"event": "auth_failed", "provided_key": provided_key})
        return False
    return True

# --------------------------
# Health & Readiness
# --------------------------
@app.route('/health')
def health():
    return {"status": "healthy"}, 200

@app.route('/ready')
def readiness():
    conn = get_db_connection(check_only=True)
    if conn:
        conn.close()
        return {"status": "ready"}, 200
    return {"status": "not ready"}, 500

# --------------------------
# Routes
# --------------------------
@app.route("/")
def home():
    return {"message": "Welcome to Product API (GKE + Cloud SQL)"}, 200

@app.route("/products", methods=["GET"])
def get_products():
    conn = get_db_connection()
    if not conn:
        return {"error": "DB connection failed"}, 500
    try:
        cur = conn.cursor()
        cur.execute("SELECT * FROM product;")
        rows = cur.fetchall()
        columns = [desc[0] for desc in cur.description]
        return jsonify([dict(zip(columns, row)) for row in rows])
    finally:
        cur.close()
        conn.close()

@app.route("/products/<int:product_id>", methods=["GET"])
def get_product(product_id):
    conn = get_db_connection()
    if not conn:
        return {"error": "DB connection failed"}, 500
    try:
        cur = conn.cursor()
        cur.execute("SELECT * FROM product WHERE id=%s;", (product_id,))
        row = cur.fetchone()
        if not row:
            return {"error": "Product not found"}, 404
        columns = [desc[0] for desc in cur.description]
        return jsonify(dict(zip(columns, row)))
    finally:
        cur.close()
        conn.close()

@app.route("/products", methods=["POST"])
def add_product():
    if not require_api_key():
        return {"error": "Unauthorized"}, 401
    data = request.get_json()
    conn = get_db_connection()
    if not conn:
        return {"error": "DB connection failed"}, 500
    try:
        cur = conn.cursor()
        cur.execute("""
            INSERT INTO product (name, description, price, quantity)
            VALUES (%s, %s, %s, %s) RETURNING id;
        """, (data.get("name"), data.get("description"), float(data.get("price")), int(data.get("quantity", 0))))
        conn.commit()
        new_id = cur.fetchone()[0]
        return {"message": "Product added!", "id": new_id}, 201
    finally:
        cur.close()
        conn.close()

# --------------------------
# Main
# --------------------------
if __name__ == "__main__":
    logger.info({"event": "starting_server"})
    create_table_if_not_exists()
    port = int(os.getenv("PORT", 8080))
    app.run(host="0.0.0.0", port=port, debug=False)
