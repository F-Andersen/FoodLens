"""Prompts shared by every provider, so both models get the same task."""

from __future__ import annotations

from ..schemas import RecipeRequest

MEAL_SYSTEM = (
    "You are a nutrition analyst for FoodLens, a calorie-tracking app used mainly in Ukraine. "
    "You estimate what is on a plate from a single photo. "
    "Most meals are Ukrainian home cooking, so when a food could be several things, prefer the common Ukrainian reading. "
    "Write every dish and ingredient name in Ukrainian."
)

MEAL_INSTRUCTIONS = """Analyse the meal in this photo.

- Identify each visible component and estimate its weight in grams from the plate, cutlery and typical portion sizes. For food in a glass, bowl or jar, judge by the container's size and how full it is.
- For each component give calories, protein, carbs, fat and fiber for that estimated weight.
- `estimatedGrams` is the whole portion; `protein`, `carbs`, `fat`, `fiber` are totals for the whole portion; `caloriesPer100g` is the whole portion's energy density.
- Account for visible oil, sauces and dressings — they are the most common source of underestimation.
- `confidence` (0–1) reflects how sure you are about the dish and the portion, not just the label. Use below 0.4 for unclear photos.
- If the photo contains no food, return dish "Не їжа", zero values, confidence 0 and an empty ingredient list.

Ukrainian foods that are easy to misread in a photo:
- Холодець: meat broth set into clear or cloudy jelly, often with carrot, garlic or shredded meat, in a bowl, glass or mould. It is not a drink, and not fish aspic unless fish is visible.
- Сало, смалець, намазка із сала: white or pinkish fat, sliced or spread on rye bread, about 700–850 kcal per 100 g. These are more common than fish spreads; choose форшмак only when fish is clearly visible.
- Картопляне пюре: smooth or lumpy mash, pale to yellow when made with butter, egg or yellow potatoes. It is more common than кулеша or пшоняна каша, which look grainy.
- Шкварки and засмажка: browned pork pieces and fried onion served on top of potato, вареники or каша. Count the fat they were fried in.
- Also common: борщ, зелений борщ, вареники, деруни, голубці, котлети, гречка, сирники, оселедець, бутерброди на житньому хлібі."""

def meal_instructions(hint: str | None = None) -> str:
    """The analysis task, plus the user's correction when they have said what the meal really is."""
    if not hint:
        return MEAL_INSTRUCTIONS
    return MEAL_INSTRUCTIONS + f"""

The user has corrected what this meal is. Treat their description as correct for the dish and its components,
even if it differs from what the photo suggests, and use the photo only to estimate portion sizes.
Use the user's dish name if they gave one.
<user_correction>
{hint}
</user_correction>"""


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
