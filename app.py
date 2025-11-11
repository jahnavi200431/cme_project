from flask import Flask, jsonify, request
import psycopg2
import os
import logging
import sys
from time import time

app = Flask(__name__)

# -----------------------
# ✅ Structured Logging Configuration
# -----------------------
logger = logging.getLogger("gke-rest-api")
logger.setLevel(logging.INFO)

# Send logs to STDOUT (so Cloud Logging treats them as INFO, not ERROR)
handler = logging.StreamHandler(sys.stdout)
formatter = logging.Formatter(
    '{"level":"%(levelname)s","message":"%(message)s","app":"gke-rest-api","version":"1.0.0"}'
)
handler.setFormatter(formatter)

# Avoid duplicate handlers
if not logger.handlers:
    logger.addHandler(handler)

# Wrap logger with metadata
logger = logging.LoggerAdapter(logger, {
    "app": "gke-rest-api",
    "version": "1.0.0"
})

app.logger = logger


# -----------------------
# ✅ Request Logging Middleware
# -----------------------

@app.before_request
def start_timer():
    request.start_time = time()


@app.after_request
def log_request(response):
    try:
        latency = round((time() - request.start_time) * 1000, 2)
    except Exception:
        latency = None

    log_data = {
        "method": request.method,
        "path": request.path,
        "status": response.status_code,
        "remote_ip": request.headers.get("X-Forwarded-For", request.remote_addr),
        "latency_ms": latency,
        "user_agent": request.headers.get("User-Agent"),
    }

    # avoid logging probe spam
    if request.path not in ("/health", "/liveness", "/readiness"):
        app.logger.info(f"Request processed {log_data}")

    return response


# -----------------------
# ✅ Health, Readiness, Liveness Endpoints
# -----------------------
@app.route('/health', methods=['GET'])
def health():
    return {'status': 'healthy'}, 200


@app.route("/liveness", methods=["GET"])
def liveness():
    # app is running
    return {"status": "alive"}, 200


@app.route("/readiness", methods=["GET"])
def readiness():
    conn = get_db_connection()
    if conn:
        conn.close()
        return {"status": "ready"}, 200
    return {"status": "not ready"}, 500


# -----------------------
# ✅ DB Configuration
# -----------------------
DB_HOST = os.getenv("DB_HOST", "136.115.254.71")
DB_NAME = os.getenv("DB_NAME", "productdb")
DB_USER = os.getenv("DB_USER", "postgres")
DB_PASS = os.getenv("DB_PASS", "postgres")
DB_PORT = os.getenv("DB_PORT", "5432")


def get_db_connection():
    try:
        conn = psycopg2.connect(
            host=DB_HOST,
            database=DB_NAME,
            user=DB_USER,
            password=DB_PASS,
            port=DB_PORT
        )
        return conn
    except Exception as e:
        app.logger.error(f"Database connection failed: {str(e)}")
        return None


# -----------------------
# ✅ Ensure Table Exists
# -----------------------
def create_table_if_not_exists():
    conn = get_db_connection()
    if not conn:
        app.logger.error("Cannot create table because DB connection failed")
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
        app.logger.info("✅ Product table ensured in database.")
    except Exception as e:
        app.logger.error(f"❌ Failed to create table: {str(e)}")
    finally:
        cur.close()
        conn.close()


# -----------------------
# ✅ API Endpoints
# -----------------------

@app.route("/")
def home():
    return jsonify({"message": "Welcome to the Product API (connected via Cloud SQL)"})


@app.route("/products", methods=["GET"])
def get_products():
    conn = get_db_connection()
    if not conn:
        return jsonify({"error": "Database connection failed"}), 500

    try:
        cur = conn.cursor()
        cur.execute("SELECT * FROM product;")
        rows = cur.fetchall()
        columns = [desc[0] for desc in cur.description]
        products = [dict(zip(columns, row)) for row in rows]
        return jsonify(products)
    except Exception as e:
        app.logger.error(f"Error fetching products: {str(e)}")
        return jsonify({"error": str(e)}), 500
    finally:
        cur.close()
        conn.close()


@app.route("/products/<int:product_id>", methods=["GET"])
def get_product(product_id):
    conn = get_db_connection()
    if not conn:
        return jsonify({"error": "Database connection failed"}), 500

    try:
        cur = conn.cursor()
        cur.execute("SELECT * FROM product WHERE id = %s;", (product_id,))
        row = cur.fetchone()
        if not row:
            return jsonify({"error": "Product not found"}), 404
        columns = [desc[0] for desc in cur.description]
        return jsonify(dict(zip(columns, row)))
    except Exception as e:
        app.logger.error(f"Error fetching product: {str(e)}")
        return jsonify({"error": str(e)}), 500
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
        return jsonify({"error": "Name and price are required"}), 400

    conn = get_db_connection()
    if not conn:
        return jsonify({"error": "Database connection failed"}), 500

    try:
        cur = conn.cursor()
        cur.execute("""
            INSERT INTO product (name, description, price, quantity)
            VALUES (%s, %s, %s, %s)
            RETURNING id;
        """, (name, description, price, quantity))
        conn.commit()
        product_id = cur.fetchone()[0]
        return jsonify({"message": "Product added successfully!", "id": product_id}), 201
    except Exception as e:
        app.logger.error(f"Error adding product: {str(e)}")
        return jsonify({"error": str(e)}), 500
    finally:
        cur.close()
        conn.close()


@app.route("/products/<int:product_id>", methods=["PUT"])
def update_product(product_id):
    data = request.get_json()
    name = data.get("name")
    description = data.get("description")
    price = data.get("price")
    quantity = data.get("quantity")

    conn = get_db_connection()
    if not conn:
        return jsonify({"error": "Database connection failed"}), 500

    try:
        cur = conn.cursor()
        cur.execute("SELECT * FROM product WHERE id = %s;", (product_id,))
        if not cur.fetchone():
            return jsonify({"error": "Product not found"}), 404

        cur.execute("""
            UPDATE product
            SET name=%s, description=%s, price=%s, quantity=%s
            WHERE id=%s;
        """, (name, description, price, quantity, product_id))
        conn.commit()
        return jsonify({"message": f"Product {product_id} updated successfully!"})
    except Exception as e:
        app.logger.error(f"Error updating product: {str(e)}")
        return jsonify({"error": str(e)}), 500
    finally:
        cur.close()
        conn.close()


@app.route("/products/<int:product_id>", methods=["DELETE"])
def delete_product(product_id):
    conn = get_db_connection()
    if not conn:
        return jsonify({"error": "Database connection failed"}), 500

    try:
        cur = conn.cursor()
        cur.execute("SELECT * FROM product WHERE id = %s;", (product_id,))
        if not cur.fetchone():
            return jsonify({"error": "Product not found"}), 404

        cur.execute("DELETE FROM product WHERE id = %s;", (product_id,))
        conn.commit()
        return jsonify({"message": f"Product {product_id} deleted successfully!"})
    except Exception as e:
        app.logger.error(f"Error deleting product: {str(e)}")
        return jsonify({"error": str(e)}), 500
    finally:
        cur.close()
        conn.close()


# -----------------------
# ✅ Start Application
# -----------------------
if __name__ == "__main__":
    app.logger.info("Starting Flask API and verifying DB connection...")
    
    conn = get_db_connection()
    if conn:
        conn.close()
        app.logger.info("✅ DB connection OK!")

    create_table_if_not_exists()

    port = int(os.getenv("PORT", 8080))
    app.run(host="0.0.0.0", port=port, debug=True)
