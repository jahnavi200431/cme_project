# Use Python 3.11 slim
FROM python:3.11-slim

WORKDIR /app

# Copy requirements
COPY app/requirements.txt .

# Upgrade pip first
RUN python -m pip install --upgrade pip setuptools wheel

# Install system dependencies for psycopg2
RUN apt-get update && apt-get install -y \
    gcc \
    libpq-dev \
    && pip install --no-cache-dir -r requirements.txt \
    && apt-get remove -y gcc \
    && apt-get autoremove -y \
    && rm -rf /var/lib/apt/lists/*

# Copy application code
COPY app/ .

EXPOSE 8080

CMD ["gunicorn", "--bind", "0.0.0.0:8080", "--workers", "4", "--access-logfile", "-", "--error-logfile", "-", "app:app"]
