FROM python:3.11-slim

WORKDIR /app

# Copy requirements
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Copy app code
COPY app.py .
COPY start.sh .

# Make start.sh executable
RUN chmod +x start.sh

# Expose port
EXPOSE 8080

# Set default command to start.sh
CMD ["/bin/bash", "/app/start.sh"]
