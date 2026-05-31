from contextlib import asynccontextmanager
from pathlib import Path
import torch
import torch.nn as nn
import timm
from pytorch_grad_cam import GradCAM

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from fastapi.staticfiles import StaticFiles

import models
from database import engine, Base, SessionLocal, run_lightweight_migrations
from storage import UPLOADS_DIR
from routes import auth_routes, admin_routes, predict_routes, chat_routes, report_routes, community_routes

MODEL_PATH = Path(r"/home/ec2-user/app/mobilenetv3_defect_4class.pt")
DEVICE = 'cuda' if torch.cuda.is_available() else 'cpu'

# Default defect-class -> fixer specialty mapping, seeded once into the DB.
DEFAULT_SPECIALTY_MAP = {
    "crack": "mason",
    "water_damage": "plumber",
    "paint_peeling": "painter",
    "rust": "welder",
}

def seed_defect_specialties():
    db = SessionLocal()
    try:
        if db.query(models.DefectSpecialty).count() == 0:
            for defect_class, specialty in DEFAULT_SPECIALTY_MAP.items():
                db.add(models.DefectSpecialty(defect_class=defect_class, specialty=specialty))
            db.commit()
    finally:
        db.close()

@asynccontextmanager
async def lifespan(app: FastAPI):
    Base.metadata.create_all(bind=engine)
    run_lightweight_migrations()
    seed_defect_specialties()

    if not MODEL_PATH.exists():
        print(f"!! PyTorch weights not found at {MODEL_PATH} — /predict will return 503.")
        app.state.model = None
        app.state.cam = None
        app.state.classes = []
    else:
        print(f"Loading PyTorch weights from {MODEL_PATH} ...")
        
        ckpt = torch.load(MODEL_PATH, map_location=DEVICE)
        classes = ckpt.get('classes', ['crack', 'water_damage', 'paint_peeling', 'rust'])
        
        # Initialize timm model matching the notebook
        model = timm.create_model('mobilenetv3_large_100', pretrained=False, num_classes=len(classes)).to(DEVICE)
        
        # Load state dict safely (handle DataParallel prefix mismatch)
        state_dict = ckpt['state_dict']
        if isinstance(model, nn.DataParallel) and not list(state_dict.keys())[0].startswith('module.'):
            state_dict = {f'module.{k}': v for k, v in state_dict.items()}
        elif not isinstance(model, nn.DataParallel) and list(state_dict.keys())[0].startswith('module.'):
            state_dict = {k.replace('module.', ''): v for k, v in state_dict.items()}
            
        model.load_state_dict(state_dict)
        model.eval()
        
        app.state.model = model
        app.state.classes = classes
        
        def unwrap(m):
            return m.module if isinstance(m, nn.DataParallel) else m
        
        target_layer = [unwrap(model).blocks[-1]]
        app.state.cam = GradCAM(model=model, target_layers=target_layer)
        
        print(f"MobileNetV3 classification model loaded. classes={classes}")

    yield
    app.state.model = None
    app.state.cam = None


app = FastAPI(title="CNN Defect Detection API", version="1.0.0", lifespan=lifespan)

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["*"],
    allow_headers=["*"],
)

# Serve uploaded report/community images.
app.mount("/uploads", StaticFiles(directory=str(UPLOADS_DIR)), name="uploads")

app.include_router(auth_routes.router)
app.include_router(admin_routes.router)
app.include_router(predict_routes.router)
app.include_router(chat_routes.router)
app.include_router(report_routes.router)
app.include_router(community_routes.router)

@app.get("/")
def root():
    return {"message": "API is running ✅"}

