from flask import Flask, jsonify, request
import psycopg2
import os
import logging
import sys
import json

app = Flask(__name__)

# ---------------------------------------------------------
# JSON LOGGING (CLOUD LOGGING FRIENDLY)
# ---------------------------------------------------------
class JsonFormatter(logging.Formatter):
    def format(self, record):

        log = {
            "severity": record.levelname,
            "app": "gke-rest-api",
            "version": "1.0.0",
        }

        # If log message is already a dict → merge it
        if isinstance(record.msg, dict):
            log.update(record.msg)
        else:
            log["message"] = record.getMessage()

        return json.dumps(log)


json_handler = logging.StreamHandler(sys.stdout)
json_handler.setFormatter(JsonFormatter())

logger = logging.getLogger("gke-rest-api")
logger.setLevel(logging.INFO)
logger.handlers = [json_handler]

logging.getLogger("werkzeug").disabled = True


# ---------------------------------------------------------
# REQUEST LOGGING
# ---------------------------------------------------------
@app.before_request
def log_request():
    body = None
    try:
        if request.is_json:
            body = request.get_json()
    except:
        body = "<unreadable JSON>"

    logger.info({
        "event": "request",
        "method": request.method,
        "path": request.path,
        "remote_ip": request.remote_addr,
        "headers": dict(request.headers),
        "query_params": request.args.to_dict(),
        "body": body,
    })


# ---------------------------------------------------------
# RESPONSE LOGGING
# ---------------------------------------------------------
@app.after_request
def log_response(response):

    try:
        response_data = response.get_data().decode("utf-8")
    except:
        response_data = "<non-json response>"

    logger.info({
        "event": "response",
        "method": request.method,
        "path": request.path,
        "status": response.status_code,
        "response_body": response_data[:500]  # limit spam
    })

    return response


# ---------------------------------------------------------
# API KEY SECURITY
# ---------------------------------------------------------
API_KEY = os.getenv("API_KEY")


def require_api_key():

    provided_key = (
        request.headers.get("X-API-KEY") or
        request.headers.get("x-api-key") or
        request.headers.get("Authorization")
    )

    if API_KEY is None:
        logger.error({"event": "api_key_env_missing"})
        return False

    if provided_key != API_KEY:
        logger.warning({
            "event": "auth_failed",
            "received_key": provided_key
        })
        return False

    return True


# ---------------------------------------------------------
# HEALTH CHECKS
# ---------------------------------------------------------
@app.route('/health', methods=['GET'])
def health():
    return {"status": "healthy"}, 200


@app.route('/ready', methods=['GET'])
def readiness():
    conn = get_db_connection(check_only=True)
    if conn:
        conn.close()
        return {"status": "ready"}, 200
    return {"status": "not ready"}, 500


# ---------------------------------------------------------
# DATABASE CONFIG
# ---------------------------------------------------------
DB_HOST = os.getenv("DB_HOST")
DB_NAME = os.getenv("DB_NAME")
DB_USER = os.getenv("DB_USER")
DB_PASS = os.getenv("DB_PASS")
DB_PORT = os.getenv("DB_PORT", "5432")


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
            logger.info({"event": "db_connection", "status": "success"})
        return conn
    except Exception as e:
        logger.error({
            "event": "db_connection_failed",
            "error": str(e)
        })
        return None


def create_table_if_not_exists():
    conn = get_db_connection()
    if not conn:
        return

    try:
        cur = conn.cursor()
        cur.execute("""
            CREATE TABLE IF NOT EXISTS product (
                id SERIAL PRIMARY KEY,
                name VARCHAR(100) NOT NULL,
                description TEXT,
                price NUMERIC(10,2) NOT NULL,
                quantity INT DEFAULT 0
            );
        """)
        conn.commit()
        logger.info({"event": "table_created"})
    except Exception as e:
        logger.error({
            "event": "table_creation_error",
            "error": str(e)
        })
    finally:
        cur.close()
        conn.close()


@app.route("/")
def home():
    return {"message": "Welcome to Product API (GKE + Cloud SQL)"}, 200


# ---------------------------------------------------------
# PUBLIC ROUTES
# ---------------------------------------------------------
@app.route("/products", methods=["GET"])
def get_products():
    conn = get_db_connection()
    if not conn:
        return {"error": "Database connection failed"}, 500

    try:
        cur = conn.cursor()
        cur.execute("SELECT * FROM product;")
        rows = cur.fetchall()
        columns = [desc[0] for desc in cur.description]
        return jsonify([dict(zip(columns, row))])
    finally:
        cur.close()
        conn.close()


@app.route("/products/<int:product_id>", methods=["GET"])
def get_product(product_id):
    conn = get_db_connection()
    if not conn:
        return {"error": "Database connection failed"}, 500

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


# ---------------------------------------------------------
# PROTECTED ROUTES (API KEY REQUIRED)
# ---------------------------------------------------------
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
            VALUES (%s, %s, %s, %s)
            RETURNING id;
        """, (
            data.get("name"),
            data.get("description"),
            data.get("price"),
            data.get("quantity", 0)
        ))
        conn.commit()
        new_id = cur.fetchone()[0]
        return {"message": "Product added!", "id": new_id}, 201
    finally:
        cur.close()
        conn.close()


@app.route("/products/<int:product_id>", methods=["PUT"])
def update_product(product_id):

    if not require_api_key():
        return {"error": "Unauthorized"}, 401

    data = request.get_json()

    conn = get_db_connection()
    if not conn:
        return {"error": "DB connection failed"}, 500

    try:
        cur = conn.cursor()
        cur.execute("SELECT id FROM product WHERE id=%s;", (product_id,))
        if not cur.fetchone():
            return {"error": "Product not found"}, 404

        cur.execute("""
            UPDATE product
            SET name=%s, description=%s, price=%s, quantity=%s
            WHERE id=%s;
        """, (
            data.get("name"),
            data.get("description"),
            data.get("price"),
            data.get("quantity"),
            product_id
        ))
        conn.commit()
        return {"message": "Product updated!"}, 200
    finally:
        cur.close()
        conn.close()


@app.route("/products/<int:product_id>", methods=["DELETE"])
def delete_product(product_id):

    if not require_api_key():
        return {"error": "Unauthorized"}, 401

    conn = get_db_connection()
    if not conn:
        return {"error": "DB connection failed"}, 500

    try:
        cur = conn.cursor()
        cur.execute("SELECT id FROM product WHERE id=%s;", (product_id,))
        if not cur.fetchone():
            return {"error": "Product not found"}, 404

        cur.execute("DELETE FROM product WHERE id=%s;", (product_id,))
        conn.commit()
        return {"message": "Product deleted!"}, 200
    finally:
        cur.close()
        conn.close()


# ---------------------------------------------------------
# START SERVER
# ---------------------------------------------------------
if __name__ == "__main__":
    logger.info({"event": "starting_server"})

    if os.getenv("INIT_DB_ONLY") == "true":
        create_table_if_not_exists()
        sys.exit(0)

    create_table_if_not_exists()

    port = int(os.getenv("PORT", 8080))
    app.run(host="0.0.0.0", port=port, debug=False)
