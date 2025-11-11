from flask import Flask, jsonify, request
import psycopg2
import os
import logging
import sys

app = Flask(__name__)

# --------------------------------------------------------
# ✅ Structured Logging Configuration
# --------------------------------------------------------

# Base logger to stdout
logging.basicConfig(stream=sys.stdout, level=logging.INFO)

# Create application logger with metadata
logger = logging.getLogger("gke-rest-api")
logger = logging.LoggerAdapter(logger, {
    "app": "gke-rest-api",
    "version": "1.0.0",
})

# Disable werkzeug default access logs (optional but recommended)
logging.getLogger("werkzeug").disabled = True


# --------------------------------------------------------
# ✅ Request/Response Structured Logging
# --------------------------------------------------------

@app.before_request
def log_request():
    logger.info({
        "event": "request",
        "method": request.method,
        "path": request.path,
        "remote_ip": request.remote_addr,
        "app": "gke-rest-api"
    })


@app.after_request
def log_response(response):
    logger.info({
        "event": "response",
        "method": request.method,
        "path": request.path,
        "status": response.status_code,
        "app": "gke-rest-api"
    })
    return response


# --------------------------------------------------------
# ✅ Health Check
# --------------------------------------------------------
@app.route('/health', methods=['GET'])
def health():
    logger.info({"event": "health_check", "status": "ok"})
    return {'status': 'healthy'}, 200


# --------------------------------------------------------
# ✅ Database Config
# --------------------------------------------------------
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
        logger.info({"event": "db_connection", "status": "success"})
        return conn
    except Exception as e:
        logger.error({"event": "db_connection_failed", "error": str(e)})
        return None


# --------------------------------------------------------
# ✅ Ensure table exists
# --------------------------------------------------------
def create_table_if_not_exists():
    conn = get_db_connection()
    if not conn:
        logger.error({"event": "table_create_failed", "reason": "db_connection_failed"})
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
        logger.error({"event": "table_create_error", "error": str(e)})
    finally:
        cur.close()
        conn.close()


# --------------------------------------------------------
# ✅ API Endpoints
# --------------------------------------------------------

@app.route("/")
def home():
    return jsonify({"message": "Welcome to the Product API (Cloud SQL connected)"})


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
        return jsonify({"message": "Product added!", "id": product_id}), 201
    except Exception as e:
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
            return jsonify({"error": "Product not found"}), 404

        cur.execute("""
            UPDATE product
            SET name=%s, description=%s, price=%s, quantity=%s
            WHERE id=%s;
        """, (data.get("name"), data.get("description"),
              data.get("price"), data.get("quantity"), product_id))
        conn.commit()
        return jsonify({"message": f"Product {product_id} updated!"})
    except Exception as e:
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
        return jsonify({"message": f"Product {product_id} deleted!"})
    except Exception as e:
        return jsonify({"error": str(e)}), 500
    finally:
        cur.close()
        conn.close()


# --------------------------------------------------------
# ✅ Start App
# --------------------------------------------------------
if __name__ == "__main__":
    logger.info({"event": "starting_server"})

    # Verify DB connection
    conn = get_db_connection()
    if conn:
        conn.close()
        logger.info({"event": "db_verified"})

    create_table_if_not_exists()

    port = int(os.getenv("PORT", 8080))
    app.run(host="0.0.0.0", port=port, debug=False)
