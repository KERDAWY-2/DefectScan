import base64
import io
from datetime import datetime, timedelta

import cv2
import numpy as np
import torch
from torchvision import transforms
from fastapi import APIRouter, Depends, File, HTTPException, Request, UploadFile
from sqlalchemy.orm import Session
from PIL import Image, ImageOps

from auth import get_current_user
from database import get_db
import models
from storage import save_bytes

router = APIRouter(prefix="/predict", tags=["Predict"])

DEVICE = 'cuda' if torch.cuda.is_available() else 'cpu'
IMG_SIZE = 384
MEAN = [0.485, 0.456, 0.406]
STD = [0.229, 0.224, 0.225]
CONF_THRESHOLD = 0.5

# F1 — upload validation
MAX_UPLOAD_BYTES = 10 * 1024 * 1024  # 10 MB
ALLOWED_FORMATS = {"JPEG", "PNG", "WEBP", "MPO"}  # MPO = multi-picture JPEG from some cameras
EXT_BY_FORMAT = {"JPEG": "jpg", "MPO": "jpg", "PNG": "png", "WEBP": "webp"}
# F2 — rate limit
MAX_UPLOADS_PER_HOUR = 10

val_tf = transforms.Compose([
    transforms.Resize(IMG_SIZE + 32),
    transforms.CenterCrop(IMG_SIZE),
    transforms.ToTensor(),
    transforms.Normalize(MEAN, STD),
])

@router.post("/")
async def predict(
    request: Request,
    file: UploadFile = File(...),
    db: Session = Depends(get_db),
    current_user=Depends(get_current_user),
):
    model = getattr(request.app.state, "model", None)
    cam = getattr(request.app.state, "cam", None)
    classes = getattr(request.app.state, "classes", [])

    if model is None or cam is None:
        raise HTTPException(status_code=503, detail="Model not loaded")

    # F2 — rate limit (rolling 60-minute window), checked before any inference work.
    one_hour_ago = datetime.utcnow() - timedelta(hours=1)
    recent_uploads = (
        db.query(models.Report)
        .filter(models.Report.user_id == current_user.id, models.Report.created_at >= one_hour_ago)
        .count()
    )
    if recent_uploads >= MAX_UPLOADS_PER_HOUR:
        raise HTTPException(
            status_code=429,
            detail=f"Upload limit reached ({MAX_UPLOADS_PER_HOUR} per hour). Please try again later.",
        )

    # F1 — reject obviously non-image content types early (PIL is the source of truth below).
    if file.content_type and not file.content_type.startswith("image/") and file.content_type != "application/octet-stream":
        raise HTTPException(status_code=415, detail=f"Unsupported file type '{file.content_type}'. Upload an image.")

    raw_bytes = await file.read()
    if not raw_bytes:
        raise HTTPException(status_code=400, detail="Empty upload")
    if len(raw_bytes) > MAX_UPLOAD_BYTES:
        raise HTTPException(status_code=413, detail="Image too large (max 10 MB).")

    try:
        pil = Image.open(io.BytesIO(raw_bytes))
        img_format = (pil.format or "").upper()
        img = ImageOps.exif_transpose(pil).convert("RGB")
    except Exception as e:
        raise HTTPException(status_code=400, detail=f"Invalid image: {e}")

    if img_format not in ALLOWED_FORMATS:
        raise HTTPException(status_code=415, detail=f"Unsupported image format '{img_format or 'unknown'}'. Allowed: JPEG, PNG, WEBP.")

    # Run inference
    x = val_tf(img).unsqueeze(0).to(DEVICE)
    with torch.no_grad():
        logits = model(x)
        probs = torch.sigmoid(logits)[0].cpu().numpy()

    top_idx = int(np.argmax(probs))
    top_prob = probs[top_idx]

    detections = [f"{classes[i]} ({p:.2f})" for i, p in enumerate(probs) if p > CONF_THRESHOLD]
    num_detections = len(detections)

    if num_detections == 0:
        # Clean background: no Grad-CAM, just echo the original image back.
        text = "No defects detected."
        primary_class = None
        img_bgr = cv2.cvtColor(np.array(img), cv2.COLOR_RGB2BGR)
    else:
        text = ", ".join(detections)
        primary_class = classes[top_idx]

        from pytorch_grad_cam.utils.model_targets import ClassifierOutputTarget
        from pytorch_grad_cam.utils.image import show_cam_on_image

        heat = cam(input_tensor=x, targets=[ClassifierOutputTarget(top_idx)])[0]
        rgb = np.array(img.resize((IMG_SIZE, IMG_SIZE))).astype(np.float32) / 255.0
        overlay = show_cam_on_image(rgb, heat, use_rgb=True)
        img_bgr = cv2.cvtColor((overlay * 255).astype(np.uint8), cv2.COLOR_RGB2BGR)

        # Label banner with the top prediction
        label = f"{classes[top_idx]} ({top_prob:.2f})"
        (tw, th), _ = cv2.getTextSize(label, cv2.FONT_HERSHEY_SIMPLEX, 0.8, 2)
        cv2.rectangle(img_bgr, (5, 5), (5 + tw + 10, 5 + th + 15), (0, 0, 0), -1)
        cv2.putText(img_bgr, label, (10, 5 + th + 5), cv2.FONT_HERSHEY_SIMPLEX, 0.8, (255, 255, 255), 2)

    ok, buf = cv2.imencode(".jpg", img_bgr, [cv2.IMWRITE_JPEG_QUALITY, 85])
    result_jpg = buf.tobytes() if ok else None
    image_b64 = base64.b64encode(result_jpg).decode("ascii") if result_jpg else None

    # F5 — persist original + annotated images and create the report row.
    image_path = save_bytes(raw_bytes, ext=EXT_BY_FORMAT.get(img_format, "jpg"))
    result_image_path = save_bytes(result_jpg, ext="jpg") if result_jpg else None

    report = models.Report(
        user_id=current_user.id,
        image_path=image_path,
        result_image_path=result_image_path,
        result=text,
        primary_class=primary_class,
        num_detections=num_detections,
        status="pending",
    )
    db.add(report)
    db.commit()
    db.refresh(report)

    print(
        f"[predict] user={getattr(current_user, 'username', '?')} "
        f"img={img.size} -> {text} (report #{report.id})"
    )

    return {
        "result": text,
        "image_b64": image_b64,
        "num_detections": num_detections,
        "report_id": report.id,
        "image_url": f"/uploads/{image_path}",
        "result_image_url": f"/uploads/{result_image_path}" if result_image_path else None,
    }
