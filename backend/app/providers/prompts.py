"""Prompts shared by every provider, so both models get the same task."""

from __future__ import annotations

from ..schemas import RecipeRequest

MEAL_SYSTEM = (
    "You are a nutrition analyst for FoodLens, a Ukrainian calorie-tracking app. "
    "You estimate what is on a plate from a single photo. "
    "Write every dish and ingredient name in Ukrainian."
)

MEAL_INSTRUCTIONS = """Analyse the meal in this photo.

- Identify each visible component and estimate its weight in grams from the plate, cutlery and typical portion sizes.
- For each component give calories, protein, carbs, fat and fiber for that estimated weight.
- `estimatedGrams` is the whole portion; `protein`, `carbs`, `fat`, `fiber` are totals for the whole portion; `caloriesPer100g` is the whole portion's energy density.
- Account for visible oil, sauces and dressings — they are the most common source of underestimation.
- `confidence` (0–1) reflects how sure you are about the dish and the portion, not just the label. Use below 0.4 for unclear photos.
- If the photo contains no food, return dish "Не їжа", zero values, confidence 0 and an empty ingredient list."""

RECIPES_SYSTEM = (
    "You are a practical home-cooking assistant for FoodLens, a Ukrainian nutrition app. "
    "You suggest simple, realistic recipes that a person can cook today with what they already have. "
    "Write everything in Ukrainian."
)

_MEAL_TYPE_UK = {"breakfast": "сніданок", "lunch": "обід", "dinner": "вечерю", "snack": "перекус"}
_DIET_UK = {
    "balanced": "збалансований раціон",
    "highProtein": "раціон з підвищеним вмістом білка",
    "vegetarian": "вегетаріанський раціон (без м'яса та риби)",
}


def recipes_prompt(request: RecipeRequest) -> str:
    meal = (f"Suggest 3 recipes for {_MEAL_TYPE_UK[request.mealType]}."
            if request.mealType else "Suggest 4 recipes covering the rest of the day (different meal types).")
    avoid = ", ".join(request.avoid) if request.avoid else "немає"
    pantry = ", ".join(request.pantry)
    return f"""{meal}

Products at home: {pantry}
Diet: {_DIET_UK[request.diet]}
Never use (allergies or dislikes): {avoid}
Calories left today: {request.caloriesLeft} kcal. Protein left today: {request.proteinLeft} g.

Rules:
- Build each recipe mainly from the products at home; basic staples (salt, pepper, oil, water) are assumed available.
- Keep each recipe within the remaining calories when possible; prefer protein-rich options if protein left is above 30 g.
- Ingredient weights are for one serving; calories, protein, carbs and fat are totals for that serving.
- 3–7 short, concrete steps per recipe.
- `shoppingList` lists only products the recipes need that are not at home (no staples).
- `message` is one or two friendly sentences of advice about the rest of the day."""
