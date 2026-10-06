#!/bin/bash
#
# Bootstraps the web tier: installs Docker, writes the Flask app and runs it
# in a container on port 80.
#
# NOTE: this file is rendered by Terraform's templatefile(), so a dollar sign
# followed by a brace is a Terraform substitution, not a shell variable. To get
# a literal one through to the shell, double the dollar sign. Shell variables
# here are written without braces for that reason.

set -euo pipefail

# Mirror all output to a log so failures can be diagnosed after boot
exec > >(tee /var/log/user-data.log | logger -t user-data -s 2>/dev/console) 2>&1

export DEBIAN_FRONTEND=noninteractive

# apt can be locked by unattended-upgrades on a fresh boot, so retry
apt_install() {
  for attempt in 1 2 3 4 5; do
    if apt-get update && apt-get install -y "$@"; then
      return 0
    fi
    echo "apt attempt $attempt failed, retrying in 15s..."
    sleep 15
  done
  return 1
}

apt_install docker.io mysql-client

systemctl start docker
systemctl enable docker

mkdir -p /home/ubuntu/app
cd /home/ubuntu/app

cat > requirements.txt << 'REQEOF'
flask
mysql-connector-python
REQEOF

cat > app.py << 'APPEOF'
import html
import os
import time

import mysql.connector
from flask import Flask, redirect, request, url_for

app = Flask(__name__)

DB_CONFIG = {
    "host": "${db_host}",
    "user": "${db_username}",
    "password": "${db_password}",
    "database": "${db_name}",
}


def get_db_connection():
    """Open a database connection, retrying while RDS finishes starting up."""
    retries = 5
    while retries > 0:
        try:
            return mysql.connector.connect(**DB_CONFIG)
        except Exception as exc:
            retries -= 1
            if retries == 0:
                raise exc
            time.sleep(3)
    return None


def init_db():
    """Create the messages table if it does not already exist."""
    try:
        conn = get_db_connection()
        if conn:
            cursor = conn.cursor()
            cursor.execute(
                """
                CREATE TABLE IF NOT EXISTS messages (
                    id INT AUTO_INCREMENT PRIMARY KEY,
                    content VARCHAR(255) NOT NULL,
                    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
                )
                """
            )
            conn.commit()
            cursor.close()
            conn.close()
    except Exception as exc:
        print(f"DB init error: {exc}")


init_db()


@app.route("/", methods=["GET", "POST"])
def home():
    conn = get_db_connection()
    messages = []
    error = None

    if request.method == "POST":
        content = request.form.get("content")
        if content and conn:
            try:
                cursor = conn.cursor()
                cursor.execute("INSERT INTO messages (content) VALUES (%s)", (content,))
                conn.commit()
                cursor.close()
                conn.close()
                return redirect(url_for("home"))
            except Exception as exc:
                error = str(exc)

    if conn:
        try:
            cursor = conn.cursor()
            cursor.execute(
                "SELECT content, created_at FROM messages ORDER BY created_at DESC LIMIT 10"
            )
            messages = cursor.fetchall()
            cursor.close()
            conn.close()
        except Exception as exc:
            error = str(exc)
    else:
        error = "Could not connect to database"

    # Escape stored content before rendering - it came from user input
    messages_html = "".join(
        f"<div class='message'><p>{html.escape(str(m[0]))}</p>"
        f"<small>{html.escape(str(m[1]))}</small></div>"
        for m in messages
    )

    status_class = "disconnected" if error else "connected"
    status_text = "\u25cf Disconnected" if error else "\u25cf Connected to RDS"
    error_html = f'<div class="error">{html.escape(error)}</div>' if error else ""
    empty_html = "<p>No messages yet. Be the first to post!</p>"

    return f"""
    <html>
    <head>
        <title>Portfolio - RDS Web App</title>
        <style>
            body {{ font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif; margin: 0; background: #f0f2f5; color: #333; }}
            .container {{ max-width: 800px; margin: 40px auto; padding: 20px; }}
            .card {{ background: white; padding: 30px; border-radius: 8px; box-shadow: 0 2px 4px rgba(0,0,0,0.1); margin-bottom: 20px; }}
            h1 {{ color: #1a73e8; margin-top: 0; }}
            .form-group {{ margin-bottom: 15px; }}
            input[type="text"] {{ width: 100%; padding: 10px; border: 1px solid #ddd; border-radius: 4px; box-sizing: border-box; }}
            button {{ background: #1a73e8; color: white; border: none; padding: 10px 20px; border-radius: 4px; cursor: pointer; font-size: 16px; }}
            button:hover {{ background: #1557b0; }}
            .message {{ border-bottom: 1px solid #eee; padding: 10px 0; }}
            .message:last-child {{ border-bottom: none; }}
            small {{ color: #666; }}
            .error {{ color: #d93025; background: #fce8e6; padding: 10px; border-radius: 4px; margin-bottom: 15px; }}
            .status {{ display: inline-block; padding: 5px 10px; border-radius: 15px; font-size: 12px; font-weight: bold; }}
            .status.connected {{ background: #e6f4ea; color: #137333; }}
            .status.disconnected {{ background: #fce8e6; color: #c5221f; }}
        </style>
    </head>
    <body>
        <div class="container">
            <div class="card">
                <h1>🚀 Containerized AWS Architecture</h1>
                <p>Status: <span class="status {status_class}">{status_text}</span></p>
                <p>This application is running in a Docker container on EC2, connecting to RDS MySQL.</p>

                {error_html}

                <form method="POST" class="form-group">
                    <input type="text" name="content" placeholder="Type a message to save to the database..." required>
                    <div style="margin-top: 10px; text-align: right;">
                        <button type="submit">Save Message</button>
                    </div>
                </form>
            </div>

            <div class="card">
                <h2>Recent Messages</h2>
                {messages_html if messages else empty_html}
            </div>

            <div style="text-align: center; color: #666;">
                <p>Database Host: {DB_CONFIG['host']}</p>
            </div>
        </div>
    </body>
    </html>
    """


