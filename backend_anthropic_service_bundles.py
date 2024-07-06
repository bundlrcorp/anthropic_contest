import json
import os
import traceback
from typing import List

from datetime import datetime
from anthropic import Anthropic
from sqlalchemy import select, desc, func
from sqlalchemy.orm import Session
from models import BundleCategory, KnowledgeObject, Summary, \
    KnowledgeObjectSummary, KnowledgeObjectBundleCategory, DailyDose
from schemas import KnowledgeObjectType, SummaryJson, DailyDoseOut

SYSTEM_PROMPT_FULL_SUMMARY = "You are an assistant news reporter for question-answering tasks. " \
                             "All of the context provided comes from the content provided below " \
                             "so each response should be based on what is provided. " \
                             "Context comprises list of documents which have " \
                             "UUID, TYPE (episode, email or article), TITLE and CONTENT. " \
                             "\n\n" \
                             "Context:"

USER_PROMPT_FULL_SUMMARY = "As a professional summarizer, create a brief " \
                           "summary of the provided text below, while adhering to these " \
                           "guidelines:\n" \
                           "- First provide one short engaging sentence on the overall " \
                           "content. Use news narration style. Make this an intro for " \
                           "one liners below. Refer to this content as OVERALL_SUMMARY\n" \
                           "- Second, look across all of the documents. Determine if there are " \
                           "any common stories, that is, " \
                           "the same story in more than one document, " \
                           "and if so, pick the main two or three and create summaries " \
                           "with only 2-5 words in each, highlighting the main topic discussed. " \
                           "Refer to this content as TRENDING_STORIES.\n" \
                           "- Next, provide a list of one liner summaries for each provided " \
                           "document.\n" \
                           "- Each one liner summary should have text, uuid and type.\n" \
                           "- Your response should use the essential information, " \
                           "eliminating extraneous language and focusing on critical aspects.\n" \
                           "- Rely strictly on the provided text, without including " \
                           "external information.\n" \
                           "Provide your answer in the following JSON format " \
                           "(make sure the answer is JSON serializable):\n" \
                           "{\n" \
                           "\"summary\": \"OVERALL_SUMMARY\",\n" \
                           "\"trending_stories\": [{\"text\": \"TRENDING_STORY_TEXT\"}," \
                           " {\"text\": \"TRENDING_STORY_TEXT\"}],\n" \
                           "\"one_liners\": [{\"text\": \"ONE_LINER_TEXT\", " \
                           "\"uuid\": UUID, \"type\": TYPE}," \
                           " {\"text\": \"ONE_LINER_TEXT\", \"uuid\": UUID, \"type\": TYPE}]\n" \
                           "}"

RETRY_FULL_SUMMARY_PROMPT = "The answer you have provided is not JSON serializable.\n" \
                            "Provide your answer in the following JSON format " \
                            "(make sure the answer is JSON serializable):\n" \
                            "{\n" \
                            "\"summary\": \"OVERALL_SUMMARY\",\n" \
                            "\"trending_stories\": [{\"text\": \"TRENDING_STORY_TEXT\"}," \
                           " {\"text\": \"TRENDING_STORY_TEXT\"}],\n" \
                            "\"one_liners\": [{\"text\": \"ONE_LINER_TEXT\", " \
                            "\"uuid\": UUID, \"type\": TYPE}," \
                            " {\"text\": \"ONE_LINER_TEXT\", \"uuid\": UUID, \"type\": TYPE}]\n" \
                            "}"

SYSTEM_PROMPT_PER_KO = "You are an assistant for question-answering tasks." \
                       "All of the context provided comes from the content provided" \
                       " below so each response should be based on what is provided.\n\n" \
                       "Context:"

SHORT_PODCAST_SUMMARY_PROMPT = "As a professional summarizer, create a brief summary" \
                               " of the provided text below, while adhering " \
                               "to these guidelines:\n" \
                               "- Provide summary in 4-5 bullets.\n" \
                               "- Your response should use the essential information, " \
                               "eliminating extraneous language and focusing on " \
                               "critical aspects.\n" \
                               "- Rely strictly on the provided text, " \
                               "without including external information."

SHORT_NL_SUMMARY_PROMPT = "As a professional summarizer, create a brief summary " \
                          "of the provided text below, while adhering to these guidelines:\n" \
                          "- Provide summary in 4-5 bullets\n" \
                          "- Your response should use the essential information, " \
                          "eliminating extraneous language and focusing on critical aspects.\n" \
                          "- Rely strictly on the provided text, without " \
                          "including external information."

