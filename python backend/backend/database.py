from sqlalchemy import create_engine, inspect, text
from sqlalchemy.ext.declarative import declarative_base
from sqlalchemy.orm import sessionmaker

SQLALCHEMY_DATABASE_URL = "sqlite:///./app.db"

engine = create_engine(SQLALCHEMY_DATABASE_URL, connect_args={"check_same_thread": False})
SessionLocal = sessionmaker(autocommit=False, autoflush=False, bind=engine)
Base = declarative_base()

def get_db():
    db = SessionLocal()
    try:
        yield db
    finally:
        db.close()

def run_lightweight_migrations():
    """Add columns introduced after a table was first created.

    `Base.metadata.create_all` creates *new tables* but never alters existing
    ones, so an `app.db` from before these features lacks `users.specialty` and
    `messages.is_ai`. Add them idempotently with SQLite `ALTER TABLE ... ADD
    COLUMN`. New tables (reports, community_*, ...) are handled by create_all.
    Run this AFTER create_all.
    """
    inspector = inspect(engine)
    existing_tables = set(inspector.get_table_names())

    def missing_columns(table, columns):
        if table not in existing_tables:
            return {}  # create_all already built it with the full schema
        present = {col["name"] for col in inspector.get_columns(table)}
        return {name: ddl for name, ddl in columns.items() if name not in present}

    pending = {
        "users": missing_columns("users", {"specialty": "VARCHAR"}),
        "messages": missing_columns("messages", {"is_ai": "BOOLEAN DEFAULT 0"}),
    }

    with engine.begin() as conn:
        for table, columns in pending.items():
            for name, ddl in columns.items():
                conn.execute(text(f"ALTER TABLE {table} ADD COLUMN {name} {ddl}"))
