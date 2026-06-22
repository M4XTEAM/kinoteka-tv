# Кинотека TV (iOS, sideload)

Нативное iOS-приложение: ищешь тайтл → **«Смотреть на Apple TV»** → поток Alloha
извлекается **на устройстве** (твой резидентный IP → нет гео-блока) → выбор
озвучки/качества → играешь и жмёшь **AirPlay** на Apple TV.

Почему нативно (а не PWA): только нативный `WKWebView` может инжектить скрипт во
**все фреймы** (`forMainFrameOnly: false`) и перехватить ответ `/bnsi` внутри
cross-origin iframe Alloha. Веб-страница так не может (CORS/sandbox).

## Архитектура
- **TMDB** — поиск по названию → `imdb_id` (ключ зашит в `TMDB.swift`).
- **AllohaExtractor** — скрытый (alpha 0.02, полноразмерный) `WKWebView` грузит
  `fbphdplay.top` → Alloha-embed внутри iframe; JS-хук на XHR/fetch ловит ответ
  `/bnsi/movies|serials/{id}` (плеер сам считает анти-бот `borth`). Сериалы: сезон/серия
  кладём в URL embed и дублируем выбором в `seasonType1/episodeType1`.
- **Плеер** — `AVPlayerViewController` (нативные контролы + кнопка AirPlay). Поток идёт
  через HF-прокси `MNQE-alloha-extract.hf.space/api?url=…`, который инжектит Referer/UA
  (Apple TV свои заголовки на AirPlay не шлёт; VK CDN отдаёт US-IP HF — проверено).

## Сборка IPA в облаке (Mac не нужен)
1. Создай **новый отдельный** GitHub-репозиторий (НЕ клади сюда основной проект Кинотеки —
   там секреты). Запушь **содержимое папки `ios-app/`** в КОРЕНЬ репозитория, чтобы было:
   ```
   <repo>/.github/workflows/build.yml
   <repo>/project.yml
   <repo>/KinotekaTV/*.swift
   ```
2. GitHub → вкладка **Actions** → workflow `build-ipa` запустится сам (или Run workflow).
3. По завершении скачай артефакт **KinotekaTV-unsigned-ipa** (это `KinotekaTV-unsigned.ipa`).

## Установка на iPhone (sideload, без Mac)
- **SideStore** (рекоменд., работает без постоянного Mac) или **AltStore**:
  - Установи SideStore/AltStore на iPhone (через их инструкцию + anisette).
  - В приложении: **+** → выбери `KinotekaTV-unsigned.ipa` → оно подпишется твоим Apple ID.
  - **Бесплатный** Apple ID: сертификат живёт 7 дней → SideStore/AltStore авто-обновляет
    по WiFi; раз в неделю держи их открытыми. **Платный** ($99/год): год без возни.
- Альтернатива с Mac: открыть в Xcode (после `xcodegen generate`) и запустить на устройстве.

## Ограничения v1
- Источник — **Alloha** (1080p H.264). ylitron (4K) — позже, у него закрыт lookup imdb→plid.
- Извлечение ~6–25 c (плеер должен реально стартануть в скрытом webview).
- HF-прокси нужен только для AirPlay-совместимости; держи Space живым (или замени на свой).
- Это первая версия — если CI выдаст ошибки компиляции, пришли лог, поправлю.

## Локальная генерация проекта (если есть Mac)
```
brew install xcodegen
xcodegen generate
open KinotekaTV.xcodeproj
```
