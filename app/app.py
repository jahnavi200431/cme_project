from flask import Flask, jsonify, request
import psycopg2
import os
import logging
import sys
import json
import io

app = Flask(__name__)

# -------------------------------------------------------
# JSON LOGGING (CLOUD LOGGING FRIENDLY)
# -------------------------------------------------------
class JsonFormatter(logging.Formatter):
    def format(self, record):
        log = {
            "severity": record.levelname,
            "app": "gke-rest-api",
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

logger = logging.getLogger("gke-rest-api")
logger.setLevel(logging.INFO)
logger.handlers = [json_handler]

werk = logging.getLogger("werkzeug")
werk.setLevel(logging.INFO)
werk.handlers = []
werk.addHandler(json_handler)

# ---------------------------------------------------------
# WSGI MIDDLEWARE — FULL REQUEST + FULL RESPONSE LOGGING
# ---------------------------------------------------------
class RequestResponseLoggerMiddleware:
    def __init__(self, app):
        self.app = app

    def __call__(self, environ, start_response):
        try:
            raw_body = environ["wsgi.input"].read()
            body_text = raw_body.decode("utf-8")
            environ["wsgi.input"] = io.BytesIO(raw_body)
        except:
            body_text = "<unable to read>"

        logger.info({
            "event": "request",
            "method": environ.get("REQUEST_METHOD"),
            "path": environ.get("PATH_INFO"),
            "query": environ.get("QUERY_STRING"),
            "remote_ip": environ.get("REMOTE_ADDR"),
            "body": body_text[:5000]
        })

        response_body_chunks = []

        def custom_start_response(status, headers, exc_info=None):
            nonlocal response_body_chunks
            def write(body):
                response_body_chunks.append(body)
                return start_response(status, headers, exc_info)
            start_response(status, headers, exc_info)
            return write

        result = self.app(environ, custom_start_response)

        for chunk in result:
            response_body_chunks.append(chunk)

        full_response_body = b"".join(response_body_chunks)
        try:
            response_text = full_response_body.decode("utf-8")
        except:
            response_text = "<binary response>"

        logger.info({
            "event": "response",
            "status": "200",
            "path": environ.get("PATH_INFO"),
            "response_body": response_text[:5000]
        })

        return response_body_chunks

app.wsgi_app = RequestResponseLoggerMiddleware(app.wsgi_app)

# ---------------------------------------------------------
# API KEY CHECK
# ---------------------------------------------------------
API_KEY = os.getenv("API_KEY")

def require_api_key():
    provided_key = (
        request.headers.get("X-API-KEY")
        or request.headers.get("x-api-key")
        or request.headers.get("Authorization")
    )
    if API_KEY is None:
        logger.error({"event": "api_key_env_missing"})
        return False
    if provided_key != API_KEY:
        logger.warning({"event": "auth_failed", "provided_key": provided_key})
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
DB_PORT = os.getenv("DB_PORT")

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
        logger.error({"event": "db_connection_failed", "error": str(e)})
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
                name VARCHAR(255) NOT NULL,
                description TEXT,
                price NUMERIC(10,2) NOT NULL,
                quantity INT DEFAULT 0,
                created_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP,
                updated_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP
            );
        """)
        # Trigger for automatic updated_at
        cur.execute("""
            CREATE OR REPLACE FUNCTION update_updated_at_column()
            RETURNS TRIGGER AS $$
            BEGIN
                NEW.updated_at = NOW();
                RETURN NEW;
            END;
            $$ LANGUAGE 'plpgsql';
        """)
        cur.execute("DROP TRIGGER IF EXISTS set_updated_at ON product;")
        cur.execute("""
            CREATE TRIGGER set_updated_at
            BEFORE UPDATE ON product
            FOR EACH ROW
            EXECUTE FUNCTION update_updated_at_column();
        """)
        conn.commit()
        logger.info({"event": "table_created"})
    except Exception as e:
        logger.error({"event": "table_creation_error", "error": str(e)})
    finally:
        cur.close()
        conn.close()

# ---------------------------------------------------------
# ROUTES
# ---------------------------------------------------------
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
    if not data.get("name") or data.get("price") is None:
        return {"error": "name and price are required"}, 400

    conn = get_db_connection()
    if not conn:
        return {"error": "DB connection failed"}, 500

    try:
        cur = conn.cursor()
        # check if product exists
        cur.execute("SELECT quantity FROM product WHERE id=%s;", (product_id,))
        row = cur.fetchone()
        if not row:
            return {"error": "Product not found"}, 404

        current_quantity = row[0]

        cur.execute("""
            UPDATE product
            SET name=%s,
                description=%s,
                price=%s,
                quantity=%s
            WHERE id=%s;
        """, (
            data.get("name"),
            data.get("description"),
            data.get("price"),
            data.get("quantity", current_quantity),  # use existing if missing
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
