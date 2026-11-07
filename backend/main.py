import json
import os
import uuid

import httpx
from fastapi import FastAPI, HTTPException
from pydantic import BaseModel, Field

app = FastAPI(title="FoodLens AI")


MAX_IMAGE_BASE64_CHARS = 8_000_000  # ~6 МБ JPEG


class AnalyzeRequest(BaseModel):
    image_base64: str = Field(min_length=1, max_length=MAX_IMAGE_BASE64_CHARS)


SCHEMA = {
    "type": "object",
    "additionalProperties": False,
    "properties": {
        "dish": {"type": "string"},
        "estimatedGrams": {"type": "number"},
        "caloriesPer100g": {"type": "number"},
        "protein": {"type": "number"},
        "carbs": {"type": "number"},
        "fat": {"type": "number"},
        "fiber": {"type": "number"},
        "confidence": {"type": "number"},
        "ingredients": {
            "type": "array",
            "items": {
                "type": "object",
                "additionalProperties": False,
                "properties": {
                    "id": {"type": "string"}, "name": {"type": "string"},
                    "grams": {"type": "number"}, "calories": {"type": "number"},
                    "protein": {"type": "number"}, "carbs": {"type": "number"},
                    "fat": {"type": "number"}, "fiber": {"type": "number"},
                },
                "required": ["id", "name", "grams", "calories", "protein", "carbs", "fat", "fiber"],
            },
        },
    },
    "required": ["dish", "estimatedGrams", "caloriesPer100g", "protein", "carbs", "fat", "fiber", "confidence", "ingredients"],
}


@app.get("/health")
def health():
    return {"status": "ok"}


@app.post("/analyze")
async def analyze(body: AnalyzeRequest):
    key = os.getenv("OPENAI_API_KEY")
    if not key:
        raise HTTPException(503, "OPENAI_API_KEY is not configured")
    payload = {
        "model": os.getenv("OPENAI_MODEL", "gpt-5.4-mini"),
        "input": [{
            "role": "user",
            "content": [
                {"type": "input_text", "text": "Analyze this meal. Identify visible ingredients and estimate the whole portion's calories and macros. Return Ukrainian dish and ingredient names. Estimates must be plausible; confidence must be 0..1."},
                {"type": "input_image", "image_url": f"data:image/jpeg;base64,{body.image_base64}", "detail": "high"},
            ],
        }],
        "text": {"format": {"type": "json_schema", "name": "food_analysis", "strict": True, "schema": SCHEMA}},
    }
    try:
        async with httpx.AsyncClient(timeout=60) as client:
            response = await client.post("https://api.openai.com/v1/responses", headers={"Authorization": f"Bearer {key}"}, json=payload)
    except httpx.HTTPError as error:
        raise HTTPException(504, f"Upstream request failed: {type(error).__name__}") from error
    if response.is_error:
        # Не передаємо клієнту сирий текст помилки постачальника.
        raise HTTPException(502, f"Upstream error {response.status_code}")
    result = response.json()
    for item in result.get("output", []):
        for content in item.get("content", []):
            if content.get("type") == "refusal":
                raise HTTPException(422, "Model refused to analyze this image")
            if content.get("type") == "output_text":
                try:
                    parsed = json.loads(content["text"])
                except (KeyError, json.JSONDecodeError) as error:
                    raise HTTPException(502, "Model returned invalid JSON") from error
                for ingredient in parsed.get("ingredients", []):
                    ingredient["id"] = str(uuid.uuid4())
                return parsed
    raise HTTPException(502, "Model returned no structured output")
