import os
import sys

sys.path.append(os.path.dirname(os.path.abspath(__file__)))

from app.database import Base, engine

Base.metadata.create_all(bind=engine)

print("✅ Database and tables created successfully.")
