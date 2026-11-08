"""Request/response models and the JSON Schemas the AI providers must follow.

Field names are camelCase because the iOS app decodes them directly.
"""

from __future__ import annotations

import uuid
from typing import Literal

from pydantic import BaseModel, ConfigDict, Field, field_validator

MealType = Literal["breakfast", "lunch", "dinner", "snack"]
Diet = Literal["balanced", "highProtein", "vegetarian"]


# ---------- Meal analysis ----------

class IngredientEstimate(BaseModel):
    """One visible component of the meal, as estimated by the model."""

    model_config = ConfigDict(extra="ignore")

    name: str = Field(min_length=1, max_length=80)
    grams: float
    calories: float
    protein: float
    carbs: float
    fat: float
    fiber: float

    @field_validator("grams", "calories", "protein", "carbs", "fat", "fiber")
    @classmethod
    def _non_negative(cls, value: float) -> float:
        return max(0.0, float(value))


class MealAnalysisOutput(BaseModel):
    """What a provider returns for a photo, validated before it reaches the app."""

    model_config = ConfigDict(extra="ignore")

    dish: str = Field(min_length=1, max_length=120)
    estimatedGrams: float
    caloriesPer100g: float
    protein: float
    carbs: float
    fat: float
    fiber: float
    confidence: float
    ingredients: list[IngredientEstimate] = Field(max_length=20)

    @field_validator("estimatedGrams", "caloriesPer100g", "protein", "carbs", "fat", "fiber")
    @classmethod
    def _non_negative(cls, value: float) -> float:
        return max(0.0, float(value))

    @field_validator("confidence")
    @classmethod
    def _unit_interval(cls, value: float) -> float:
        return min(1.0, max(0.0, float(value)))


class Ingredient(IngredientEstimate):
    id: str


class MealAnalysisResponse(MealAnalysisOutput):
    ingredients: list[Ingredient]

    @classmethod
    def from_output(cls, output: MealAnalysisOutput) -> "MealAnalysisResponse":
        data = output.model_dump()
        data["ingredients"] = [{**item, "id": str(uuid.uuid4())} for item in data["ingredients"]]
        return cls.model_validate(data)


class AnalyzeRequest(BaseModel):
    # Base64 of a JPEG without a data: prefix. The exact byte limit is checked after decoding.
    image_base64: str = Field(min_length=16, max_length=6_000_000)


# ---------- Recipes ----------

class RecipeRequest(BaseModel):
    pantry: list[str] = Field(min_length=1, max_length=50)
    mealType: MealType | None = None
    caloriesLeft: int = Field(ge=0, le=6000)
    proteinLeft: int = Field(ge=0, le=400)
    diet: Diet = "balanced"
    avoid: list[str] = Field(default_factory=list, max_length=20)

    @field_validator("pantry", "avoid")
    @classmethod
    def _clean_items(cls, items: list[str]) -> list[str]:
        cleaned = [item.strip()[:60] for item in items if item and item.strip()]
        return list(dict.fromkeys(cleaned))  # de-duplicate, keep order


class RecipeIngredient(BaseModel):
    model_config = ConfigDict(extra="ignore")

    name: str = Field(min_length=1, max_length=80)
    grams: int
    calories: int

    @field_validator("grams", "calories", mode="before")
    @classmethod
    def _round_non_negative(cls, value: float) -> int:
        return max(0, round(float(value)))


class Recipe(BaseModel):
    model_config = ConfigDict(extra="ignore")

    title: str = Field(min_length=1, max_length=120)
    mealType: MealType
    minutes: int
    ingredients: list[RecipeIngredient] = Field(min_length=1, max_length=20)
    steps: list[str] = Field(min_length=1, max_length=12)
    calories: int
    protein: int
    carbs: int
    fat: int

    @field_validator("minutes", "calories", "protein", "carbs", "fat", mode="before")
    @classmethod
    def _round_non_negative(cls, value: float) -> int:
        return max(0, round(float(value)))


class RecipeSuggestions(BaseModel):
    model_config = ConfigDict(extra="ignore")

    message: str = Field(max_length=600)
    recipes: list[Recipe] = Field(min_length=1, max_length=5)
    shoppingList: list[str] = Field(max_length=30)


# ---------- Auth ----------

class RegisterRequest(BaseModel):
    installId: uuid.UUID


class TokenResponse(BaseModel):
    token: str
    expiresAt: int


# ---------- JSON Schemas for structured output ----------
# Both providers require: every property listed in "required" and additionalProperties false.

_NUMBER = {"type": "number"}

_INGREDIENT_SCHEMA = {
    "type": "object",
    "additionalProperties": False,
    "properties": {
        "name": {"type": "string"},
        "grams": _NUMBER, "calories": _NUMBER, "protein": _NUMBER,
        "carbs": _NUMBER, "fat": _NUMBER, "fiber": _NUMBER,
    },
    "required": ["name", "grams", "calories", "protein", "carbs", "fat", "fiber"],
}

MEAL_ANALYSIS_SCHEMA = {
    "type": "object",
    "additionalProperties": False,
    "properties": {
        "dish": {"type": "string"},
        "estimatedGrams": _NUMBER,
        "caloriesPer100g": _NUMBER,
        "protein": _NUMBER, "carbs": _NUMBER, "fat": _NUMBER, "fiber": _NUMBER,
        "confidence": _NUMBER,
        "ingredients": {"type": "array", "items": _INGREDIENT_SCHEMA},
    },
    "required": ["dish", "estimatedGrams", "caloriesPer100g", "protein", "carbs", "fat", "fiber",
                 "confidence", "ingredients"],
}

_RECIPE_SCHEMA = {
    "type": "object",
    "additionalProperties": False,
    "properties": {
        "title": {"type": "string"},
        "mealType": {"type": "string", "enum": ["breakfast", "lunch", "dinner", "snack"]},
        "minutes": {"type": "integer"},
        "ingredients": {
            "type": "array",
            "items": {
                "type": "object",
                "additionalProperties": False,
                "properties": {"name": {"type": "string"}, "grams": {"type": "integer"}, "calories": {"type": "integer"}},
                "required": ["name", "grams", "calories"],
            },
        },
        "steps": {"type": "array", "items": {"type": "string"}},
        "calories": {"type": "integer"},
        "protein": {"type": "integer"},
        "carbs": {"type": "integer"},
        "fat": {"type": "integer"},
    },
    "required": ["title", "mealType", "minutes", "ingredients", "steps", "calories", "protein", "carbs", "fat"],
}

RECIPE_SUGGESTIONS_SCHEMA = {
    "type": "object",
    "additionalProperties": False,
    "properties": {
        "message": {"type": "string"},
        "recipes": {"type": "array", "items": _RECIPE_SCHEMA},
        "shoppingList": {"type": "array", "items": {"type": "string"}},
    },
    "required": ["message", "recipes", "shoppingList"],
}
