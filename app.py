from flask import Flask, jsonify, request
import psycopg2
import os

app = Flask(__name__)

@app.route('/health', methods=['GET'])
def health():
    return {'status': 'healthy'}, 200

DB_HOST = os.getenv("DB_HOST", "127.0.0.1")
DB_NAME = os.getenv("DB_NAME", "productdb")
DB_USER = os.getenv("DB_USER", "postgres")
DB_PASS = os.getenv("DB_PASS", "postgres")
DB_PORT = os.getenv("DB_PORT", "5433")

def get_db_connection():
    try:
        conn = psycopg2.connect(
            host=DB_HOST,
            database=DB_NAME,
            user=DB_USER,
            password=DB_PASS,
            port=DB_PORT
        )
        print(" Database connection successful!")
        return conn
    except Exception as e:
        print(" Database connection failed!")
        print(e)
        return None

@app.route("/")
def home():
    return jsonify({"message": "Welcome to the Product API (connected via Cloud SQL)"})



@app.route("/products", methods=["GET"])
def get_products():
    conn = get_db_connection()
    if conn is None:
        return jsonify({"error": "Database connection failed"}), 500

    cur = conn.cursor()
    cur.execute("SELECT * FROM product;")
    rows = cur.fetchall()
    columns = [desc[0] for desc in cur.description]
    products = [dict(zip(columns, row)) for row in rows]

    cur.close()
    conn.close()
    return jsonify(products)



@app.route("/products/<int:product_id>", methods=["GET"])
def get_product(product_id):
    conn = get_db_connection()
    if conn is None:
        return jsonify({"error": "Database connection failed"}), 500

    cur = conn.cursor()
    cur.execute("SELECT * FROM product WHERE id = %s;", (product_id,))
    row = cur.fetchone()

    if row is None:
        cur.close()
        conn.close()
        return jsonify({"error": "Product not found"}), 404

    columns = [desc[0] for desc in cur.description]
    product = dict(zip(columns, row))

    cur.close()
    conn.close()
    return jsonify(product)



@app.route("/products", methods=["POST"])
def add_product():
    data = request.get_json()
    name = data.get("name")
    description = data.get("description")
    price = data.get("price")
    quantity = data.get("quantity", 0)

    if not name or not price:
        return jsonify({"error": "Name and price are required"}), 400

    conn = get_db_connection()
    cur = conn.cursor()
    cur.execute("""
        INSERT INTO product (name, description, price, quantity)
        VALUES (%s, %s, %s, %s)
        RETURNING id;
    """, (name, description, price, quantity))
    conn.commit()
    product_id = cur.fetchone()[0]
    cur.close()
    conn.close()

    return jsonify({"message": "Product added successfully!", "id": product_id}), 201


@app.route("/products/<int:product_id>", methods=["PUT"])
def update_product(product_id):
    data = request.get_json()
    name = data.get("name")
    description = data.get("description")
    price = data.get("price")
    quantity = data.get("quantity")

    conn = get_db_connection()
    cur = conn.cursor()

    cur.execute("SELECT * FROM product WHERE id = %s;", (product_id,))
    if cur.fetchone() is None:
        cur.close()
        conn.close()
        return jsonify({"error": "Product not found"}), 404

    cur.execute("""
        UPDATE product
        SET name = %s, description = %s, price = %s, quantity = %s
        WHERE id = %s;
    """, (name, description, price, quantity, product_id))
    conn.commit()

    cur.close()
    conn.close()

    return jsonify({"message": f"Product {product_id} updated successfully!"})



@app.route("/products/<int:product_id>", methods=["DELETE"])
def delete_product(product_id):
    conn = get_db_connection()
    cur = conn.cursor()

    cur.execute("SELECT * FROM product WHERE id = %s;", (product_id,))
    if cur.fetchone() is None:
        cur.close()
        conn.close()
        return jsonify({"error": "Product not found"}), 404

    cur.execute("DELETE FROM product WHERE id = %s;", (product_id,))
    conn.commit()

    cur.close()
    conn.close()

    return jsonify({"message": f"Product {product_id} deleted successfully!"})


# -----------------------------------------
# Start the Application
# -----------------------------------------
if __name__ == "__main__":
    print(" Starting Flask API and testing Cloud SQL connection...")
    conn = get_db_connection()
    if conn:
        conn.close()
        print(" Cloud SQL connection verified successfully!")

    port = int(os.getenv("PORT", 8080))
    app.run(host="0.0.0.0", port=port, debug=True)
