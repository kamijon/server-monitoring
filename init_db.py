import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from app.database import Base, engine, SessionLocal
from app.models import User
import bcrypt

Base.metadata.create_all(bind=engine)

db = SessionLocal()
if not db.query(User).first():
    hashed = bcrypt.hashpw('admin123'.encode('utf-8'), bcrypt.gensalt())
    user = User(username='admin', password=hashed.decode('utf-8'), is_admin=True)
    db.add(user)
    db.commit()
    print("✅ Admin user created.")
else:
    print("ℹ️ Admin user already exists.")
db.close()
