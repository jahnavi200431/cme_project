from flask import Flask, jsonify, request
import psycopg2
import os
import logging
import sys
import json

app = Flask(__name__)

# -------------------------------------------------------
# ✅ Structured JSON Logging Configuration
# ------------------------------------------------------

class JsonFormatter(logging.Formatter):
    def format(self, record):
        log = {
            "severity": record.levelname,
            "message": record.getMessage(),
            "app": "gke-rest-api",
            "version": "1.0.0",
        }
        return json.dumps(log)

json_handler = logging.StreamHandler(sys.stdout)
json_handler.setFormatter(JsonFormatter())

logger = logging.getLogger("gke-rest-api")
logger.setLevel(logging.INFO)
logger.handlers = [json_handler]

# Disable noisy werkzeug logs
logging.getLogger("werkzeug").disabled = True


# --------------------------------------------------------
# ✅ Log Request/Response Events
# --------------------------------------------------------

@app.before_request
def log_request():
    logger.info(json.dumps({
        "event": "request",
        "method": request.method,
        "path": request.path,
        "remote_ip": request.remote_addr
    }))


@app.after_request
def log_response(response):
    logger.info(json.dumps({
        "event": "response",
        "method": request.method,
        "path": request.path,
        "status": response.status_code
    }))
    return response


# --------------------------------------------------------
# ✅ Health Check Endpoints
# --------------------------------------------------------

@app.route('/health', methods=['GET'])
def health():
    logger.info(json.dumps({"event": "health_check", "status": "ok"}))
    return {"status": "healthy"}, 200


@app.route('/ready', methods=['GET'])
def readiness():
    # Check database readiness
    conn = get_db_connection(check_only=True)
    status = "ready" if conn else "not ready"

    logger.info(json.dumps({"event": "readiness_check", "status": status}))
    if conn:
        conn.close()
        return {"status": "ready"}, 200
    return {"status": "not ready"}, 500


# --------------------------------------------------------
# ✅ Database Configuration
# --------------------------------------------------------


DB_HOST = os.getenv("DB_HOST", "35.194.2.254")
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
            logger.info(json.dumps({"event": "db_connection", "status": "success"}))
        return conn
    except Exception as e:
        logger.error(json.dumps({"event": "db_connection_failed", "error": str(e)}))
        return None


# --------------------------------------------------------
# ✅ Create Table If Not Exists
# --------------------------------------------------------

def create_table_if_not_exists():
    conn = get_db_connection()
    if not conn:
        logger.error(json.dumps({
            "event": "table_create_failed",
            "reason": "db_connection_failed"
        }))
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
        logger.info(json.dumps({"event": "table_created"}))
    except Exception as e:
        logger.error(json.dumps({"event": "table_creation_error", "error": str(e)}))
    finally:
        cur.close()
        conn.close()


# --------------------------------------------------------
# ✅ REST API Routes
# --------------------------------------------------------

@app.route("/")
def home():
    return jsonify({
        "message": "Welcome to the Product API (Cloud SQL connected)"
    })


@app.route("/products", methods=["GET"])
def get_products():
    conn = get_db_connection()
    if not conn:
        return {"error": "Database connection failed"}, 500

    try:
        cur = conn.cursor()
        cur.execute("SELECT * FROM product;")
        rows = cur.fetchall()
        col_names = [desc[0] for desc in cur.description]
        products = [dict(zip(col_names, row)) for row in rows]
        return jsonify(products)
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
        return jsonify(dict(zip(col_names, row)))
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
        return jsonify({"message": "Product added!", "id": new_id}), 201
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

        return {"message": f"Product {product_id} updated!"}
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

        return {"message": f"Product {product_id} deleted!"}
    except Exception as e:
        return {"error": str(e)}, 500
    finally:
        cur.close()
        conn.close()


# --------------------------------------------------------
# ✅ Start Server
# --------------------------------------------------------

if __name__ == "__main__":
    logger.info(json.dumps({"event": "starting_server"}))

    # Verify DB connectivity at startup
    conn = get_db_connection()
    if conn:
        conn.close()
        logger.info(json.dumps({"event": "db_verified"}))

    create_table_if_not_exists()

    port = int(os.getenv("PORT", 8080))
    app.run(host="0.0.0.0", port=port, debug=False)
