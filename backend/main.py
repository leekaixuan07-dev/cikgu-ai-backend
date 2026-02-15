from fastapi import FastAPI, HTTPException, BackgroundTasks, Request
from fastapi.middleware.cors import CORSMiddleware
import uvicorn
import firebase_admin
from firebase_admin import credentials, firestore
import google.generativeai as genai
import os
import requests
from pypdf import PdfReader
from io import BytesIO
from .models import *
from typing import List, Dict
import logging
from dotenv import load_dotenv
import re
import json

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

load_dotenv()
logger.info(f"DEBUG: CWD is {os.getcwd()}")
key_status = bool(os.environ.get('GOOGLE_API_KEY'))
logger.info(f"DEBUG: GOOGLE_API_KEY present in env: {key_status}")

def convert_gdrive_url(url: str) -> str:
    """Converts a Google Drive view/open URL to a direct download URL."""
    file_id_match = re.search(r'/d/([a-zA-Z0-9_-]+)', url)
    if file_id_match:
        file_id = file_id_match.group(1)
        return f'https://drive.google.com/uc?export=download&id={file_id}'
    return url

app = FastAPI(title="CikguAI Backend")

# 1. Environment & Setup
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Configuration
SERVICE_ACCOUNT_KEY = "backend/serviceAccountKey.json"
GEMINI_API_KEY = os.environ.get("GOOGLE_API_KEY") 

LOCAL_PDF_PATH = "server_textbook.pdf"
TEXTBOOK_CONTENT = {} # Cache for RAG: {page_num: text} 
db = None
model = None 
# ...

# ...

# 2. Core Functions Implementation
# A. Startup & RAG Initialization
import asyncio

PDF_LOADING_STATUS = "pending"

async def load_pdf_background():
    global TEXTBOOK_CONTENT, PDF_LOADING_STATUS
    PDF_LOADING_STATUS = "loading"
    try:
        # Re-verify DB connection inside task if needed, or rely on global 'db'
        if not db:
             logger.error("DB not initialized in background task")
             PDF_LOADING_STATUS = "failed_no_db"
             return

        doc_ref = db.collection("content").document("textbook_v1")
        doc = doc_ref.get()
        if doc.exists:
            data = doc.to_dict()
            pdf_url = data.get("pdf_drive_link")
            
            if not os.path.exists(LOCAL_PDF_PATH) and pdf_url:
                download_url = convert_gdrive_url(pdf_url)
                logger.info(f"Downloading PDF from {download_url}...")
                response = await asyncio.to_thread(requests.get, download_url)
                if response.status_code == 200:
                    with open(LOCAL_PDF_PATH, "wb") as f:
                        f.write(response.content)
                    logger.info("PDF Downloaded.")
                else:
                    logger.error(f"Failed to download PDF: {response.status_code}")
                    PDF_LOADING_STATUS = "failed_download"
                    return
            
            if os.path.exists(LOCAL_PDF_PATH):
                logger.info("Extracting text from PDF...")
                def extract_text():
                    reader = PdfReader(LOCAL_PDF_PATH)
                    content = {}
                    for i, page in enumerate(reader.pages):
                        text = page.extract_text()
                        if text:
                            content[i + 1] = text
                    return content

                TEXTBOOK_CONTENT = await asyncio.to_thread(extract_text)
                logger.info(f"Extracted {len(TEXTBOOK_CONTENT)} pages.")
                PDF_LOADING_STATUS = "completed"
        else:
            logger.warning("textbook_v1 document not found in Firestore.")
            PDF_LOADING_STATUS = "not_found"
    except Exception as e:
        logger.error(f"Background PDF Sync Failed: {e}")
        PDF_LOADING_STATUS = f"failed_error: {str(e)}"

@app.on_event("startup")
async def startup_event():
    global db, model, TEXTBOOK_CONTENT
    
    # Init Firebase
    try:
        if not firebase_admin._apps:
            firebase_creds = os.environ.get("FIREBASE_CREDENTIALS")
            if firebase_creds:
                cred_dict = json.loads(firebase_creds)
                cred = credentials.Certificate(cred_dict)
                firebase_admin.initialize_app(cred)
                logger.info("Firebase Initialized with Environment Variable Credentials")
            elif os.path.exists(SERVICE_ACCOUNT_KEY):
                cred = credentials.Certificate(SERVICE_ACCOUNT_KEY)
                firebase_admin.initialize_app(cred)
                logger.info("Firebase Initialized with File Credentials")
            else:
                logger.warning("serviceAccountKey.json not found and FIREBASE_CREDENTIALS not set. Using default creds (Application Default Credentials).")
                firebase_admin.initialize_app()
        db = firestore.client()
        logger.info("Firebase Initialized")
    except Exception as e:
        logger.error(f"Firebase Init Failed: {e}")

    # Init Gemini
    logger.info(f"Initializing Gemini with Key: {GEMINI_API_KEY[:5]}... if present")
    if GEMINI_API_KEY:
        try:
            genai.configure(api_key=GEMINI_API_KEY)
            model = genai.GenerativeModel('gemini-2.0-flash-lite')
            logger.info("Gemini Initialized Successfully (Lite Model)")
        except Exception as e:
             logger.error(f"Gemini Init Failed: {e}")
    else:
        logger.warning("GOOGLE_API_KEY not set.")

    # Start PDF loading in background
    asyncio.create_task(load_pdf_background())

