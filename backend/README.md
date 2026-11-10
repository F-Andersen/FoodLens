# FoodLens API

Сервер для iOS-застосунку FoodLens. Він аналізує фото страв і підбирає рецепти через AI. Провайдер обирається змінною `AI_PROVIDER`: `anthropic` (Claude, за замовчуванням), `openai`, `gemini` або `mock` (для розробки, без мережевих запитів).

API-ключі зберігаються лише на сервері. Застосунок отримує анонімний токен пристрою, а квоти діють окремо для кожного встановлення.

## Структура

```text
backend/
├── app/
│   ├── main.py              # FastAPI: маршрути, помилки, ліміти
│   ├── config.py            # Налаштування зі змінних середовища
│   ├── auth.py              # HMAC-токени пристроїв
│   ├── ratelimit.py         # Ліміти запитів (у пам'яті)
│   ├── schemas.py           # Pydantic-моделі та JSON Schema для AI
│   └── providers/           # anthropic, openai, gemini, mock + спільні промпти
├── tests/                   # pytest
├── Dockerfile
├── docker-compose.yml       # API + Caddy (HTTPS)
├── Caddyfile
└── .env.example
```

## API

Усі помилки повертаються у форматі `{"error": {"code": "...", "message": "..."}}`. Поле `message` написане українською й готове для показу користувачу. Відповіді з кодом 429 і 503 містять заголовок `Retry-After`.

| Метод | Шлях | Авторизація | Опис |
| --- | --- | --- | --- |
| GET | `/health` | — | Перевірка, що сервер працює |
| POST | `/v1/auth/register` | — | `{"installId": "<uuid>"}` → `{"token", "expiresAt"}`. Ліміт на IP |
| POST | `/v1/analyze` | Bearer | `{"image_base64": "<jpeg>"}` → оцінка страви з інгредієнтами |
| POST | `/v1/recipes` | Bearer | Продукти й залишок норми → рецепти та список покупок |

`/v1/recipes` приймає таке тіло запиту:

```json
{"pantry": ["курка", "гречка"], "mealType": "lunch", "caloriesLeft": 900,
 "proteinLeft": 60, "diet": "balanced", "avoid": ["горіхи"]}
```

`mealType` може бути `breakfast`, `lunch`, `dinner`, `snack` або `null` (увесь день). `diet` може бути `balanced`, `highProtein` або `vegetarian`.

Коди помилок:

| Код | Що означає |
| --- | --- |
| 400 | Некоректний запит, base64 або не JPEG |
| 401 | Немає токена, токен неправильний або прострочений. Застосунок реєструється заново автоматично |
| 413 | Фото більше за `MAX_IMAGE_BYTES` |
| 422 | Модель відмовилась обробляти запит |
| 429 | Вичерпано ліміт |
| 502 | AI повернув некоректну відповідь або сервер неправильно налаштований |
| 503 | AI тимчасово недоступний |

## Безпека

- **Токени пристроїв.** Вони підписані HMAC-SHA256 і живуть `TOKEN_TTL_DAYS` днів. Якщо змінити `AUTH_SECRET`, усі токени одразу стануть недійсними.
- **Ліміти:**
  - аналіз фото: `ANALYZE_PER_HOUR` на годину й `ANALYZE_PER_DAY` на добу для кожного встановлення;
  - рецепти: `RECIPES_PER_HOUR` на годину;
  - реєстрація: `REGISTER_PER_HOUR_PER_IP` з одного IP.
- **Розмір запиту.** Caddy відхиляє тіло запиту понад 5 МБ, а API перевіряє заголовок `Content-Length` і розмір декодованого JPEG.
- **IP клієнта.** Береться останній запис `X-Forwarded-For`, який додає Caddy. Підставлені клієнтом попередні записи ігноруються.
- **Контейнер.** Працює від звичайного користувача з файловою системою лише для читання. Документація `/docs` вимкнена.
- **Приватність.** Фото не зберігаються й не записуються в логи.

Ліміти зберігаються в пам'яті одного процесу. Цього достатньо для одного VPS. Якщо запустити кілька копій сервера, лічильники треба перенести в Redis.

## Локальний запуск

Потрібен Python 3.10+ (у Docker використовується 3.12).

```bash
cd backend
python3.12 -m venv .venv && source .venv/bin/activate
pip install -r requirements-dev.txt
python -m pytest
AI_PROVIDER=mock AUTH_SECRET=$(openssl rand -hex 32) \
  uvicorn app.main:app_factory --factory --reload --port 8000
```

Те саме в Docker, без локального Python:

```bash
docker build -t foodlens-api backend
docker run --rm -p 8000:8000 -e AI_PROVIDER=mock -e AUTH_SECRET=$(openssl rand -hex 32) foodlens-api
```

Щоб застосунок на симуляторі звертався до локального сервера, у налаштуваннях вкажіть адресу `http://localhost:8000`. Для iPhone потрібен HTTPS, тобто розгорнутий сервер.

## Розгортання на VPS

Підійде будь-який VPS з Ubuntu 24.04, 1 vCPU та 1 ГБ RAM (наприклад, Hetzner CX22 або DigitalOcean Basic).

1. **DNS.** Створіть A-запис (і AAAA, якщо є IPv6), наприклад `api.foodlens.example`, що вказує на IP сервера.
2. **Docker і firewall:**
   ```bash
   curl -fsSL https://get.docker.com | sh
   ufw allow OpenSSH && ufw allow 80,443/tcp && ufw allow 443/udp && ufw enable
   ```
3. **Код і налаштування:**
   ```bash
   git clone https://github.com/F-Andersen/FoodLens.git && cd FoodLens/backend
   cp .env.example .env
   ```
   У файлі `.env` вкажіть:
   - `DOMAIN`;
   - `AUTH_SECRET` (згенеруйте командою `openssl rand -hex 32`);
   - `AI_PROVIDER`;
   - `ANTHROPIC_API_KEY`, `OPENAI_API_KEY` або `GEMINI_API_KEY`.
4. **Запуск.** Caddy сам отримає сертифікат Let's Encrypt:
   ```bash
   docker compose up -d --build
   curl https://api.foodlens.example/health
   ```
5. **Оновлення:**
   ```bash
   git pull && docker compose up -d --build
   ```
6. **Логи:**
   ```bash
   docker compose logs -f api
   ```

Щоб змінити провайдера, змініть `AI_PROVIDER` у `.env` і виконайте `docker compose up -d`.

Після розгортання вкажіть адресу сервера в `AppConfig.defaultAPIBaseURL` у застосунку. Тоді користувачам не доведеться нічого налаштовувати.

## Моделі

- **Anthropic.** За замовчуванням `claude-opus-5-5` із `effort: medium` і відповіддю за JSON Schema. Увімкнено серверний fallback (`fallbacks: "default"`): якщо модель відмовляє через спрацювання фільтрів безпеки, API сам повторює запит на рекомендованій моделі. Модель можна змінити через `ANTHROPIC_MODEL`.
- **OpenAI.** Responses API зі строгою JSON Schema. Модель задається через `OPENAI_MODEL`.
- **Gemini.** Interactions API з JSON Schema та `store: false`. Модель задається через `GEMINI_MODEL`, за замовчуванням `gemini-3.8-flash`. Ключ створюється в Google AI Studio. На безкоштовному рівні Google може використовувати запити для покращення своїх продуктів, а ліміти невеликі, тому для реальних користувачів потрібен платний ключ.

Відповідь моделі завжди перевіряється Pydantic: від'ємні значення обнуляються, `confidence` обмежується діапазоном 0–1.
