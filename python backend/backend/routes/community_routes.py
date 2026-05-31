import json
from typing import List, Optional

from fastapi import (
    APIRouter, Depends, File, HTTPException, Query, UploadFile,
    WebSocket, WebSocketDisconnect,
)
from sqlalchemy.orm import Session

from database import get_db
import models
from auth import get_current_user
from schemas import PostOut
from storage import save_bytes
from routes.chat_routes import get_current_user_ws

router = APIRouter(prefix="/community", tags=["Community"])

ALLOWED_EMOJIS = {"👍", "❤️", "😮", "😢", "🔧"}


class CommunityConnectionManager:
    """Single global feed room — every authenticated client receives every event."""
    def __init__(self):
        self.connections: List[WebSocket] = []

    async def connect(self, websocket: WebSocket):
        await websocket.accept()
        self.connections.append(websocket)

    def disconnect(self, websocket: WebSocket):
        if websocket in self.connections:
            self.connections.remove(websocket)

    async def broadcast(self, message: dict):
        payload = json.dumps(message)
        for conn in list(self.connections):
            try:
                await conn.send_text(payload)
            except Exception:
                self.disconnect(conn)


manager = CommunityConnectionManager()


# --- Serialization helpers ---

def reaction_summary(db: Session, current_user_id: Optional[int], post_id=None, comment_id=None):
    q = db.query(models.CommunityReaction)
    q = q.filter(models.CommunityReaction.post_id == post_id) if post_id is not None \
        else q.filter(models.CommunityReaction.comment_id == comment_id)
    by_emoji = {}
    for r in q.all():
        entry = by_emoji.setdefault(r.emoji, {"emoji": r.emoji, "count": 0, "reacted": False})
        entry["count"] += 1
        if current_user_id is not None and r.user_id == current_user_id:
            entry["reacted"] = True
    return list(by_emoji.values())


def serialize_comment(db: Session, c: models.CommunityComment, current_user_id: Optional[int]):
    author = db.query(models.User).filter(models.User.id == c.author_id).first()
    return {
        "id": c.id,
        "post_id": c.post_id,
        "author_id": c.author_id,
        "author_name": author.username if author else None,
        "content": c.content,
        "created_at": c.created_at.isoformat(),
        "reactions": reaction_summary(db, current_user_id, comment_id=c.id),
    }


def serialize_post(db: Session, p: models.CommunityPost, current_user_id: Optional[int]):
    author = db.query(models.User).filter(models.User.id == p.author_id).first()
    comments = (
        db.query(models.CommunityComment)
        .filter(models.CommunityComment.post_id == p.id)
        .order_by(models.CommunityComment.created_at.asc())
        .all()
    )
    return {
        "id": p.id,
        "author_id": p.author_id,
        "author_name": author.username if author else None,
        "content": p.content,
        "image_path": p.image_path,
        "created_at": p.created_at.isoformat(),
        "reactions": reaction_summary(db, current_user_id, post_id=p.id),
        "comments": [serialize_comment(db, c, current_user_id) for c in comments],
    }


# --- REST: history + image upload ---

@router.get("/posts", response_model=List[PostOut])
def list_posts(db: Session = Depends(get_db), current_user: models.User = Depends(get_current_user)):
    posts = db.query(models.CommunityPost).order_by(models.CommunityPost.created_at.desc()).all()
    return [serialize_post(db, p, current_user.id) for p in posts]


@router.post("/upload-image")
async def upload_image(
    file: UploadFile = File(...),
    db: Session = Depends(get_db),
    current_user: models.User = Depends(get_current_user),
):
    if file.content_type and not file.content_type.startswith("image/"):
        raise HTTPException(status_code=415, detail="Only image uploads are allowed.")
    data = await file.read()
    if not data:
        raise HTTPException(status_code=400, detail="Empty upload")
    if len(data) > 10 * 1024 * 1024:
        raise HTTPException(status_code=413, detail="Image too large (max 10 MB).")
    path = save_bytes(data, ext="jpg")
    return {"image_path": path, "image_url": f"/uploads/{path}"}


# --- WebSocket: live post / comment / react ---

@router.websocket("/ws")
async def community_ws(websocket: WebSocket, token: str = Query(...), db: Session = Depends(get_db)):
    user = get_current_user_ws(token, db)
    if not user:
        await websocket.close(code=1008)
        return

    await manager.connect(websocket)
    try:
        while True:
            raw = await websocket.receive_text()
            try:
                data = json.loads(raw)
            except json.JSONDecodeError:
                continue
            action = data.get("action")

            if action == "post":
                content = (data.get("content") or "").strip()
                image_path = data.get("image_path")
                if not content and not image_path:
                    continue
                post = models.CommunityPost(author_id=user.id, content=content, image_path=image_path)
                db.add(post)
                db.commit()
                db.refresh(post)
                await manager.broadcast({"type": "new_post", "post": serialize_post(db, post, None)})

            elif action == "comment":
                post_id = data.get("post_id")
                content = (data.get("content") or "").strip()
                if not post_id or not content:
                    continue
                comment = models.CommunityComment(post_id=post_id, author_id=user.id, content=content)
                db.add(comment)
                db.commit()
                db.refresh(comment)
                await manager.broadcast({"type": "new_comment", "comment": serialize_comment(db, comment, None)})

            elif action == "react":
                emoji = data.get("emoji")
                post_id = data.get("post_id")
                comment_id = data.get("comment_id")
                if emoji not in ALLOWED_EMOJIS or (post_id is None and comment_id is None):
                    continue
                # Toggle: remove this user's identical reaction if present, else add it.
                existing = (
                    db.query(models.CommunityReaction)
                    .filter(
                        models.CommunityReaction.user_id == user.id,
                        models.CommunityReaction.emoji == emoji,
                        models.CommunityReaction.post_id == post_id,
                        models.CommunityReaction.comment_id == comment_id,
                    )
                    .first()
                )
                if existing:
                    db.delete(existing)
                else:
                    db.add(models.CommunityReaction(
                        user_id=user.id, emoji=emoji, post_id=post_id, comment_id=comment_id,
                    ))
                db.commit()
                count = (
                    db.query(models.CommunityReaction)
                    .filter(
                        models.CommunityReaction.emoji == emoji,
                        models.CommunityReaction.post_id == post_id,
                        models.CommunityReaction.comment_id == comment_id,
                    )
                    .count()
                )
                await manager.broadcast({
                    "type": "reaction",
                    "post_id": post_id,
                    "comment_id": comment_id,
                    "emoji": emoji,
                    "count": count,
                })

    except WebSocketDisconnect:
        manager.disconnect(websocket)
    except Exception:
        manager.disconnect(websocket)
