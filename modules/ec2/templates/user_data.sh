#!/bin/bash
set -e

# Update system and install Docker
apt-get update
apt-get install -y docker.io mysql-client

# Start and enable Docker
systemctl start docker
systemctl enable docker

# Create app directory
mkdir -p /home/ubuntu/app
cd /home/ubuntu/app

# Create requirements.txt for Docker
cat > requirements.txt << 'REQEOF'
flask
mysql-connector-python
REQEOF

# Create the Python Flask application
cat > app.py << 'APPEOF'
from flask import Flask, request, redirect, url_for
import mysql.connector
import time
import os

app = Flask(__name__)

# Database configuration
DB_CONFIG = {
    "host": "${db_host}",
    "user": "${db_username}",
    "password": "${db_password}",
    "database": "${db_name}"
}

def get_db_connection():
    """Establish database connection with retry logic"""
    retries = 5
    while retries > 0:
        try:
            connection = mysql.connector.connect(**DB_CONFIG)
            return connection
        except Exception as e:
            retries -= 1
            if retries == 0:
                raise e
            time.sleep(3)
    return None

def init_db():
    """Initialize database table"""
    try:
        conn = get_db_connection()
        if conn:
            cursor = conn.cursor()
            cursor.execute("""
                CREATE TABLE IF NOT EXISTS messages (
                    id INT AUTO_INCREMENT PRIMARY KEY,
                    content VARCHAR(255) NOT NULL,
                    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
                )
            """)
            conn.commit()
            cursor.close()
            conn.close()
    except Exception as e:
        print(f"DB Init Error: {e}")

# Initialize DB on startup
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
                return redirect(url_for("home"))
            except Exception as e:
                error = str(e)

    if conn:
        try:
            cursor = conn.cursor()
            cursor.execute("SELECT content, created_at FROM messages ORDER BY created_at DESC LIMIT 10")
            messages = cursor.fetchall()
            cursor.close()
            conn.close()
        except Exception as e:
            error = str(e)
    else:
        error = "Could not connect to database"

    messages_html = "".join([f"<div class='message'><p>{m[0]}</p><small>{m[1]}</small></div>" for m in messages])

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
                <p>
                    Status:
                    <span class="status {'connected' if not error else 'disconnected'}">
                        {'● Connected to RDS' if not error else '● Disconnected'}
                    </span>
                </p>
                <p>This application is running in a Docker container on EC2, connecting to RDS MySQL.</p>

                {f'<div class="error">{error}</div>' if error else ''}

                <form method="POST" class="form-group">
                    <input type="text" name="content" placeholder="Type a message to save to the database..." required>
                    <div style="margin-top: 10px; text-align: right;">
                        <button type="submit">Save Message</button>
                    </div>
                </form>
            </div>

            <div class="card">
                <h2>Recent Messages</h2>
                {messages_html if messages else '<p>No messages yet. Be the first to post!</p>'}
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
    try:
        connection = get_db_connection()
        if connection and connection.is_connected():
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
            """
    except Exception as e:
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
                <p>Error: {str(e)}</p>
                <a href="/">← Back to Home</a>
            </div>
        </body>
        </html>
        """, 500

@app.route("/db-info")
def db_info():
    try:
        connection = get_db_connection()
        if connection and connection.is_connected():
            cursor = connection.cursor()
            cursor.execute("SELECT VERSION()")
            version = cursor.fetchone()[0]
            cursor.execute("SELECT DATABASE()")
            db_name = cursor.fetchone()[0]
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
                        <p><strong>MySQL Version:</strong> {version}</p>
                        <p><strong>Database Name:</strong> {db_name}</p>
                        <p><strong>Host:</strong> ${db_host}</p>
                    </div>
                    <a href="/">← Back to Home</a>
                </div>
            </body>
            </html>
            """
    except Exception as e:
        return f"Error: {str(e)}", 500

if __name__ == "__main__":
    app.run(host='0.0.0.0', port=80)
APPEOF

# Create the Dockerfile
cat > Dockerfile << 'DOCKEREOF'
FROM python:3.9-slim
WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
COPY app.py .
EXPOSE 80
CMD ["python", "app.py"]
DOCKEREOF

# Build and run the Docker container
docker build -t portfolio-flask-app .
docker run -d -p 80:80 --name flask-container --restart unless-stopped portfolio-flask-app