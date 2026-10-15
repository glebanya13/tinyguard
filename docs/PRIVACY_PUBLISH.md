# Публикация политики конфиденциальности

Google Play и приложение требуют **публичный https-URL** политики. Сейчас
`GameInfo.PRIVACY_URL` пуст, поэтому `python3 tools/validate_project.py` выводит
`WARNING: PRIVACY_URL ...` (не ошибка, но блокер релиза). **URL здесь не указан намеренно —
его нужно получить после публикации.**

## Перед публикацией

1. В `docs/PRIVACY.md` заменить все `TODO` (дата редакции, контактный e-mail владельца).
2. Сверить таблицу данных с реальным поведением (`docs/FIREBASE.md`, `docs/ACCOUNTS.md`,
   если есть): если появились новые поля — обновить политику.

## GitHub Pages (проще всего)

1. Репозиторий → Settings → Pages → Source: *Deploy from a branch*, ветка `main`
   (или `gh-pages`), папка `/docs`. Репозиторий должен быть публичным
   (на бесплатном плане Pages для приватных репозиториев недоступны).
2. Через 1–2 минуты страница появится по адресу вида
   `https://<владелец>.github.io/<репозиторий>/PRIVACY` (Jekyll отрисует `PRIVACY.md`
   как HTML; `.md` в конце не нужен). Открыть адрес в браузере без входа в аккаунт и убедиться.
3. Вписать проверенный адрес в `const PRIVACY_URL` в `scripts/game_info.gd`
   (https, без пробелов) и в карточку приложения в Google Play Console.
4. `python3 tools/validate_project.py` — предупреждение должно исчезнуть.

Альтернатива: любой статический хостинг или Firebase Hosting (`firebase deploy --only hosting`
с каталогом, содержащим HTML-версию политики).

## Готовый сайт (`website/`)

Статический сайт с политикой, страницей удаления аккаунта, поддержкой, условиями и контактами готов
(EN основной, RU под `/ru/`), см. `website/README.md`. Он публикует тексты из `docs/PRIVACY.md` и
`docs/ACCOUNTS.md` как обычные HTML-страницы (без JavaScript для чтения), без сторонних запросов.

1. Заполнить `website/src/config/site.ts`: `contacts.email`, `privacy.operatorName`, `siteUrl`, при желании
   `playUrl`; после проверки текста поставить `privacy.reviewed = true`.
2. `cd website && npm install && SITE_BASE=/<репозиторий>/ npm run build` (или `/` для своего домена),
   залить `website/dist/` на GitHub Pages / Cloudflare Pages / Netlify.
3. Открыть `https://<хост>/privacy/` и `https://<хост>/delete-account/` без входа в аккаунт и вписать
   проверенные адреса в `GameInfo.PRIVACY_URL`, `GameInfo.DELETION_URL` и в Play Console.
