from flask import Flask, jsonify, request
import psycopg2
import os
import logging
import sys
from pythonjsonlogger import jsonlogger

app = Flask(__name__)

# -----------------------
# 🔧 Structured JSON Logging Configuration
# -----------------------
logHandler = logging.StreamHandler(sys.stdout)
formatter = jsonlogger.JsonFormatter(
    '%(asctime)s %(name)s %(levelname)s %(message)s %(extra)s'
)
logHandler.setFormatter(formatter)

logger = logging.getLogger()
logger.addHandler(logHandler)
logger.setLevel(logging.INFO)

# Use Flask's logger
app.logger.handlers = logger.handlers
app.logger.setLevel(logging.INFO)

# Helper function to log structured events
def log_event(level, message, **kwargs):
    extra = {"extra": kwargs} if kwargs else {}
    if level.lower() == "info":
        app.logger.info(message, extra=extra)
    elif level.lower() == "warning":
        app.logger.warning(message, extra=extra)
    elif level.lower() == "error":
        app.logger.error(message, extra=extra)
    elif level.lower() == "exception":
        app.logger.exception(message, extra=extra)

# -----------------------
# Health Check Endpoint
# -----------------------
@app.route('/health', methods=['GET'])
def health():
    log_event("info", "Health check requested")
    return {'status': 'healthy'}, 200

# -----------------------
# Database Configuration
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
        log_event("info", "Database connection established")
        return conn
    except Exception as e:
        log_event("exception", "Database connection failed", error=str(e))
        return None

# -----------------------
# Ensure Table Exists
# -----------------------
def create_table_if_not_exists():
    conn = get_db_connection()
    if not conn:
        log_event("error", "Cannot create table, DB connection failed")
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
        log_event("info", "✅ Product table ensured in database")
    except Exception as e:
        log_event("exception", "Failed to create table", error=str(e))
    finally:
        cur.close()
        conn.close()

# -----------------------
# API Endpoints
# -----------------------
@app.route("/")
def home():
    log_event("info", "Home endpoint accessed")
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

        log_event("info", "Fetched all products", count=len(products))
        return jsonify(products)
    except Exception as e:
        log_event("exception", "Error fetching products", error=str(e))
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
            log_event("warning", "Product not found", product_id=product_id)
            return jsonify({"error": "Product not found"}), 404
        columns = [desc[0] for desc in cur.description]
        log_event("info", "Fetched single product", product_id=product_id)
        return jsonify(dict(zip(columns, row)))
    except Exception as e:
        log_event("exception", "Error fetching product", product_id=product_id, error=str(e))
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
        log_event("warning", "Missing name or price in POST /products", payload=data)
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
        log_event("info", "Product added", product_id=product_id, name=name)
        return jsonify({"message": "Product added successfully!", "id": product_id}), 201
    except Exception as e:
        log_event("exception", "Failed to add product", payload=data, error=str(e))
        return jsonify({"error": str(e)}), 500
    finally:
        cur.close()
        conn.close()

@app.route("/products/<int:product_id>", methods=["PUT"])
def update_product(product_id):
    data = request.get_json()
    conn = get_db_connection()
    if not conn:
        return jsonify({"error": "Database connection failed"}), 500

    try:
        cur = conn.cursor()
        cur.execute("SELECT * FROM product WHERE id = %s;", (product_id,))
        if not cur.fetchone():
            log_event("warning", "Product not found for update", product_id=product_id)
            return jsonify({"error": "Product not found"}), 404

        cur.execute("""
            UPDATE product
            SET name=%s, description=%s, price=%s, quantity=%s
            WHERE id=%s;
        """, (data.get("name"), data.get("description"), data.get("price"), data.get("quantity"), product_id))
        conn.commit()
        log_event("info", "Product updated", product_id=product_id)
        return jsonify({"message": f"Product {product_id} updated successfully!"})
    except Exception as e:
        log_event("exception", "Failed to update product", product_id=product_id, payload=data, error=str(e))
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
            log_event("warning", "Product not found for delete", product_id=product_id)
            return jsonify({"error": "Product not found"}), 404

        cur.execute("DELETE FROM product WHERE id = %s;", (product_id,))
        conn.commit()
        log_event("info", "Product deleted", product_id=product_id)
        return jsonify({"message": f"Product {product_id} deleted successfully!"})
    except Exception as e:
        log_event("exception", "Failed to delete product", product_id=product_id, error=str(e))
        return jsonify({"error": str(e)}), 500
    finally:
        cur.close()
        conn.close()

# -----------------------
# Start the App
# -----------------------
if __name__ == "__main__":
    log_event("info", "Starting Flask API and verifying DB connection")
    conn = get_db_connection()
    if conn:
        conn.close()
        log_event("info", "✅ Cloud SQL connection verified")

    create_table_if_not_exists()

    port = int(os.getenv("PORT", 8080))
    app.run(host="0.0.0.0", port=port, debug=True)
