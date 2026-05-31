from fastapi import APIRouter, WebSocket, WebSocketDisconnect, Depends, HTTPException, Query
from sqlalchemy.orm import Session
from database import get_db
import models, auth
from schemas import AiChatRequest, AiChatResponse
from typing import List, Dict, Optional
from pydantic import BaseModel
from datetime import datetime
import json
import os

router = APIRouter(prefix="/chat", tags=["Chat"])

# --- Gemini AI assistant (F4) ---
GEMINI_MODEL = os.getenv("GEMINI_MODEL", "gemini-2.5-flash")
AI_HISTORY_LIMIT = 12  # recent messages passed to Gemini for context
AI_SYSTEM_PROMPT = (
    "You are the in-app support assistant for a building-defect detection app. "
    "The app's model classifies four defect types: crack, water_damage, paint_peeling, and rust. "
    "Help users understand their detection results, assess severity, and take sensible next steps "
    "(e.g. when to call a professional). Be concise, friendly, and practical. "
    "You are not a substitute for a licensed engineer for structural safety concerns."
)

_genai_client = None

def _get_genai_client():
    """Lazily build the Gemini client so the server still boots when the
    package/key is absent; failures surface as a clean 503 from /chat/ai."""
    global _genai_client
    if _genai_client is not None:
        return _genai_client
    api_key = os.getenv("GEMINI_API_KEY")
    if not api_key:
        raise HTTPException(status_code=503, detail="AI assistant is not configured (missing GEMINI_API_KEY).")
    try:
        from google import genai
    except ImportError:
        raise HTTPException(status_code=503, detail="AI assistant unavailable (google-genai not installed).")
    _genai_client = genai.Client(api_key=api_key)
    return _genai_client

class MessageOut(BaseModel):
    id: int
    user_id: int
    sender_id: Optional[int] = None  # NULL for AI-generated messages
    content: str
    is_ai: bool = False
    timestamp: datetime

    class Config:
        from_attributes = True

class ConnectionManager:
    def __init__(self):
        # Maps user_id to a list of active websockets (the user and possibly an admin)
        self.active_connections: Dict[int, List[WebSocket]] = {}

    async def connect(self, websocket: WebSocket, user_id: int):
        await websocket.accept()
        if user_id not in self.active_connections:
            self.active_connections[user_id] = []
        self.active_connections[user_id].append(websocket)

    def disconnect(self, websocket: WebSocket, user_id: int):
        if user_id in self.active_connections:
            if websocket in self.active_connections[user_id]:
                self.active_connections[user_id].remove(websocket)
            if not self.active_connections[user_id]:
                del self.active_connections[user_id]

    async def broadcast(self, message: str, user_id: int):
        if user_id in self.active_connections:
            for connection in self.active_connections[user_id]:
                await connection.send_text(message)

manager = ConnectionManager()

def get_current_user_ws(token: str, db: Session):
    try:
        from jose import jwt
        from auth import SECRET_KEY, ALGORITHM
        payload = jwt.decode(token, SECRET_KEY, algorithms=[ALGORITHM])
        user_id = payload.get("sub")
        if user_id is None:
            return None
        user = db.query(models.User).filter(models.User.id == int(user_id)).first()
        return user
    except Exception:
        return None

@router.websocket("/ws/{user_id}")
async def websocket_endpoint(websocket: WebSocket, user_id: int, token: str = Query(...), db: Session = Depends(get_db)):
    user = get_current_user_ws(token, db)
    if not user:
        await websocket.close(code=1008)
        return
    
    # Only admins or the owner of the chat can connect to this specific user_id's room
    if user.role != "admin" and user.id != user_id:
        await websocket.close(code=1008)
        return

    await manager.connect(websocket, user_id)
    try:
        while True:
            data = await websocket.receive_text()
            
            # Save to DB
            msg = models.Message(user_id=user_id, sender_id=user.id, content=data)
            db.add(msg)
            db.commit()
            db.refresh(msg)
            
            # Broadcast the message to everyone in the room
            payload = {
                "id": msg.id,
                "user_id": msg.user_id,
                "sender_id": msg.sender_id,
                "content": msg.content,
                "is_ai": bool(msg.is_ai),
                "timestamp": msg.timestamp.isoformat()
            }
            await manager.broadcast(json.dumps(payload), user_id)
            
    except WebSocketDisconnect:
        manager.disconnect(websocket, user_id)

@router.get("/history/{user_id}", response_model=List[MessageOut])
def get_history(user_id: int, db: Session = Depends(get_db), current_user: models.User = Depends(auth.get_current_user)):
    if current_user.role != "admin" and current_user.id != user_id:
        raise HTTPException(status_code=403, detail="Not authorized to view this chat history")
    return db.query(models.Message).filter(models.Message.user_id == user_id).order_by(models.Message.timestamp.asc()).all()

@router.post("/ai", response_model=AiChatResponse)
def chat_ai(payload: AiChatRequest, db: Session = Depends(get_db), current_user: models.User = Depends(auth.get_current_user)):
    """AI-assistant mode: persist the user's message, ask Gemini using recent
    room history as context, persist and return the AI reply. Sync def on
    purpose — the Gemini call is blocking, so FastAPI runs it in a threadpool."""
    room_id = payload.room_user_id
    if current_user.role != "admin" and current_user.id != room_id:
        raise HTTPException(status_code=403, detail="Not authorized for this chat room")

    text = payload.message.strip()
    if not text:
        raise HTTPException(status_code=400, detail="Empty message")

    # Persist the user's message in the same room as human chat.
    user_msg = models.Message(user_id=room_id, sender_id=current_user.id, content=text, is_ai=False)
    db.add(user_msg)
    db.commit()
    db.refresh(user_msg)

    # Build conversation context from recent room history (oldest -> newest).
    recent = (
        db.query(models.Message)
        .filter(models.Message.user_id == room_id)
        .order_by(models.Message.timestamp.desc())
        .limit(AI_HISTORY_LIMIT)
        .all()
    )
    recent = list(reversed(recent))

    client = _get_genai_client()
    from google.genai import types

    contents = [
        types.Content(
            role="model" if m.is_ai else "user",
            parts=[types.Part.from_text(text=m.content)],
        )
        for m in recent
    ]
    # Gemini expects the conversation to start with a user turn.
    while contents and contents[0].role == "model":
        contents.pop(0)

    try:
        response = client.models.generate_content(
            model=GEMINI_MODEL,
            contents=contents,
            config=types.GenerateContentConfig(
                system_instruction=AI_SYSTEM_PROMPT,
                temperature=0.4,
                max_output_tokens=600,
            ),
        )
        reply_text = (response.text or "").strip() or "Sorry, I couldn't generate a response right now."
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=502, detail=f"AI request failed: {e}")

    ai_msg = models.Message(user_id=room_id, sender_id=None, content=reply_text, is_ai=True)
    db.add(ai_msg)
    db.commit()
    db.refresh(ai_msg)

    return {"reply": reply_text}
