from flask import Flask, jsonify, request
import psycopg2
import os
import logging
import sys

app = Flask(__name__)

# -----------------------
# 🔧 Logging Configuration (Fix for Cloud Logging "ERROR" severity issue)
# -----------------------
# Send normal logs (access/info) to stdout instead of stderr
logging.basicConfig(stream=sys.stdout, level=logging.INFO)
app.logger.handlers = logging.getLogger().handlers
app.logger.setLevel(logging.INFO)

# -----------------------
# Health Check Endpoint
# -----------------------
@app.route('/health', methods=['GET'])
def health():
    return {'status': 'healthy'}, 200

# -----------------------
# Database Configuration
# -----------------------
DB_HOST = os.getenv("DB_HOST", "136.115.254.71")  # Cloud SQL public IP
DB_NAME = os.getenv("DB_NAME", "productdb")
DB_USER = os.getenv("DB_USER", "postgres")
DB_PASS = os.getenv("DB_PASS", "postgres")
DB_PORT = os.getenv("DB_PORT", "5432")

def get_db_connection():
    """Return a psycopg2 connection or None if failed."""
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
        app.logger.error("Database connection failed!")
        app.logger.error(e)
        return None

# -----------------------
# Ensure Table Exists
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
        app.logger.error("❌ Failed to create table:")
        app.logger.error(e)
    finally:
        cur.close()
        conn.close()

# -----------------------
# API Endpoints
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
        return jsonify({"message": "Product added successfully!", "id": product_id}), 201
    except Exception as e:
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
        return jsonify({"error": str(e)}), 500
    finally:
        cur.close()
        conn.close()

# -----------------------
# Start the App
# -----------------------
if __name__ == "__main__":
    app.logger.info("Starting Flask API and testing Cloud SQL connection...")
    conn = get_db_connection()
    if conn:
        conn.close()
        app.logger.info("✅ Cloud SQL connection verified successfully!")

    # Auto-create table
    create_table_if_not_exists()

    port = int(os.getenv("PORT", 8080))
    app.run(host="0.0.0.0", port=port, debug=True)
