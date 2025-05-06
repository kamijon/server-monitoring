#!/bin/bash

# Exit on error
set -e

echo "🔧 Starting installation of Server Monitoring..."

# Update and install dependencies
echo "📦 Installing system dependencies..."
sudo apt update
sudo apt install -y python3-full python3-pip python3-venv git supervisor ufw

# Setup directory
echo "📁 Creating project directory..."
sudo mkdir -p /opt/server-monitoring
sudo chown $USER:$USER /opt/server-monitoring

# Clone repository
echo "📥 Cloning repository..."
git clone https://github.com/kamijon/server-monitoring.git /opt/server-monitoring

# Setup Python venv
cd /opt/server-monitoring
echo "🐍 Setting up virtual environment..."
python3 -m venv venv
source venv/bin/activate
pip install --upgrade pip

# Install Python dependencies
echo "📦 Installing Python packages..."
pip install -r requirements.txt || pip install uvicorn[standard]  # fallback if uvicorn missing

# Create log file
echo "📝 Creating log file..."
sudo touch /opt/server-monitoring/server.log
sudo chown $USER:$USER /opt/server-monitoring/server.log

# Create initial database and admin user
echo "🛠️ Creating database and admin user..."
cat << EOF > /opt/server-monitoring/init_db.py
import os, sys, bcrypt
sys.path.append(os.path.dirname(os.path.abspath(__file__)))
from app.database import Base, engine, SessionLocal
from app.models import User

Base.metadata.create_all(bind=engine)
db = SessionLocal()
if not db.query(User).first():
    hashed = bcrypt.hashpw('admin123'.encode('utf-8'), bcrypt.gensalt())
    user = User(username='admin', password=hashed.decode('utf-8'), is_admin=True)
    db.add(user)
    db.commit()
    print("✅ Admin user created.")
else:
    print("ℹ️ Admin already exists.")
db.close()
EOF

PYTHONPATH=/opt/server-monitoring venv/bin/python3 init_db.py
rm init_db.py

# Configure Supervisor
echo "⚙️ Configuring Supervisor..."
sudo tee /etc/supervisor/conf.d/server-monitoring.conf > /dev/null << EOF
[program:server-monitoring]
directory=/opt/server-monitoring
command=/opt/server-monitoring/venv/bin/uvicorn app.main:app --host 0.0.0.0 --port 8000
user=$USER
autostart=true
autorestart=true
stderr_logfile=/var/log/supervisor/server-monitoring.err.log
stdout_logfile=/var/log/supervisor/server-monitoring.out.log
environment=PYTHONUNBUFFERED=1
EOF

# Restart Supervisor
sudo supervisorctl reread
sudo supervisorctl update
sudo supervisorctl restart server-monitoring

# Firewall settings
echo "🛡️ Configuring firewall..."
sudo ufw allow 8000/tcp
sudo ufw allow 22/tcp
sudo ufw --force enable

# Done
echo "✅ Installation complete!"
echo "➡️ Access at: http://your-server-ip:8000"
echo "👤 Default login: admin / admin123"
echo "📊 To check status: sudo supervisorctl status server-monitoring"
echo "📄 To view logs: sudo tail -f /var/log/supervisor/server-monitoring.out.log"
