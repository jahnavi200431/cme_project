from flask import Flask, jsonify, request, g
import logging
import sys
import json
import psycopg2
from psycopg2 import pool
import os
from contextlib import contextmanager
from time import time

app = Flask(__name__)



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



DB_HOST = os.getenv("DB_HOST")
DB_PORT = int(os.getenv("DB_PORT"))
DB_NAME = os.getenv("DB_NAME")
DB_USER = os.getenv("DB_USER")
DB_PASS = os.getenv("DB_PASS")
API_KEY = os.getenv("API_KEY")



try:
    db_pool = psycopg2.pool.SimpleConnectionPool(
        minconn=2,
        maxconn=20,
        host=DB_HOST,
        database=DB_NAME,
        user=DB_USER,
        password=DB_PASS,
        port=DB_PORT,
        connect_timeout=5,
        keepalives=1,
        keepalives_idle=30,
        keepalives_interval=10,
        keepalives_count=5
    )
    logger.info({"event": "db_pool_created"})
except Exception as e:
    logger.error({"event": "db_pool_error", "error": str(e)}, exc_info=True)
    db_pool = None


@contextmanager
def get_conn():
    if not db_pool:
        yield None
        return
    conn = None
    try:
        conn = db_pool.getconn()
        yield conn
    except Exception as e:
        logger.error({"event": "db_connection_failed", "error": str(e)}, exc_info=True)
        yield None
    finally:
        if conn:
            db_pool.putconn(conn)


@app.before_request
def log_request():
    g.start_time = time()

    try:
        body = request.get_data(as_text=True)
    except Exception:
        body = None

    
    headers = {
        k: ("***" if k.lower() in ["authorization", "x-api-key"] else v)
        for k, v in request.headers.items()
    }

    logger.info({
        "event": "http_request",
        "method": request.method,
        "path": request.path,
        "headers": headers,
        "body": body,
    })


@app.after_request
def log_response(response):
    duration = round((time() - g.start_time) * 1000, 2)

    try:
        response_body = response.get_data(as_text=True)
    except Exception:
        response_body = None

    logger.info({
        "event": "http_response",
        "method": request.method,
        "path": request.path,
        "status": response.status_code,
        "duration_ms": duration,
        "response_body": response_body,
    })

    return response



def create_table_if_not_exists():
    with get_conn() as conn:
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


create_table_if_not_exists()



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



@app.route('/health')
def health():
    return {"status": "healthy"}, 200


@app.route('/ready')
def readiness():
    with get_conn() as conn:
        if conn:
            return {"status": "ready"}, 200
        return {"status": "not ready"}, 500


@app.route("/")
def home():
    return {"message": "Welcome to Product API (GKE + Cloud SQL)"}, 200


@app.route("/products", methods=["GET"])
def get_products():
    with get_conn() as conn:
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


@app.route("/products/<int:product_id>", methods=["GET"])
def get_product(product_id):
    with get_conn() as conn:
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


@app.route("/products", methods=["POST"])
def add_product():
    if not require_api_key():
        return {"error": "Unauthorized"}, 401
    data = request.get_json()
    with get_conn() as conn:
        if not conn:
            return {"error": "DB connection failed"}, 500
        try:
            cur = conn.cursor()
            cur.execute("""
                INSERT INTO product (name, description, price, quantity)
                VALUES (%s, %s, %s, %s) RETURNING id;
            """, (
                data.get("name"),
                data.get("description"),
                float(data.get("price")),
                int(data.get("quantity", 0))
            ))
            conn.commit()
            new_id = cur.fetchone()[0]
            return {"message": "Product added!", "id": new_id}, 201
        finally:
            cur.close()


@app.route("/products/<int:product_id>", methods=["PUT"])
def update_product(product_id):
    if not require_api_key():
        return {"error": "Unauthorized"}, 401
    data = request.get_json()
    with get_conn() as conn:
        if not conn:
            return {"error": "DB connection failed"}, 500
        try:
            cur = conn.cursor()
            cur.execute("""
                UPDATE product
                SET name = %s,
                    description = %s,
                    price = %s,
                    quantity = %s,
                    updated_at = CURRENT_TIMESTAMP
                WHERE id = %s
                RETURNING id;
            """, (
                data.get("name"),
                data.get("description"),
                float(data.get("price")),
                int(data.get("quantity", 0)),
                product_id
            ))
            updated = cur.fetchone()
            conn.commit()
            if not updated:
                return {"error": "Product not found"}, 404
            return {"message": "Product updated!", "id": updated[0]}, 200
        finally:
            cur.close()


@app.route("/products/<int:product_id>", methods=["DELETE"])
def delete_product(product_id):
    if not require_api_key():
        return {"error": "Unauthorized"}, 401
    with get_conn() as conn:
        if not conn:
            return {"error": "DB connection failed"}, 500
        try:
            cur = conn.cursor()
            cur.execute("DELETE FROM product WHERE id = %s RETURNING id;", (product_id,))
            deleted = cur.fetchone()
            conn.commit()
            if not deleted:
                return {"error": "Product not found"}, 404
            return {"message": "Product deleted!", "id": deleted[0]}, 200
        finally:
            cur.close()



if __name__ == "__main__":
    logger.info({"event": "starting_server"})
    port = int(os.getenv("PORT", 8080))
    app.run(host="0.0.0.0", port=port, debug=False)
