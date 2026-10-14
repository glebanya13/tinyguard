# Firebase (онлайн-рекорды и облачное сохранение)

Онлайн-часть необязательна: без файла `firebase.cfg` игра полностью офлайн, кнопка
«Рекорды» на карте скрыта. Подключение — через REST API Firebase из GDScript
(`scripts/online.gd`, autoload `Online`), без нативных плагинов.

## Что отправляется

| Данные | Где | Когда |
|---|---|---|
| Анонимный id (Firebase Auth) | Authentication | при первом онлайн-действии |
| Имя (до 16 символов) и рекорд волн осады | `leaderboards/level_<id>/scores/<uid>` | новый рекорд бесконечной осады |
| Файл прогресса (звёзды, улучшения, рекорды, настройки) | `saves/<uid>` | кнопка «В облако» |

Ни почты, ни рекламы, ни аналитики. Для Google Play в анкете Data safety: «идентификатор
устройства или другой ID» (анонимный id) и «игровой прогресс», без передачи третьим лицам.

## Создание проекта (один раз, ~10 минут)

1. <https://console.firebase.google.com> → **Add project** → имя `tinyguard` →
   Google Analytics можно выключить.
2. **Build → Authentication → Get started → Sign-in method → Anonymous → Enable**.
3. **Build → Firestore Database → Create database** → регион (например `europe-west`)
   → **Production mode**.
4. Правила: вкладка **Rules** → вставить содержимое `firestore.rules` → **Publish**.
   Или из корня репозитория:
   ```bash
   npm i -g firebase-tools && firebase login
   firebase use --add            # выбрать проект (создаст .firebaserc, он не коммитится)
   firebase deploy --only firestore:rules
   ```
5. **Project settings → General → Your apps → Web (`</>`)** → зарегистрировать
   приложение → из `firebaseConfig` взять `apiKey` и `projectId`.
6. Скопировать `firebase.example.cfg` в `firebase.cfg` и вписать их. Файл не
   коммитится, но попадает в APK (`include_filter` в `export_presets.cfg`).

`apiKey` веб-приложения — это не секрет, а идентификатор проекта; доступ
ограничивают правила Firestore (каждый пишет только свои документы, рекорд только
растёт, размеры полей ограничены).

## Проверка

1. Запустить игру, пройти уровень, сыграть бесконечную осаду → при новом рекорде он
   уходит в таблицу. На карте → «Рекорды» → топ-10 выбранного уровня.
2. «В облако» / «Из облака» — копия прогресса; «Из облака» заменяет локальный.
3. В консоли Firestore видны `leaderboards/level_N/scores/*` и `saves/*`.

Тесты без сети: `tests/test_online.gd` (разбор ответов, восстановление прогресса).
