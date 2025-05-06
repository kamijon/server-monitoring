#!/bin/bash

# Exit on error
set -e

# Function to check if a command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Function to print status messages
print_status() {
    echo -e "\n\033[1;34m==>\033[0m \033[1m$1\033[0m"
}

# Function to print error messages
print_error() {
    echo -e "\n\033[1;31m==>\033[0m \033[1m$1\033[0m"
}

# Function to print success messages
print_success() {
    echo -e "\n\033[1;32m==>\033[0m \033[1m$1\033[0m"
}

# Function to check system requirements
check_requirements() {
    print_status "Checking system requirements..."
    
    # Check if running as root
    if [ "$EUID" -ne 0 ]; then
        print_error "Please run as root or with sudo"
        exit 1
    fi
    
    # Check if system is Ubuntu/Debian
    if ! command_exists apt; then
        print_error "This script requires Ubuntu/Debian system"
        exit 1
    fi
    
    # Check Python version
    if ! command_exists python3; then
        print_error "Python 3 is required but not installed"
        exit 1
    fi
    
    # Check available disk space (at least 1GB)
    local available_space=$(df -BG / | awk 'NR==2 {print $4}' | sed 's/G//')
    if [ "$available_space" -lt 1 ]; then
        print_error "At least 1GB of free disk space is required"
        exit 1
    fi
}

# Function to handle errors
handle_error() {
    print_error "An error occurred during installation"
    print_error "Please check the logs and try again"
    exit 1
}

# Set up error handling
trap 'handle_error' ERR

print_status "Starting installation of Server Monitoring..."

# Check system requirements
check_requirements

# Update system and install dependencies
print_status "Updating system and installing dependencies..."
apt update
apt upgrade -y
apt install -y python3 python3-pip python3-venv git supervisor ufw

# Create application directory
print_status "Creating application directory..."
mkdir -p /opt/server-monitoring
chown $SUDO_USER:$SUDO_USER /opt/server-monitoring

# Clone the repository
print_status "Cloning repository..."
if [ -d "/opt/server-monitoring/.git" ]; then
    cd /opt/server-monitoring
    git pull
else
    git clone https://github.com/kamijon/server-monitoring.git /opt/server-monitoring
fi

# Create and activate virtual environment
print_status "Setting up Python virtual environment..."
cd /opt/server-monitoring
python3 -m venv venv
source venv/bin/activate

# Install Python dependencies
print_status "Installing Python dependencies..."
pip install --upgrade pip
pip install -r requirements.txt

# Create log file and set permissions
print_status "Setting up log file..."
touch /opt/server-monitoring/server.log
chown $SUDO_USER:$SUDO_USER /opt/server-monitoring/server.log
chmod 644 /opt/server-monitoring/server.log

# Create log directory for supervisor
print_status "Setting up supervisor logs..."
mkdir -p /var/log/supervisor
chown -R $SUDO_USER:$SUDO_USER /var/log/supervisor

# Create database initialization script
print_status "Creating database initialization script..."
cat > /opt/server-monitoring/init_db.py << 'EOF'
import os
import sys
from sqlalchemy import create_engine, inspect
from sqlalchemy.orm import sessionmaker
from app.database import Base
from app.models import User
import bcrypt

# Database URL
SQLALCHEMY_DATABASE_URL = "sqlite:///./app.db"

def init_db():
    try:
        # Ensure we're in the correct directory
        os.chdir(os.path.dirname(os.path.abspath(__file__)))
        
        # Create engine
        print("Creating database engine...")
        engine = create_engine(SQLALCHEMY_DATABASE_URL, connect_args={"check_same_thread": False})
        
        # Check if tables exist
        inspector = inspect(engine)
        existing_tables = inspector.get_table_names()
        
        if not existing_tables:
            print("Creating database tables...")
            Base.metadata.create_all(bind=engine)
            print("Database tables created successfully")
        else:
            print("Database tables already exist")
        
        # Create session
        SessionLocal = sessionmaker(autocommit=False, autoflush=False, bind=engine)
        db = SessionLocal()
        
        try:
            print("Checking for existing admin user...")
            admin = db.query(User).filter(User.username == "admin").first()
            if not admin:
                print("Creating admin user...")
                hashed = bcrypt.hashpw("admin123".encode('utf-8'), bcrypt.gensalt())
                admin = User(username="admin", password=hashed.decode('utf-8'), is_admin=True)
                db.add(admin)
                db.commit()
                print("Admin user created successfully")
            else:
                print("Admin user already exists")
        except Exception as e:
            print(f"Error creating admin user: {str(e)}")
            db.rollback()
            raise
        finally:
            db.close()
    except Exception as e:
        print(f"Error initializing database: {str(e)}")
        sys.exit(1)

if __name__ == "__main__":
    init_db()
EOF

# Initialize database
print_status "Initializing database..."
cd /opt/server-monitoring
source venv/bin/activate
PYTHONPATH=/opt/server-monitoring python3 init_db.py

# Create Supervisor configuration
print_status "Configuring Supervisor..."
cat > /etc/supervisor/conf.d/server-monitoring.conf << EOF
[program:server-monitoring]
directory=/opt/server-monitoring
command=/opt/server-monitoring/venv/bin/uvicorn app.main:app --host 0.0.0.0 --port 8000
user=$SUDO_USER
autostart=true
autorestart=true
stderr_logfile=/var/log/supervisor/server-monitoring.err.log
stdout_logfile=/var/log/supervisor/server-monitoring.out.log
environment=PYTHONUNBUFFERED=1,PYTHONPATH=/opt/server-monitoring
EOF

# Reload Supervisor
print_status "Starting services..."
supervisorctl reread
supervisorctl update
supervisorctl restart server-monitoring

# Configure firewall
print_status "Configuring firewall..."
if command_exists ufw; then
    ufw allow 8000/tcp
    ufw allow 22/tcp
    ufw --force enable
fi

# Wait for the service to start
print_status "Waiting for service to start..."
sleep 5

# Check if the service is running
if supervisorctl status server-monitoring | grep -q "RUNNING"; then
    print_success "Installation completed successfully!"
    print_success "The application is now running at http://$(hostname -I | awk '{print $1}'):8000"
    print_success "Default login credentials:"
    print_success "Username: admin"
    print_success "Password: admin123"
    print_success "\nTo check the status, run: sudo supervisorctl status server-monitoring"
    print_success "To view logs, run: sudo tail -f /var/log/supervisor/server-monitoring.out.log"
else
    print_error "Service failed to start. Please check the logs:"
    print_error "sudo tail -f /var/log/supervisor/server-monitoring.err.log"
    exit 1
fi
