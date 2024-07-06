import hashlib
import os
import json
from typing import Optional

from fastapi import HTTPException
from sqlalchemy import select
from sqlalchemy.exc import SQLAlchemyError
from sqlalchemy.orm import Session
from controllers.ko_base import KOBaseController
from es import DocType, ESManager
from models import Episode, KnowledgeObject, User
from starlette import status

from .ml import MLController
from .google_storage_service import GoogleStorageService
from services.ko_authorizer import KOAuthorizerService
from services import KOSerializerService, KOFilterHiddenService, AnthropicSummaryService
from schemas import EpisodeTranscriptionOut, EpisodeTimestampedTranscriptionOut, \
    EpisodeOut, TranscriptionStatus, TimestampTopicPrompt


class EpisodeController(KOBaseController):
    KO_TYPE = Episode
    IDENTIFICATION_FIELDS = ['guid', 'link', 'title']
    REQUIRED_FIELDS = ['title', 'mp3_url', 'summary']

    @classmethod
    def create(cls, *args, **kwargs) -> Optional[KnowledgeObject]:
        episode = super().create(*args, **kwargs, doc_types=[DocType.KO])

        if episode is not None:
            mc = MLController()
            mc.transcribe_episode_initial(str(episode.id), episode.mp3_url)

        return episode

    @classmethod
    def _create_model(cls, db, data, parent) -> Episode:
        return Episode(
            guid=data.get('guid'),
            title=data.get('title'),
            link=data.get('link'),
            publication_date=data.get('publication_date'),
            mp3_url=data.get('mp3_url'),
            duration=data.get('duration'),
            duration_sw=data.get('duration_sw'),
            image=data.get('image'),
            itunes_type=data.get('itunes_type'),
            parent=parent,
            needs_authorization=data.get("needs_authorization", False)
        )

    @classmethod
    def _fetch_transcription(cls, ko: Episode) -> Optional[str]:
        gs = GoogleStorageService()
        remote_file_name = hashlib.sha256(ko.mp3_url.encode()).hexdigest()
        local_file_name = f'./{remote_file_name}'
        file_exists = gs.download_file(remote_file_name, local_file_name)
        transcription = None
        if file_exists:
            with open(local_file_name, 'r') as transcription_file:
                transcription = transcription_file.read()
        os.remove(local_file_name)
        return transcription

    @classmethod
    def _fetch_transcription_text_from_timestamps(cls, ko: Episode) -> Optional[str]:
        gs = GoogleStorageService()
        remote_file_name = "{}.json".format(hashlib.sha256(ko.mp3_url.encode()).hexdigest())
        local_file_name = f'./{remote_file_name}'
        file_exists = gs.download_file(remote_file_name, local_file_name)
        transcription = None
        if file_exists:
            with open(local_file_name, 'r') as transcription_file:
                segments = json.load(transcription_file)
                transcription = ''.join([item['text'] for item in segments['segments']])
        os.remove(local_file_name)
        return transcription

    @classmethod
    def _fetch_transcription_text_from_ko_id(cls, ko_id: str, db: Session) -> Optional[str]:
        ko_lookup_stmt = select(Episode).where(Episode.id == ko_id,
                                               Episode.deleted.is_(False))
        ko = db.execute(ko_lookup_stmt).scalar_one()
        gs = GoogleStorageService()
        remote_file_name = "{}.json".format(hashlib.sha256(ko.mp3_url.encode()).hexdigest())
        local_file_name = f'./{remote_file_name}'
        file_exists = gs.download_file(remote_file_name, local_file_name)
        transcription = None
        if file_exists:
            with open(local_file_name, 'r') as transcription_file:
                segments = json.load(transcription_file)
                transcription = ''.join([item['text'] for item in segments['segments']])
        os.remove(local_file_name)
        return transcription

    @classmethod
    def _fetch_timestamped_transcription(cls,
                                         ko: Episode
                                         ) -> Optional[EpisodeTimestampedTranscriptionOut]:
        gs = GoogleStorageService()
        remote_file_name = "{}.json".format(hashlib.sha256(ko.mp3_url.encode()).hexdigest())
        local_file_name = f'./{remote_file_name}'
        file_exists = gs.download_file(remote_file_name, local_file_name)
        transcription = None
        if file_exists:
            with open(local_file_name, 'r') as transcription_file:
                transcription = EpisodeTimestampedTranscriptionOut(**json.load(transcription_file),
                                                                   status=ko.transcription_status)
                try:
                    os.remove(local_file_name)
                except Exception:
                    pass
        return transcription

    @classmethod
    def update_segments(cls,
                        db: Session,
                        es_manager: ESManager,
                        ko: Episode):
        data = cls._fetch_transcription_text_from_timestamps(ko)
        if not data:
            return

        es_manager.delete_document(str(ko.id), DocType.SEGMENT)
        cls._create_es_docs(es_manager, ko, {"content": data}, doc_types=[DocType.SEGMENT])
        if ko.bundle_categories and ko.transcription_status == TranscriptionStatus.FULL:
            individual_summary_required = any(
                [bc.summary_required for bc in ko.bundle_categories])
            if individual_summary_required:
                a_ss = AnthropicSummaryService()
                a_ss.summarise_ko(db, ko, data)

    @classmethod
    def find_by_id(cls, db: Session, user: User, id: str, deep_link=False) -> Episode:
        try:
            ko_lookup_stmt = select(Episode).where(Episode.id == id,
                                                   Episode.deleted.is_(False))
            authorized_stmt = ko_lookup_stmt
            if not deep_link:
                authorized_stmt = KOAuthorizerService.authorize_sql(ko_lookup_stmt, user)
            filtered_stmt = KOFilterHiddenService.filter_sql(authorized_stmt, user)
            ko = db.execute(filtered_stmt).scalar_one()
            return ko
        except SQLAlchemyError:
            raise HTTPException(status_code=404)

    @classmethod
    def get_transcription(cls,
                          db: Session,
                          user: User,
                          id: str,
                          deep_link=False) -> EpisodeTranscriptionOut:
        ko = cls.find_by_id(db, user, id, deep_link)
        data = cls._fetch_transcription_text_from_timestamps(ko)
        if not data:
            data = "Transcription in progress"
        return EpisodeTranscriptionOut(text=data, status=ko.transcription_status)

    @classmethod
    def get_timestamped_transcription(cls,
                                      db: Session,
                                      user: User,
                                      id: str,
                                      deep_link=False
                                      ) -> Optional[EpisodeTimestampedTranscriptionOut]:
        ko = cls.find_by_id(db, user, id, deep_link)
        return cls._fetch_timestamped_transcription(ko)

    @classmethod
    def update_duration(cls,
                        id: str,
                        duration: float,
                        db: Session,
                        es_manager: ESManager,
                        user: User) -> EpisodeOut:
        ko = cls.find_by_id(db, user, id)
        if duration < 0:
            raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST,
                                detail="Duration can't be negative number.")
        try:
            setattr(ko, 'duration_sw', duration)
            db.add(ko)
            db.commit()
            return KOSerializerService.serialize(es_manager=es_manager,
                                                 relational_kos=[ko],
                                                 db=db,
                                                 user=user)[0]
        except Exception:
            raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST,
                                detail="Failed to update episode duration.")

    @classmethod
    def initialize_full_transcription(cls,
                                      episode_id: str,
                                      db: Session,
                                      user: User,
                                      deep_link=False):
        episode = cls.find_by_id(db, user, episode_id, deep_link)
        if episode.transcription_status == TranscriptionStatus.INITIAL:
            episode.transcription_status = TranscriptionStatus.PARTIAL

            mc = MLController()
            if mc.transcribe_episode_full(str(episode.id), episode.mp3_url):
                db.add(episode)
                db.commit()
            return
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST,
                            detail="Failed to initialize full transcription.")

    @classmethod
    def get_ai_prompt_topics_with_timestamps(cls,
                                             db: Session,
                                             user: User,
                                             id: str,
                                             deep_link=False
                                             ) -> Optional[TimestampTopicPrompt]:
        model_name = "claude-3-5-sonnet-20240620"
        max_tokens = 4096
        temperature = 0.4
        system_prompt = "You're an expert who helps people understand precisely what topics " \
                        "are being discussed in a document. " \
                        "The document is a transcript from a podcast. " \
                        "The podcast is {0:.2f}s long. " \
                        "ALWAYS MAKE SURE TO EXTRACT & DESCRIBE TOPICS " \
                        "COVERING THE WHOLE DOCUMENT. " \
                        "Here is the document: "
        user_prompt = "List ALL the topics discussed in this document in bullet form. " \
                      "Here are important rules for creating the list of topics: " \
                      "1. Make sure to LIST ONLY THE MAIN TOPICS DISCUSSED. " \
                      "2. The total word count of the entire output " \
                      "should be approximately 300 words. " \
                      "3. Once you have identified the topics, it is VERY important " \
                      "to PRECISELY identify WHEN these topics were primarily being discussed." \
                      " Here are some important rules for assessing " \
                      "WHEN a topic starts being discussed:" \
                      " 3.1. Read back over the text segments to " \
                      "look for when the topic was PRIMARILY discussed." \
                      " 3.2. You should use the segment timestamp information. " \
                      "3.3.  Specifically, assess which segment represents the " \
                      "BEGINNING of the primary discussion of the topic you identified. " \
                      "3.4 Show the timestamp of that segment as the " \
                      "start time of the topic description. " \
                      "3.5. Be VERY METHODICAL and PRECISE when applying " \
                      "the relevant segment timestamp. " \
                      "4. Describe each topic in a short sentence or a few words. " \
                      "5. Before listing topics always say: Here is a list " \
                      "of main topics discussed in the podcast. " \
                      "6. Here is an example of the output: (543.23s) Topic XXX was discussed"
        ttp = None
        ko = cls.find_by_id(db, user, id, deep_link)
        gs = GoogleStorageService()
        remote_file_name = "{}.json".format(hashlib.sha256(ko.mp3_url.encode()).hexdigest())
        local_file_name = f'./{remote_file_name}'
        file_exists = gs.download_file(remote_file_name, local_file_name)
        if file_exists:
            with open(local_file_name, 'r') as transcription_file:
                segment_res = json.load(transcription_file)
                data = [{"start": item['start'],
                         "end": item['end'],
                         "text": item['text']} for item in segment_res['segments']]

                transcription_text_list = ["{0:.2f}s: ".format(d['start']) + d['text'].strip()
                                           for d in data]
                transcription_text = ' '.join(transcription_text_list)
                system_prompt = system_prompt.format(data[-1]['end'])
                ttp = TimestampTopicPrompt(model_name=model_name,
                                           system_prompt=system_prompt + transcription_text,
                                           max_tokens=max_tokens,
                                           temperature=temperature,
                                           user_prompt=user_prompt)
        return ttp