@app.route("/health")
def health():
    """Reports whether the app can reach the database. Returns 503 if it cannot."""
    try:
        connection = get_db_connection()
        if not (connection and connection.is_connected()):
            raise RuntimeError("Database connection could not be established")
        connection.close()
        return """
        <html>
        <head><title>Health Check</title>
        <style>
            body { font-family: Arial, sans-serif; margin: 40px; background: #f5f5f5; }
            .container { background: white; padding: 30px; border-radius: 10px; box-shadow: 0 2px 10px rgba(0,0,0,0.1); max-width: 600px; margin: auto; }
            .success { color: #1e8900; font-size: 24px; }
        </style>
        </head>
        <body>
            <div class="container">
                <h1 class="success">✅ Database Connected Successfully!</h1>
                <p>The Flask application is successfully connected to the RDS MySQL database.</p>
                <a href="/">← Back to Home</a>
            </div>
        </body>
        </html>
        """, 200
    except Exception as exc:
        return f"""
        <html>
        <head><title>Health Check</title>
        <style>
            body {{ font-family: Arial, sans-serif; margin: 40px; background: #f5f5f5; }}
            .container {{ background: white; padding: 30px; border-radius: 10px; box-shadow: 0 2px 10px rgba(0,0,0,0.1); max-width: 600px; margin: auto; }}
            .error {{ color: #d13212; font-size: 24px; }}
        </style>
        </head>
        <body>
            <div class="container">
                <h1 class="error">❌ Database Connection Failed</h1>
                <p>Error: {html.escape(str(exc))}</p>
                <a href="/">← Back to Home</a>
            </div>
        </body>
        </html>
        """, 503


@app.route("/db-info")
def db_info():
    """Shows the MySQL server version and current database name."""
    try:
        connection = get_db_connection()
        if not (connection and connection.is_connected()):
            raise RuntimeError("Database connection could not be established")
        cursor = connection.cursor()
        cursor.execute("SELECT VERSION()")
        version = cursor.fetchone()[0]
        cursor.execute("SELECT DATABASE()")
        current_db = cursor.fetchone()[0]
        cursor.close()
        connection.close()
        return f"""
        <html>
        <head><title>Database Info</title>
        <style>
            body {{ font-family: Arial, sans-serif; margin: 40px; background: #f5f5f5; }}
            .container {{ background: white; padding: 30px; border-radius: 10px; box-shadow: 0 2px 10px rgba(0,0,0,0.1); max-width: 600px; margin: auto; }}
            .info {{ background: #e7f3fe; padding: 15px; border-radius: 5px; margin: 10px 0; }}
        </style>
        </head>
        <body>
            <div class="container">
                <h1>📊 Database Information</h1>
                <div class="info">
                    <p><strong>MySQL Version:</strong> {html.escape(str(version))}</p>
                    <p><strong>Database Name:</strong> {html.escape(str(current_db))}</p>
                    <p><strong>Host:</strong> {DB_CONFIG['host']}</p>
                </div>
                <a href="/">← Back to Home</a>
            </div>
        </body>
        </html>
        """, 200
    except Exception as exc:
        return f"Error: {html.escape(str(exc))}", 503


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=80)
APPEOF

cat > Dockerfile << 'DOCKEREOF'
FROM python:3.12-slim

WORKDIR /app

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY app.py .

EXPOSE 80
CMD ["python", "app.py"]
DOCKEREOF

docker build -t portfolio-flask-app .
docker run -d -p 80:80 --name flask-container --restart unless-stopped portfolio-flask-app
