from flask import Flask, jsonify, request
import psycopg2
import os
import logging
import sys
import json

app = Flask(__name__)

# -------------------------------------------------------------------
# ✅ JSON Structured Logging Formatter
# -------------------------------------------------------------------

class JsonFormatter(logging.Formatter):
    def format(self, record):
        log = {
            "severity": record.levelname,
            "message": record.getMessage(),
            "app": "gke-rest-api",
            "version": "1.0.0"
        }

        # Add all extra fields sent via extra={}
        for key, value in record.__dict__.items():
            if key not in (
                "args", "msg", "levelname", "levelno", "pathname",
                "filename", "module", "exc_info", "exc_text",
                "stack_info", "lineno", "created", "msecs"
            ):
                log[key] = value

        return json.dumps(log)


# Configure logger
json_handler = logging.StreamHandler(sys.stdout)
json_handler.setFormatter(JsonFormatter())

logger = logging.getLogger("gke-rest-api")
logger.setLevel(logging.INFO)
logger.handlers = [json_handler]
logger.propagate = False

# Disable werkzeug logs
logging.getLogger("werkzeug").disabled = True


# -------------------------------------------------------------------
# ✅ Request & Response Logging
# -------------------------------------------------------------------

@app.before_request
def log_request():
    logger.info(
        "request_received",
        extra={
            "event": "request",
            "method": request.method,
            "path": request.path,
            "remote_ip": request.remote_addr
        }
    )


@app.after_request
def log_response(response):
    logger.info(
        "response_sent",
        extra={
            "event": "response",
            "method": request.method,
            "path": request.path,
            "status": response.status_code
        }
    )
    return response


# -------------------------------------------------------------------
# ✅ Health + Readiness Checks
# -------------------------------------------------------------------

@app.route('/health', methods=['GET'])
def health():
    logger.info("health_check", extra={"event": "health_check", "status": "ok"})
    return {"status": "healthy"}, 200


@app.route('/ready', methods=['GET'])
def readiness():
    conn = get_db_connection(check_only=True)
    ready = bool(conn)

    logger.info(
        "readiness_check",
        extra={"event": "readiness_check", "status": "ready" if ready else "not_ready"}
    )

    if conn:
        conn.close()
        return {"status": "ready"}, 200
    return {"status": "not ready"}, 500


# -------------------------------------------------------------------
# ✅ Database Configuration
# -------------------------------------------------------------------

DB_HOST = os.getenv("DB_HOST", "136.115.254.71")
DB_NAME = os.getenv("DB_NAME", "productdb")
DB_USER = os.getenv("DB_USER", "postgres")
DB_PASS = os.getenv("DB_PASS", "postgres")
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
            logger.info("db_connection_success", extra={"event": "db_connection", "status": "success"})
        return conn
    except Exception as e:
        logger.error("db_connection_failed", extra={"event": "db_connection_failed", "error": str(e)})
        return None


# -------------------------------------------------------------------
# ✅ Create Table If Not Exists
# -------------------------------------------------------------------

def create_table_if_not_exists():
    conn = get_db_connection()
    if not conn:
        logger.error("table_create_failed", extra={"event": "table_create_failed", "reason": "db_down"})
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

        logger.info("table_created", extra={"event": "table_created", "table": "product"})
    except Exception as e:
        logger.error("table_create_error", extra={"event": "table_create_error", "error": str(e)})
    finally:
        cur.close()
        conn.close()


# -------------------------------------------------------------------
# ✅ API Routes
# -------------------------------------------------------------------

@app.route("/")
def home():
    return jsonify({"message": "Welcome to the Product API (Cloud SQL connected)"})


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
        return jsonify([dict(zip(columns, row)) for row in rows])
    except Exception as e:
        return {"error": str(e)}, 500
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
        col_names = [desc[0] for desc in cur.description]
        return dict(zip(col_names, row))
    except Exception as e:
        return {"error": str(e)}, 500
    finally:
        cur.close()
        conn.close()


@app.route("/products", methods=["POST"])
def add_product():
    data = request.get_json()

    name = data.get("name")
    description = data.get("description")
    price = data.get("price")
    quantity = data.get("quantity", 0)

    if not name or price is None:
        return {"error": "Name and price are required"}, 400

    conn = get_db_connection()
    if not conn:
        return {"error": "Database connection failed"}, 500

    try:
        cur = conn.cursor()
        cur.execute("""
            INSERT INTO product (name, description, price, quantity)
            VALUES (%s, %s, %s, %s)
            RETURNING id;
        """, (name, description, price, quantity))
        conn.commit()
        new_id = cur.fetchone()[0]

        return {"message": "Product added", "id": new_id}, 201
    except Exception as e:
        return {"error": str(e)}, 500
    finally:
        cur.close()
        conn.close()


@app.route("/products/<int:product_id>", methods=["PUT"])
def update_product(product_id):
    data = request.get_json()

    conn = get_db_connection()
    if not conn:
        return {"error": "Database connection failed"}, 500

    try:
        cur = conn.cursor()
        cur.execute("SELECT id FROM product WHERE id=%s;", (product_id,))
        if not cur.fetchone():
            return {"error": "Product not found"}, 404

        cur.execute("""
            UPDATE product
            SET name=%s, description=%s, price=%s, quantity=%s
            WHERE id=%s;
        """, (data.get("name"), data.get("description"),
              data.get("price"), data.get("quantity"), product_id))
        conn.commit()

        return {"message": f"Product {product_id} updated"}
    except Exception as e:
        return {"error": str(e)}, 500
    finally:
        cur.close()
        conn.close()


@app.route("/products/<int:product_id>", methods=["DELETE"])
def delete_product(product_id):
    conn = get_db_connection()
    if not conn:
        return {"error": "Database connection failed"}, 500

    try:
        cur = conn.cursor()
        cur.execute("SELECT id FROM product WHERE id=%s;", (product_id,))
        if not cur.fetchone():
            return {"error": "Product not found"}, 404

        cur.execute("DELETE FROM product WHERE id=%s;", (product_id,))
        conn.commit()

        return {"message": f"Product {product_id} deleted"}
    except Exception as e:
        return {"error": str(e)}, 500
    finally:
        cur.close()
        conn.close()


# -------------------------------------------------------------------
# ✅ Start Server
# -------------------------------------------------------------------

if __name__ == "__main__":
    logger.info("server_starting", extra={"event": "starting_server"})

    conn = get_db_connection()
    if conn:
        conn.close()
        logger.info("db_verified", extra={"event": "db_verified"})

    create_table_if_not_exists()

    port = int(os.getenv("PORT", 8080))
    app.run(host="0.0.0.0", port=port, debug=False)