ONE_LINER_SUMMARY_PROMPT = "As a professional summarizer, create a brief summary" \
                           " of the provided text below, while adhering " \
                           "to these guidelines:\n" \
                           "- Provide summary in one engaging sentence.\n" \
                           "- Provide only the answer. Don't explain what the answer is.\n" \
                           "- Use news narration style.\n" \
                           "- Your response should use the essential information, " \
                           "eliminating extraneous language and focusing on " \
                           "critical aspects.\n" \
                           "- Rely strictly on the provided text, " \
                           "without including external information."

TS_WITHOUT_ONELIN_PROMPT = "As a professional summarizer, create a brief summary" \
                           " of the provided text below, while adhering " \
                           "to these guidelines:\n" \
                           "- First provide summary in one engaging sentence. " \
                           "Provide only the answer. Don't explain what the answer is. " \
                           "Refer to this content as OVERALL_SUMMARY.\n" \
                           "- Second, look across all of the documents. Determine if there are " \
                           "any common stories, that is, " \
                           "the same story in more than one document, " \
                           "and if so, pick the main two or three and create summaries " \
                           "with only 2-5 words in each, highlighting the main topic discussed. " \
                           "Refer to this content as TRENDING_STORIES.\n" \
                           "- Use news narration style.\n" \
                           "- Your response should use the essential information, " \
                           "eliminating extraneous language and focusing on " \
                           "critical aspects.\n" \
                           "- Rely strictly on the provided text, " \
                           "without including external information.\n" \
                           "Provide your answer in the following JSON format " \
                           "(make sure the answer is JSON serializable):\n" \
                           "{\n" \
                           "\"summary\": \"OVERALL_SUMMARY\",\n" \
                           "\"trending_stories\": [{\"text\": \"TRENDING_STORY_TEXT\"}," \
                           " {\"text\": \"TRENDING_STORY_TEXT\"}]\n" \
                           "}"

ANTHROPIC_MODEL_NAME = "claude-3-haiku-20240307"
ANTHROPIC_MAX_TOKENS = 4096
ANTHROPIC_RETRY_MODEL_NAME = "claude-3-5-sonnet-20240620"


