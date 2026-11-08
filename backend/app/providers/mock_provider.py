"""Deterministic provider for local development and tests (AI_PROVIDER=mock). Makes no network calls."""

from __future__ import annotations

from ..schemas import (
    IngredientEstimate,
    MealAnalysisOutput,
    Recipe,
    RecipeIngredient,
    RecipeRequest,
    RecipeSuggestions,
)


class MockProvider:
    name = "mock"

    async def analyze_meal(self, jpeg_base64: str) -> MealAnalysisOutput:
        return MealAnalysisOutput(
            dish="Гречка з куркою",
            estimatedGrams=350,
            caloriesPer100g=143,
            protein=38,
            carbs=52,
            fat=13,
            fiber=6,
            confidence=0.8,
            ingredients=[
                IngredientEstimate(name="гречка", grams=200, calories=220, protein=8, carbs=42, fat=2, fiber=5),
                IngredientEstimate(name="куряче філе", grams=150, calories=280, protein=30, carbs=10, fat=11, fiber=1),
            ],
        )

    async def suggest_recipes(self, request: RecipeRequest) -> RecipeSuggestions:
        meal_type = request.mealType or "lunch"
        return RecipeSuggestions(
            message=f"До кінця дня залишилось {request.caloriesLeft} ккал.",
            recipes=[
                Recipe(
                    title=f"Страва з: {request.pantry[0]}",
                    mealType=meal_type,
                    minutes=20,
                    ingredients=[RecipeIngredient(name=request.pantry[0], grams=150, calories=200)],
                    steps=["Підготуйте продукти.", "Приготуйте 15 хвилин."],
                    calories=200,
                    protein=15,
                    carbs=20,
                    fat=6,
                )
            ],
            shoppingList=["зелень"],
        )

    async def aclose(self) -> None:
        return None
