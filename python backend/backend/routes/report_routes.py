from typing import List, Optional

from fastapi import APIRouter, Depends, HTTPException, Query
from sqlalchemy.orm import Session

from database import get_db
import models
from auth import get_current_user, get_admin_user, get_fixer_user
from schemas import ReportOut, ReportMetadataUpdate, AssignFixer, UserOut
from storage import delete_file

router = APIRouter(prefix="/reports", tags=["Reports"])

VALID_SEVERITIES = {"low", "medium", "high"}

# --- Reporter-facing ---

@router.get("/me", response_model=List[ReportOut])
def my_reports(db: Session = Depends(get_db), current_user: models.User = Depends(get_current_user)):
    return (
        db.query(models.Report)
        .filter(models.Report.user_id == current_user.id)
        .order_by(models.Report.created_at.desc())
        .all()
    )

# --- Fixer-facing ---

@router.get("/assigned", response_model=List[ReportOut])
def assigned_reports(db: Session = Depends(get_db), fixer: models.User = Depends(get_fixer_user)):
    return (
        db.query(models.Report)
        .filter(models.Report.assigned_fixer_id == fixer.id)
        .order_by(models.Report.created_at.desc())
        .all()
    )

# --- Admin-facing list with filter/sort ---

@router.get("", response_model=List[ReportOut])
@router.get("/", response_model=List[ReportOut])
def list_reports(
    location: Optional[str] = None,
    status: Optional[str] = None,
    sort_by: str = Query("created_at", pattern="^(created_at|location|severity|status)$"),
    order: str = Query("desc", pattern="^(asc|desc)$"),
    db: Session = Depends(get_db),
    admin: models.User = Depends(get_admin_user),
):
    q = db.query(models.Report)
    q = q.filter(models.Report.num_detections > 0)
    if location:
        q = q.filter(models.Report.location.ilike(f"%{location}%"))
    if status:
        q = q.filter(models.Report.status == status)

    sort_col = getattr(models.Report, sort_by)
    q = q.order_by(sort_col.asc() if order == "asc" else sort_col.desc())
    return q.all()

# --- Shared lookup ---

def _get_report_or_404(report_id: int, db: Session) -> models.Report:
    report = db.query(models.Report).filter(models.Report.id == report_id).first()
    if not report:
        raise HTTPException(status_code=404, detail="Report not found")
    return report

@router.get("/{report_id}", response_model=ReportOut)
def get_report(report_id: int, db: Session = Depends(get_db), current_user: models.User = Depends(get_current_user)):
    report = _get_report_or_404(report_id, db)
    allowed = (
        current_user.role == "admin"
        or report.user_id == current_user.id
        or report.assigned_fixer_id == current_user.id
    )
    if not allowed:
        raise HTTPException(status_code=403, detail="Not authorized to view this report")
    return report

@router.patch("/{report_id}", response_model=ReportOut)
def update_metadata(
    report_id: int,
    payload: ReportMetadataUpdate,
    db: Session = Depends(get_db),
    current_user: models.User = Depends(get_current_user),
):
    """The metadata form: reporter (or admin) fills location/severity/description."""
    report = _get_report_or_404(report_id, db)
    if current_user.role != "admin" and report.user_id != current_user.id:
        raise HTTPException(status_code=403, detail="Not authorized to edit this report")

    if payload.severity is not None and payload.severity not in VALID_SEVERITIES:
        raise HTTPException(status_code=422, detail=f"severity must be one of {sorted(VALID_SEVERITIES)}")

    if payload.location is not None:
        report.location = payload.location
    if payload.severity is not None:
        report.severity = payload.severity
    if payload.description is not None:
        report.description = payload.description

    db.commit()
    db.refresh(report)
    return report

@router.delete("/{report_id}")
def delete_report(report_id: int, db: Session = Depends(get_db), admin: models.User = Depends(get_admin_user)):
    report = _get_report_or_404(report_id, db)
    delete_file(report.image_path)
    delete_file(report.result_image_path)
    db.delete(report)
    db.commit()
    return {"ok": True}

# --- Admin assignment + completion (F6 loop) ---

@router.get("/{report_id}/suggested-fixers", response_model=List[UserOut])
def suggested_fixers(report_id: int, db: Session = Depends(get_db), admin: models.User = Depends(get_admin_user)):
    """Fixers whose specialty matches the report's primary defect class."""
    report = _get_report_or_404(report_id, db)
    mapping = (
        db.query(models.DefectSpecialty)
        .filter(models.DefectSpecialty.defect_class == report.primary_class)
        .first()
    )
    if not mapping:
        return []
    return (
        db.query(models.User)
        .filter(models.User.role == "fixer", models.User.specialty == mapping.specialty)
        .all()
    )

@router.post("/{report_id}/assign", response_model=ReportOut)
def assign_fixer(
    report_id: int,
    payload: AssignFixer,
    db: Session = Depends(get_db),
    admin: models.User = Depends(get_admin_user),
):
    report = _get_report_or_404(report_id, db)
    fixer = db.query(models.User).filter(models.User.id == payload.fixer_id).first()
    if not fixer or fixer.role != "fixer":
        raise HTTPException(status_code=400, detail="Target user is not a fixer")

    report.assigned_fixer_id = fixer.id
    report.status = "assigned"
    db.commit()
    db.refresh(report)
    return report

@router.post("/{report_id}/fixer-done", response_model=ReportOut)
def fixer_done(report_id: int, db: Session = Depends(get_db), fixer: models.User = Depends(get_fixer_user)):
    report = _get_report_or_404(report_id, db)
    if report.assigned_fixer_id != fixer.id:
        raise HTTPException(status_code=403, detail="This report is not assigned to you")
    if report.status not in ("assigned", "fixer_done"):
        raise HTTPException(status_code=409, detail=f"Cannot mark done from status '{report.status}'")

    report.status = "fixer_done"
    db.commit()
    db.refresh(report)
    return report

@router.post("/{report_id}/complete", response_model=ReportOut)
def complete_report(report_id: int, db: Session = Depends(get_db), admin: models.User = Depends(get_admin_user)):
    report = _get_report_or_404(report_id, db)
    if report.status != "fixer_done":
        raise HTTPException(
            status_code=409,
            detail="Report can only be completed after the fixer marks it done",
        )
    report.status = "completed"
    db.commit()
    db.refresh(report)
    return report
