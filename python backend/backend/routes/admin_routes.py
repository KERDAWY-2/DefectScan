from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.orm import Session
from database import get_db
from schemas import UserOut, FixerCreate, DefectSpecialtyOut
from typing import List, Optional
import models, auth
from auth import get_admin_user

router = APIRouter(prefix="/admin", tags=["Admin"])

@router.get("/users", response_model=List[UserOut])
def get_all_users(db: Session = Depends(get_db), admin: models.User = Depends(get_admin_user)):
    return db.query(models.User).all()

@router.delete("/users/{user_id}")
def delete_user(user_id: int, db: Session = Depends(get_db), admin: models.User = Depends(get_admin_user)):
    user = db.query(models.User).filter(models.User.id == user_id).first()
    if not user:
        raise HTTPException(status_code=404, detail="User not found")
    db.delete(user)
    db.commit()
    return {"message": f"User {user_id} deleted"}

@router.get("/specialties", response_model=List[DefectSpecialtyOut])
def list_specialties(db: Session = Depends(get_db), admin: models.User = Depends(get_admin_user)):
    """The defect-class -> specialty mapping, used to populate the 'create fixer'
    specialty dropdown and to suggest fixers when assigning a report."""
    return db.query(models.DefectSpecialty).all()

@router.post("/fixers", response_model=UserOut)
def create_fixer(payload: FixerCreate, db: Session = Depends(get_db), admin: models.User = Depends(get_admin_user)):
    """Admin creates a fixer account tagged with a specialty (e.g. plumber)."""
    if db.query(models.User).filter(models.User.username == payload.username).first():
        raise HTTPException(status_code=400, detail="Username already exists")
    if db.query(models.User).filter(models.User.email == payload.email).first():
        raise HTTPException(status_code=400, detail="Email already exists")
    if payload.national_id and db.query(models.User).filter(models.User.national_id == payload.national_id).first():
        raise HTTPException(status_code=400, detail="National ID already registered")
    if payload.mobile and db.query(models.User).filter(models.User.mobile == payload.mobile).first():
        raise HTTPException(status_code=400, detail="Mobile number already registered")

    fixer = models.User(
        username=payload.username,
        email=payload.email,
        hashed_password=auth.hash_password(payload.password),
        second_name=payload.second_name,
        national_id=payload.national_id,
        mobile=payload.mobile,
        address=payload.address,
        role="fixer",
        specialty=payload.specialty,
    )
    db.add(fixer)
    db.commit()
    db.refresh(fixer)
    return fixer

@router.get("/fixers", response_model=List[UserOut])
def list_fixers(specialty: Optional[str] = None, db: Session = Depends(get_db), admin: models.User = Depends(get_admin_user)):
    q = db.query(models.User).filter(models.User.role == "fixer")
    if specialty:
        q = q.filter(models.User.specialty == specialty)
    return q.all()
