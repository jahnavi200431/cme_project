#!/bin/bash
echo " Waiting for Cloud SQL Proxy..."
while ! nc -z 127.0.0.1 5432; do
  sleep 1
done

echo " Cloud SQL Proxy is ready. Starting Flask app..."
exec gunicorn -w 2 -b 0.0.0.0:8080 app:app

