from flask import Flask, jsonify, request
import logging
import sys
import json
import io
import os
from google.cloud import secretmanager
import psycopg2
from google.auth import default as google_auth_default

app = Flask(__name__)

# ------------------------------------------------------
# JSON LOGGING (CLOUD LOGGING FRIENDLY)
# -------------------------------------------------------
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
root.handlers = [json_handler]

logger = logging.getLogger("my-project-app-477009")
logger.setLevel(logging.INFO)
logger.handlers = [json_handler]


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
# SECRET MANAGER HELPERS (SAFE)
# ---------------------------------------------------------
client = secretmanager.SecretManagerServiceClient()

def detect_project_id():
    """Detect project ID using GKE metadata or ADC."""
    try:
        _, project_id = google_auth_default()
        return project_id
    except:
        return os.getenv("GCP_PROJECT_ID")  # fallback

def get_secret(secret_name):
    project_id = detect_project_id()
    secret_path = f"projects/{project_id}/secrets/{secret_name}/versions/latest"
    response = client.access_secret_version(name=secret_path)
    return response.payload.data.decode("UTF-8")


# These will be initialized at runtime (not during build)
DB_PASS = None
API_KEY = None

def init_runtime_secrets():
    """Load secrets ONLY when running inside GKE, not during image build."""
    global DB_PASS, API_KEY
    logger.info({"event": "loading_secrets"})

    DB_PASS = get_secret("db-password")
    API_KEY = get_secret("api-key")

    logger.info({"event": "secrets_loaded"})


# ---------------------------------------------------------
# API KEY CHECK
# ---------------------------------------------------------
def require_api_key():
    provided_key = (
        request.headers.get("X-API-KEY")
        or request.headers.get("x-api-key")
        or request.headers.get("Authorization")
    )
    if not provided_key or provided_key != API_KEY:
        logger.warning({
            "event": "auth_failed",
            "provided_key": provided_key
        })
        return False
    return True

# ---------------------------------------------------------
# HEALTH CHECKS
# ---------------------------------------------------------
@app.route('/health')
def health():
    return {"status": "healthy"}, 200

@app.route('/ready')
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
                name VARCHAR(100) NOT NULL,
                description TEXT,
                price NUMERIC(10,2) NOT NULL,
                quantity INT DEFAULT 0,
                created_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP,
                updated_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP
            );
        """)
        conn.commit()
        logger.info({"event": "table_ready"})
    except Exception as e:
        logger.error({"event": "table_creation_error", "error": str(e)})
    finally:
        cur.close()
        conn.close()


# ---------------------------------------------------------
# ROUTES (UNCHANGED)
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


# ---------------------------------------------------------
# START SERVER
# ---------------------------------------------------------
if __name__ == "__main__":
    logger.info({"event": "starting_server"})

    # ⭐ load secrets safely at runtime
    init_runtime_secrets()

    create_table_if_not_exists()

    port = int(os.getenv("PORT", 8080))
    app.run(host="0.0.0.0", port=port, debug=False)
