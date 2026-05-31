from pydantic import BaseModel, EmailStr
from typing import Optional, List
from datetime import datetime

class UserCreate(BaseModel):
    username: str
    email: EmailStr
    password: str
    second_name: str
    national_id: str
    mobile: str
    address: str

class UserLogin(BaseModel):
    username: str
    password: str

class UserOut(BaseModel):
    id: int
    username: str
    email: str
    second_name: Optional[str] = None
    national_id: Optional[str] = None
    mobile: Optional[str] = None
    address: Optional[str] = None
    role: str
    specialty: Optional[str] = None
    is_active: bool

    class Config:
        from_attributes = True

class Token(BaseModel):
    access_token: str
    token_type: str

# --- Fixers / specialties (F6) ---

class FixerCreate(BaseModel):
    username: str
    email: EmailStr
    password: str
    second_name: Optional[str] = None
    national_id: Optional[str] = None
    mobile: Optional[str] = None
    address: Optional[str] = None
    specialty: str

class DefectSpecialtyOut(BaseModel):
    id: int
    defect_class: str
    specialty: str

    class Config:
        from_attributes = True

# --- Reports (F5) ---

class ReportOut(BaseModel):
    id: int
    user_id: int
    image_path: Optional[str] = None
    result_image_path: Optional[str] = None
    result: Optional[str] = None
    primary_class: Optional[str] = None
    num_detections: int = 0
    location: Optional[str] = None
    severity: Optional[str] = None
    description: Optional[str] = None
    status: str
    assigned_fixer_id: Optional[int] = None
    created_at: datetime
    updated_at: Optional[datetime] = None

    class Config:
        from_attributes = True

class ReportMetadataUpdate(BaseModel):
    location: Optional[str] = None
    severity: Optional[str] = None      # low | medium | high
    description: Optional[str] = None

class AssignFixer(BaseModel):
    fixer_id: int

# --- Community (F3) ---

class ReactionCount(BaseModel):
    emoji: str
    count: int
    reacted: bool = False  # whether the requesting user reacted with this emoji

class CommentOut(BaseModel):
    id: int
    post_id: int
    author_id: int
    author_name: Optional[str] = None
    content: str
    created_at: datetime
    reactions: List[ReactionCount] = []

    class Config:
        from_attributes = True

class PostOut(BaseModel):
    id: int
    author_id: int
    author_name: Optional[str] = None
    content: str
    image_path: Optional[str] = None
    created_at: datetime
    reactions: List[ReactionCount] = []
    comments: List[CommentOut] = []

    class Config:
        from_attributes = True

# --- AI support chat (F4) ---

class AiChatRequest(BaseModel):
    room_user_id: int
    message: str

class AiChatResponse(BaseModel):
    reply: str
