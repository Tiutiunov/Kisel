# Privacy / Конфиденциальность

*English first, Russian below. / Сначала по-английски, ниже по-русски.*

Kisel is a desktop program that runs on your computer. It has no accounts, no server of its own, no analytics and no telemetry. Its authors receive nothing from it.

## What stays on your computer

- Settings: a file in your user profile.
- Secrets (for example a GitHub token): the system's own store, Windows Credential Manager or KWallet. Never in a settings file.
- What Claude Code tells Kisel through its hooks and mods (the state of a session, its last line, permission requests, limits): kept in memory and in Kisel's data folder, and sent nowhere.

## When Kisel reaches the network

Only for the features below. Each can be switched off in Settings or simply not used.

| Feature | Where to | What is sent |
| --- | --- | --- |
| Update check | api.github.com | A request for the list of releases. No identifiers. |
| GitHub view | api.github.com | Your own token, to read your repositories and pull requests. |
| Luka's connection reading | 1.1.1.1 (Cloudflare) | A ping. |
| Luka's speed test | speed.cloudflare.com | Test data, when you start the test. |
| Chat with an API key saved in an older version | api.anthropic.com | Your message and your key. Newer versions talk to your local Claude Code session instead. |

These services see your IP address, as any site you visit does, and handle it under their own policies.

## Discord

Off unless you switch it on. When on, Kisel talks only to the Discord program running on your computer, over Discord's local channel. It sends one of three fixed lines ("Working with Claude Code", "Claude is waiting for an answer", "With Claude Code, taking a break"), the time it started, and the name of the session only if you switch that on as well. Discord then shows it in your profile under its own privacy policy. Nothing you or Claude wrote is sent. Kisel does not sign in to Discord and reads nothing from it.

## Contact

Questions and requests: open an issue at https://github.com/Tiutiunov/Kisel/issues

---

Kisel — программа, которая работает на твоём компьютере. У неё нет аккаунтов, своего сервера, аналитики и телеметрии. Авторы ничего от неё не получают.

## Что остаётся на компьютере

- Настройки: файл в профиле пользователя.
- Секреты (например, токен GitHub): системное хранилище, Windows Credential Manager или KWallet. В файле настроек их нет.
- То, что Claude Code сообщает Kisel через хуки и моды (состояние сессии, её последняя строка, запросы разрешений, лимиты): хранится в памяти и в папке данных Kisel и никуда не отправляется.

## Когда Kisel выходит в сеть

Только для перечисленного ниже. Каждую функцию можно выключить в настройках или просто не пользоваться ею.

| Функция | Куда | Что отправляется |
| --- | --- | --- |
| Проверка обновлений | api.github.com | Запрос списка релизов. Без идентификаторов. |
| Экран GitHub | api.github.com | Твой собственный токен, чтобы прочитать твои репозитории и пулл-реквесты. |
| Показания связи у Луки | 1.1.1.1 (Cloudflare) | Пинг. |
| Замер скорости у Луки | speed.cloudflare.com | Тестовые данные, когда ты запускаешь замер. |
| Чат с API-ключом, сохранённым в старой версии | api.anthropic.com | Твоё сообщение и твой ключ. Новые версии вместо этого говорят с локальной сессией Claude Code. |

Эти сервисы видят твой IP-адрес, как любой сайт, и обращаются с ним по своим правилам.

## Discord

Выключено, пока не включишь. Когда включено, Kisel общается только с программой Discord на твоём компьютере, по её локальному каналу. Он отправляет одну из трёх готовых строк («Работает с Claude Code», «Claude ждёт ответа», «С Claude Code, перерыв»), время начала и название сессии, только если ты включил и это. Дальше Discord показывает это в твоём профиле по своей политике конфиденциальности. Ничего из написанного тобой или Claude не отправляется. Kisel не входит в Discord и ничего из него не читает.

## Связь

Вопросы и просьбы: создай issue на https://github.com/Tiutiunov/Kisel/issues
