from pydantic import BaseModel, Field
from typing import List, Optional, Dict
from datetime import datetime

class LearningMode(str):
    STANDARD = "Standard"
    REMEDIAL = "Remedial"

class QuizResult(BaseModel):
    chapter_id: str
    score: float
    timestamp: datetime = Field(default_factory=datetime.now)

class UserProfile(BaseModel):
    uid: str
    email: str
    name: Optional[str] = None # Renamed from display_name per spec
    learning_mode: str = LearningMode.STANDARD
    quiz_history: List[QuizResult] = []

class LoginRequest(BaseModel):
    uid: str
    email: str
    name: Optional[str] = None

class ChatMessage(BaseModel):
    role: str # "user" or "model" or "system"
    content: str

class ChatRequest(BaseModel):
    uid: str
    message: str
    current_chapter_name: Optional[str] = None # Renamed/Added per spec
    history: List[ChatMessage] = []

class QuizGenerationRequest(BaseModel):
    uid: str
    chapter_name: str

class QuizSubmissionRequest(BaseModel):
    uid: str
    score_percent: float

class ModeUpdateRequest(BaseModel):
    uid: str
    mode: str