# B. Adaptive Logic
def get_system_prompt(uid: str) -> str:
    """
    Fetches user's learning mode and returns appropriate system prompt.
    """
    try:
        if db:
            user_ref = db.collection("users").document(uid)
            doc = user_ref.get()
            if doc.exists:
                mode = doc.to_dict().get("learning_mode", LearningMode.STANDARD)
            else:
                mode = LearningMode.STANDARD
        else:
            mode = LearningMode.STANDARD
    except:
        mode = LearningMode.STANDARD

    if mode == LearningMode.REMEDIAL:
        return (
            "You are a friendly senior student ('Abang'). The user is confused. "
            "Explain using Manglish (Malaysian English). Use analogies involving Nasi Lemak, "
            "Mamak stalls, Football, or KL Traffic. Example: 'Imagine gravity is like when you rush for free food...'"
        )
    else:
        return (
            "You are CikguAI. Explain concepts formally and strictly based on the syllabus. "
            "Be encouraging but academic. "
            "DEFAULT LANGUAGE: Bahasa Melayu. Only use English if the user asks in English."
        )

def get_relevant_context(query: str, chapter_name: Optional[str] = None) -> str:
    """
    Simple RAG: Find pages containing keywords from query.
    If chapter_name provided, could filter by chapter range (requires mapping).
    For now, full text search.
    """
    relevant_text = []
    # Split query into keywords
    # Allow short keywords if they are numbers or subtopics (e.g. "2.1")
    keywords = [k.lower() for k in query.split() if len(k) > 3 or any(char.isdigit() for char in k)]
    
    hits = []
    
    # Simple Chapter Mapping (In real app, fetch from DB)
    chapter_starts = {}
    # Scan content for chapter titles to build dynamic map if not available
    # Or just use the default fallback if DB invalid
    default_chapters = {
         "Bab 1: Warisan Negara Bangsa": 1,
         "Bab 2: Kebangkitan Nasionalisme": 22,
         "Bab 3: Konflik Dunia": 50 # Approximate
    }
    
    target_page = 0
    if chapter_name:
        # Try to find start page from default map or DB
        for title, start_page in default_chapters.items():
            if title in chapter_name or chapter_name in title:
                target_page = start_page
                break
    
    for page_num, text in TEXTBOOK_CONTENT.items():
        score = sum(text.lower().count(k) for k in keywords)
        
        # Boost if page is within likely chapter range
        if target_page > 0 and bucket_page(page_num, target_page):
             score += 5 # Boost chapter pages
             
        # Boost if page contains chapter title explicitly
        if chapter_name and chapter_name.lower() in text.lower():
             score += 10
             
        if score > 0:
            hits.append((score, page_num, text))
    
    # Sort by score desc
    hits.sort(key=lambda x: x[0], reverse=True)
    
    # Take top 3 pages
    top_hits = hits[:3]
    return "\n---\n".join([f"Page {h[1]}: {h[2]}" for h in top_hits])

def bucket_page(page, start):
    # Assume chapter length ~20 pages
    return start <= page < start + 20

# 3. API Endpoints Specification

@app.get("/")
def home():
    return {"status": "CikguAI Backend Running"}

@app.post("/auth/login")
def auth_login(request: LoginRequest):
    if not db:
        raise HTTPException(status_code=503, detail="Database unavailable")
    
    user_ref = db.collection("users").document(request.uid)
    doc = user_ref.get()
    
    if not doc.exists:
        data = {
            "uid": request.uid,
            "email": request.email,
            "name": request.name,
            "learning_mode": LearningMode.STANDARD,
            "quiz_history": []
        }
        user_ref.set(data)
        return {"status": "success", "message": "User created"}
    else:
        # Update login info if needed
        return {"status": "success", "message": "User exists"}

from fastapi.staticfiles import StaticFiles

# Mount static files to serve the PDF
app.mount("/static", StaticFiles(directory="."), name="static")

