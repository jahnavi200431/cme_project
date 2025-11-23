# Use Python 3.11
FROM python:3.11

# Set working directory
WORKDIR /app

# Install netcat for wait-for-proxy
RUN apt-get update && apt-get install -y netcat-openbsd && rm -rf /var/lib/apt/lists/*

# Copy requirements
COPY app/requirements.txt .

# Install Python dependencies
RUN pip install --no-cache-dir -r requirements.txt

# Copy application code
COPY app/ .

# Copy start.sh
COPY app/start.sh .

# Make start.sh executable
RUN chmod +x start.sh

# Expose port
EXPOSE 8080

# Start Flask app via start.sh
CMD ["/bin/bash", "/app/start.sh"]
