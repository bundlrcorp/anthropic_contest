import asyncio
import uuid
from typing import Optional

from controllers import EpisodeController
from fastapi import APIRouter, Depends, Query, Body, Request
from sqlalchemy import select
from sqlalchemy.orm import Session

from database import get_db
from es import ESManager
from models import User
from schemas import EpisodeOut, EpisodeTranscriptionOut, \
    EpisodeTimestampedTranscriptionOut, TranscriptionStatus, \
    TimestampTopicPrompt
from sse_starlette.sse import EventSourceResponse
from utils import get_es_manager
from async_database import sessionmanager
from dependencies.async_user import get_async_user

from models import Episode

router = APIRouter()


@router.get("/{id}/ai-prompt-timestamps-with-topics",
            response_model=Optional[TimestampTopicPrompt]
            )
def get_episode_ai_prompt_topics_with_timestamps(
        id: str,
        deep_link: bool = Query(default=False),
        db: Session = Depends(get_db),
        user: User = Depends(get_async_user)):
    """
    Retrieves json containing transcription with segments.
    """
    return EpisodeController.get_ai_prompt_topics_with_timestamps(db, user, id, deep_link)