@app.get("/chapters")
def get_chapters(request: Request):
    if not db:
        raise HTTPException(status_code=503, detail="Database unavailable")
    
    # Construct local URL for PDF
    base_url = str(request.base_url).rstrip("/")
    # In production (Render), this will be the https URL
    # locally, http://localhost:8000
    pdf_link = f"{base_url}/static/{LOCAL_PDF_PATH}"

    doc = db.collection("content").document("textbook_v1").get()
    if doc.exists:
        data = doc.to_dict()
        return {
            "chapters": data.get("chapters", {}),
            "pdf_drive_link": pdf_link # Return local static link instead of GDrive
        }
    else:
        # Return fallback/demo data if DB empty
        return {
            "chapters": {
                "Bab 1: Warisan Negara Bangsa": 1,
                "Bab 2: Kebangkitan Nasionalisme": 22
            },
            "pdf_drive_link": pdf_link
        }

@app.post("/chat")
def chat(request: ChatRequest):
    if not model:
        raise HTTPException(status_code=503, detail="AI Model unavailable")
    
    # 1. Get Prompt
    system_prompt = get_system_prompt(request.uid)
    
    # 2. RAG
    context_text = get_relevant_context(request.message, request.current_chapter_name)
    
    # 3. Generate
    history_text = ""
    for msg in request.history:
        role_label = "USER" if msg.role == "user" else "CIKGU"
        history_text += f"{role_label}: {msg.content}\n"

    full_prompt = f"""
    SYSTEM: {system_prompt}
    SUBJECT: Sejarah Tingkatan 4 (KSSM)
    
    CURRENT CHAPTER: {request.current_chapter_name}
    IMPORTANT: You are an expert tutor for this specific chapter. 
    1. EXPLAIN ONLY what is in the provided context for this chapter.
    2. IF the user asks about the chapter title, USE THE EXACT TITLE provided above ({request.current_chapter_name}).
    3. SUBCONTEXT: If the text provided is insufficient, acknowledge it, but do NOT invent a different chapter title.
    
    CONTEXT FROM TEXTBOOK:
    {context_text}
    
    CHAT HISTORY:
    {history_text}
    
    USER QUESTION: {request.message}
    """
    
    try:
        response = model.generate_content(full_prompt)
        # Determine mode used for frontend display
        mode = "Remedial" if "Abang" in system_prompt else "Standard"
        return {"response": response.text, "mode_used": mode}
    except Exception as e:
        error_msg = str(e)
        logger.error(f"Chat Error: {error_msg}")
        if "429" in error_msg or "Quota" in error_msg:
             raise HTTPException(status_code=429, detail="Quota Exceeded. Please wait a moment.")
        raise HTTPException(status_code=500, detail=error_msg)

@app.post("/quiz/generate")
def quiz_generate(request: QuizGenerationRequest):
    if not model:
        raise HTTPException(status_code=503, detail="AI Model unavailable")

    # Fetch context for chapter - Simplified: Search strictly for "Chapter X" or keywords in chapter name
    # In a real app, rely on the Chapter Page Mapping to get exact text range.
    # For now, searching keywords from chapter name.
    context_text = get_relevant_context(request.chapter_name)
    
    prompt = f"""
    SUBJECT: Sejarah Tingkatan 4 (KSSM)
    Generate 3 Multiple Choice Questions (MCQ) based on this text:
    "{context_text[:2000]}..." 
    
    Target Audience: Malaysian Form 4 Students.
    Return ONLY valid JSON array:
    [
        {{"question": "...", "options": ["A", "B", "C", "D"], "answer": "A"}},
        ...
    ]
    Do not add markdown formatting like ```json.
    """
    
    try:
        response = model.generate_content(prompt)
        cleaned_text = response.text.replace("```json", "").replace("```", "").strip()
        import json
        questions = json.loads(cleaned_text)
        return {"questions": questions}
    except Exception as e:
        print(f"Quiz Gen Error: {e}")
        # Fallback
        return {
            "questions": [
                {"question": "Example Question?", "options": ["A", "B", "C", "D"], "answer": "A"}
            ]
        }

@app.post("/quiz/submit")
def quiz_submit(request: QuizSubmissionRequest):
    if not db:
        raise HTTPException(status_code=503, detail="Database unavailable")
    
    user_ref = db.collection("users").document(request.uid)
    
    # 1. Update History
    new_record = {
        "score": request.score_percent,
        "timestamp": firestore.SERVER_TIMESTAMP
    }
    # Using array_union or standard update
    user_ref.update({
        "quiz_history": firestore.ArrayUnion([new_record])
    })
    
    # 2. Adaptation Rule
    new_mode = None
    if request.score_percent < 50:
        new_mode = LearningMode.REMEDIAL
    elif request.score_percent >= 80:
        new_mode = LearningMode.STANDARD
    
    if new_mode:
        user_ref.update({"learning_mode": new_mode})
        return {"new_mode": new_mode}
    
    # No change
    doc = user_ref.get()
    current_mode = doc.to_dict().get("learning_mode", "Standard")
    return {"new_mode": current_mode}

if __name__ == "__main__":
    uvicorn.run("backend.main:app", host="0.0.0.0", port=8000, reload=True)
