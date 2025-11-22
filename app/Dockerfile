# Use Python 3.11 slim for smaller image
FROM python:3.11-slim

# Set working directory inside container
WORKDIR /app

# Copy requirements from app folder
COPY app/requirements.txt .

# Install dependencies, including psycopg2 build dependencies
RUN apt-get update && apt-get install -y \
    gcc \
    libpq-dev \
    && pip install --no-cache-dir -r requirements.txt \
    && apt-get remove -y gcc \
    && apt-get autoremove -y \
    && rm -rf /var/lib/apt/lists/*

# Copy the rest of the application code
COPY app/ .

# Expose port for GKE
EXPOSE 8080

# Run the Flask app using Gunicorn
CMD ["gunicorn", "--bind", "0.0.0.0:8080", "--workers", "4", "--access-logfile", "-", "--error-logfile", "-", "app:app"]