class AnthropicSummaryService:

    def __init__(self):
        self.client = Anthropic(
            api_key=os.getenv("ANTHROPIC_API_KEY")
        )

    def create_full_content_summary(self, db: Session,
                                    bundle_category: BundleCategory,
                                    select_from: datetime,
                                    timezones: List[str]):
        summarized_individual_kos = self.get_individually_summarized_kos(db,
                                                                         bundle_category,
                                                                         select_from)
        all_relevant_kos = self.get_kos(db,
                                        bundle_category,
                                        select_from)
        daily_dose = self.get_random_daily_dose(db)
        full_summary = list()

        if not summarized_individual_kos:
            return full_summary

        full_summary = self.get_full_summary(summarized_individual_kos)

        if not full_summary:
            full_summary = self.get_full_summary_based_on_one_liners(summarized_individual_kos)

        for fs in full_summary.one_liners:
            for ark in all_relevant_kos:
                if fs.uuid == str(ark.id) and fs.type == str(ark.ko_type.value):
                    parent = ark.parent
                    fs.parent = parent.name
                    fs.publisher = parent.parent.name if parent.parent else None
                    break
        if daily_dose:
            dd_out = DailyDoseOut(
                quote=daily_dose.quote,
                source=daily_dose.source,
                dd_type=daily_dose.dd_type
            )
            full_summary.daily_dose = dd_out
        stored_summaries = self.create_summary_for_bundle_category(db,
                                                                   bundle_category.id,
                                                                   full_summary,
                                                                   timezones,
                                                                   all_relevant_kos
                                                                   )
        if not stored_summaries:
            return list()
        return stored_summaries

    def get_full_summary(self, summarized_individual_kos):
        final_content = ''.join(
            [f"UUID: {sko.ko_id}\nTYPE: {sko.ko_type.value}\n"
             f"TITLE: {sko.name}\n"
             f"CONTENT: "
             f"{sko.summary_text if sko.summary_text else sko.summary_one_liner}\n\n"
             for sko in summarized_individual_kos])
        summary_verified = dict()
        try:
            message = self.client.messages.create(
                max_tokens=ANTHROPIC_MAX_TOKENS,
                system=f"{SYSTEM_PROMPT_FULL_SUMMARY}{final_content}",
                messages=[
                    {
                        "role": "user",
                        "content": USER_PROMPT_FULL_SUMMARY,
                    }
                ],
                model=ANTHROPIC_MODEL_NAME,
            )
            summary_text = message.to_dict().get('content')[0].get("text")
            try:
                summary = json.loads(summary_text)
                summary_verified = SummaryJson(**summary)
                for sv in summary_verified.one_liners:
                    exists = False
                    for sko in summarized_individual_kos:
                        if sv.uuid == str(sko.ko_id) and sv.type == str(sko.ko_type.value):
                            exists = True
                            break
                    if not exists:
                        raise Exception
            except Exception:
                traceback.print_exc()
                message = self.client.messages.create(
                    max_tokens=ANTHROPIC_MAX_TOKENS,
                    system=f"{SYSTEM_PROMPT_FULL_SUMMARY}{final_content}",
                    messages=[
                        {
                            "role": "user",
                            "content": USER_PROMPT_FULL_SUMMARY,
                        },
                        {
                            "role": "assistant",
                            "content": summary_text,
                        },
                        {
                            "role": "user",
                            "content": RETRY_FULL_SUMMARY_PROMPT,
                        },
                    ],
                    model=ANTHROPIC_RETRY_MODEL_NAME,
                )
                summary_text = message.to_dict().get('content')[0].get("text")
                try:
                    summary = json.loads(summary_text)
                    summary_verified = SummaryJson(**summary)
                    for sv in summary_verified.one_liners:
                        exists = False
                        for sko in summarized_individual_kos:
                            if sv.uuid == str(sko.ko_id) and sv.type == str(sko.ko_type.value):
                                exists = True
                                break
                        if not exists:
                            raise Exception
                except Exception:
                    traceback.print_exc()
        except Exception:
            traceback.print_exc()
        return summary_verified

    def get_full_summary_based_on_one_liners(self, summarized_individual_kos):
        final_content = ''.join(
            [f"UUID: {sko.ko_id}\nTYPE: {sko.ko_type.value}\n"
             f"TITLE: {sko.name}\n"
             f"CONTENT: "
             f"{sko.summary_text if sko.summary_text else sko.summary_one_liner}\n\n"
             for sko in summarized_individual_kos])
        summary_text = ""
        trending_stories = list()
        one_liners = [{"text": sko.summary_one_liner if sko.summary_one_liner else '',
                       "uuid": str(sko.ko_id),
                       "type": sko.ko_type.value} for sko in summarized_individual_kos]
        try:
            message = self.client.messages.create(
                max_tokens=ANTHROPIC_MAX_TOKENS,
                system=f"{SYSTEM_PROMPT_FULL_SUMMARY}{final_content}",
                messages=[
                    {
                        "role": "user",
                        "content": TS_WITHOUT_ONELIN_PROMPT,
                    }
                ],
                model=ANTHROPIC_RETRY_MODEL_NAME,
            )
            summary_text = message.to_dict().get('content')[0].get("text")
            summary = json.loads(summary_text)
            summary_verified = SummaryJson(
                summary=summary.get('summary', ''),
                trending_stories=summary.get('trending_stories', []),
                one_liners=one_liners
            )
        except Exception:
            traceback.print_exc()
            summary_verified = SummaryJson(
                summary=summary_text,
                one_liners=one_liners,
                trending_stories=trending_stories
            )
        return summary_verified

    def summarise_ko(self, db: Session, ko: KnowledgeObject, content: str):
        summary = self.get_ko_summary(db, ko)
        if not summary:
            summary_text = self._anthropic_summarise_individual_ko(ko, content)
            summary_one_liner = self._anthropic_summarise_individual_ko_as_one_line(ko, content)
            self.create_ko_summary(db, ko, summary_text, summary_one_liner)

    def _anthropic_summarise_individual_ko(self, ko: KnowledgeObject, text_to_summarise):
        summary_text = ""
        try:
            final_content = "Title: {}\nContent: {}\n".format(ko.title, text_to_summarise)
            message = self.client.messages.create(
                max_tokens=ANTHROPIC_MAX_TOKENS,
                system=f"{SYSTEM_PROMPT_PER_KO}{final_content}",
                messages=[
                    {
                        "role": "user",
                        "content": SHORT_PODCAST_SUMMARY_PROMPT if
                        ko.ko_type == KnowledgeObjectType.EPISODE
                        else SHORT_NL_SUMMARY_PROMPT,
                    }
                ],
                model=ANTHROPIC_MODEL_NAME,
            )
            summary_text = message.to_dict().get('content')[0].get("text")
        except Exception:
            traceback.print_exc()
        return summary_text

    def _anthropic_summarise_individual_ko_as_one_line(self,
                                                       ko: KnowledgeObject,
                                                       text_to_summarise):
        one_liner = ko.title
        try:
            final_content = "Title: {}\nContent: {}\n".format(ko.title, text_to_summarise)
            message = self.client.messages.create(
                max_tokens=ANTHROPIC_MAX_TOKENS,
                system=f"{SYSTEM_PROMPT_PER_KO}{final_content}",
                messages=[
                    {
                        "role": "user",
                        "content": ONE_LINER_SUMMARY_PROMPT
                    }
                ],
                model=ANTHROPIC_MODEL_NAME,
            )
            one_liner = message.to_dict().get('content')[0].get("text")
        except Exception:
            traceback.print_exc()
        return one_liner

    @staticmethod
    def get_ko_summary(db: Session, ko: KnowledgeObject):
        try:
            stmt = (select(KnowledgeObjectSummary)
                    .where(KnowledgeObjectSummary.ko_id == ko.id).limit(1))
            summary = db.execute(stmt).scalar()
            return summary
        except Exception:
            traceback.print_exc()

    @staticmethod
    def create_ko_summary(db: Session, ko: KnowledgeObject,
                          summary_text: str, summary_one_liner: str):
        try:
            ko_summary = KnowledgeObjectSummary(
                summary_text=summary_text,
                summary_one_liner=summary_one_liner,
                ko_id=ko.id,
                ko_type=ko.ko_type,
                name=ko.title
            )
            db.add(ko_summary)
            db.commit()
        except Exception:
            traceback.print_exc()

    @staticmethod
    def get_individually_summarized_kos(db: Session,
                                        bundle_category: BundleCategory,
                                        select_from: datetime):
        summary_query = (
            select(KnowledgeObjectSummary)
            .join(KnowledgeObjectBundleCategory,
                  KnowledgeObjectBundleCategory.knowledge_object_id == KnowledgeObjectSummary.ko_id)
            .join(KnowledgeObject,
                  KnowledgeObject.id == KnowledgeObjectSummary.ko_id)
            .where(
                KnowledgeObjectBundleCategory.bundle_category_id == bundle_category.id,
                KnowledgeObject.deleted.is_(False),
                KnowledgeObjectSummary.created_on >= select_from
            )
            .order_by(
                desc(KnowledgeObjectSummary.created_on)
            )
        )
        ko_summaries = db.execute(summary_query).scalars().all()
        return ko_summaries

    @staticmethod
    def get_kos(db: Session,
                bundle_category: BundleCategory,
                select_from: datetime):
        kos_query = (
            select(KnowledgeObject)
            .join(KnowledgeObjectBundleCategory,
                  KnowledgeObjectBundleCategory.knowledge_object_id == KnowledgeObject.id)
            .where(
                KnowledgeObjectBundleCategory.bundle_category_id == bundle_category.id,
                KnowledgeObject.deleted.is_(False),
                KnowledgeObject.created_on >= select_from
            )
            .order_by(
                desc(KnowledgeObject.created_on)
            )
        )
        kos = db.execute(kos_query).scalars().all()
        return list(kos)

    @staticmethod
    def get_random_daily_dose(db: Session):
        lookup_stmt = (select(DailyDose).order_by(func.random()).limit(1))
        daily_dose = db.execute(lookup_stmt).scalar_one_or_none()
        return daily_dose

    @staticmethod
    def create_summary_for_bundle_category(db: Session,
                                           bundle_category_id: str,
                                           summary_json: SummaryJson,
                                           timezones: List[str],
                                           kos: List[KnowledgeObject]
                                           ):
        bundle_summaries = list()
        try:
            for tz in timezones:
                bundle_summary = Summary(
                    summary_json=summary_json.dict(),
                    timezone=tz,
                    bundle_category_id=bundle_category_id,
                    knowledge_objects=kos,
                )
                bundle_summaries.append(bundle_summary)
            if bundle_summaries:
                db.add_all(bundle_summaries)
                db.commit()
                return bundle_summaries
            return bundle_summaries
        except Exception:
            traceback.print_exc()
            return bundle_summaries

    @staticmethod
    def create_empty_summary_for_bundle_category(db: Session,
                                                 bundle_category_id: str,
                                                 summary_json: dict,
                                                 timezones: List[str],
                                                 kos: List[KnowledgeObject]):
        try:
            bundle_summaries = list()
            for tz in timezones:
                bundle_summary = Summary(
                    summary_json=summary_json,
                    timezone=tz,
                    bundle_category_id=bundle_category_id,
                    knowledge_objects=kos,
                )
                bundle_summaries.append(bundle_summary)
            if bundle_summaries:
                db.add_all(bundle_summaries)
                db.commit()
        except Exception:
            traceback.print_exc()
