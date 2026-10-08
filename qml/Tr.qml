// The interface's two languages. The copy is written in English where it is used, as
// `Tr.t("...")`; the Russian for it is looked up here by the English text. A phrase with
// no entry stays English, so a new string is never a broken one.
//
//   Tr.t(s)  a fixed phrase written in the QML
//   Tr.d(s)  a phrase that comes from elsewhere at run time (the hub's "Edit invoice.ts",
//            an error from GitHub): a known whole phrase, or a known beginning with the
//            rest left as it is
//
// Which language: Settings, "Language" (Prefs.language: en | ru). It is English unless
// Russian has been picked there, whatever the system's own language.
pragma Singleton
import QtQuick
import Kisel.Core

QtObject {
    readonly property string lang: Prefs.language === "ru" ? "ru" : "en"
    readonly property bool russian: lang === "ru"

    function t(s) {
        if (!russian) return s
        const v = ru[s]
        return v === undefined ? s : v
    }
    function d(s) {
        if (!russian || !s) return s
        const v = ru[s]
        if (v !== undefined) return v
        for (const p of starts)
            if (s.startsWith(p[0])) return p[1] + s.substring(p[0].length)
        return s
    }

    // what the hub and the clients say, by how it begins
    readonly property var starts: [
        ["Run ", "Запуск: "], ["Edit ", "Правка: "], ["Read ", "Чтение: "], ["Search ", "Поиск: "], ["Allowed ", "Разрешено: "],
        ["GitHub answered ", "GitHub ответил "], ["Cannot read ", "Не удаётся прочитать "]
    ]

    readonly property var ru: ({
        // ---- states ----
        "Done": "Готово", "Working": "Работает", "Thinking": "Думает", "Needs you": "Ждёт тебя", "Failed": "Ошибка", "Idle": "Простой",
        "Listening": "Слушает", "Not connected": "Не подключён", "Waiting for you": "Ждёт тебя",
        "Question": "Вопрос", "Permission": "Разрешение", "Settings": "Настройки", "Session": "Сессия", "Sessions": "Сессии",
        "Mute sounds": "Выключить звуки", "Unmute sounds": "Включить звуки", "Move the bar": "Переместить таблетку", "Close": "Закрыть",

        // ---- Miku's Home ----
        "Claude Code is not connected yet. Shall we fix that?": "Claude Code ещё не подключён. Исправим?",
        "I cannot listen for hooks right now. Sorry!": "Сейчас не могу слушать хуки. Прости!",
        "Ready and listening. Start a session and I will watch it.": "Готова и слушаю. Начни сессию, а я присмотрю.",
        "Thinking it over. Give it a moment.": "Обдумывает. Дай минутку.",
        "Working on it. I will tell you when it is done.": "Работает. Скажу, когда закончит.",
        "Claude needs you. Have a look?": "Claude ждёт тебя. Глянешь?",
        "All done! Come and see.": "Всё готово! Иди посмотри.",
        "That one went wrong. Want to see why?": "Тут что-то пошло не так. Посмотрим почему?",
        "Nothing is running. I am right here.": "Ничего не запущено. Я тут.",
        "Repos": "Репо", "Chat": "Чат", "waiting for a session": "жду сессию", "not connected": "не подключён",
        "Connect Claude Code": "Подключить Claude Code", "Open session": "Открыть сессию", "Connect": "Подключить", "Open": "Открыть",

        // ---- permission and question ----
        "Allow": "Разрешить", "Always": "Всегда", "Deny": "Отклонить", "Send answer": "Отправить ответ",
        "Reply in terminal": "Ответить в терминале", "In terminal": "В терминале",
        "·  1 of": "·  1 из", "  ·  pick any": "  ·  можно несколько",

        // ---- session, chat, GitHub ----
        "No prompt yet": "Запроса пока нет", "Nothing changed yet": "Пока ничего не изменено",
        "Ask Claude anything": "Спроси Claude о чём угодно", " is listening": " слушает", "Message Claude": "Сообщение для Claude",
        "Stop": "Стоп", "Send": "Отправить", "Drop the file on me": "Брось файл на меня",
        "Add a GitHub token": "Добавь токен GitHub",
        "Settings → GitHub. A read-only personal access token is enough.": "Настройки → GitHub. Хватит личного токена только на чтение.",
        "open PRs": "открытых PR", "waiting for your review": "ждут твоего ревью", "Refresh": "Обновить", "Draft": "Черновик",
        "Passing": "Проходит", "Failing": "Падает", "Running": "Идёт", "No checks": "Без проверок", "No open pull requests": "Открытых пул-реквестов нет",
        "GitHub sent something unexpected": "GitHub прислал что-то непонятное", "GitHub refused the request": "GitHub отклонил запрос",
        "GitHub rejected the token": "GitHub не принял токен",
        "Can't read that file (text files up to 200 KB)": "Не могу прочитать файл (только текст до 200 КБ)",
        "That looks like a binary file": "Похоже, это не текстовый файл", "Add your Anthropic API key in Settings": "Добавь ключ Anthropic в настройках",
        "The request failed": "Запрос не удался",

        // ---- Zundamon's player ----
        "Nothing playing": "Ничего не играет", "Open Spotify and it shows up here": "Открой Spotify, и трек появится тут",
        "Previous track": "Предыдущий трек", "Pause": "Пауза", "Play": "Играть", "Next track": "Следующий трек",

        // ---- Teto's monitor ----
        "Memory": "Память", "RAM": "ОЗУ", "The last minute": "Последняя минута", "Clean memory": "Очистить память", "Clean": "Чистка",
        "Freed ": "Освободила ", " GB": " ГБ", "Already tidy": "И так чисто",
        "I cannot see this machine from here.": "Отсюда мне эту машину не видно.",
        "Sweeping the memory. Stand back.": "Подметаю память. Отойди.",
        " GB. You are welcome.": " ГБ. Не благодари.",
        "Nothing much to free. It was tidy already.": "Освобождать почти нечего. Тут и так было чисто.",
        "The memory is full. Close something, will you?": "Память забита. Закрой уже что-нибудь, а?",
        "The processor is flat out. What are you running?": "Процессор на пределе. Что ты там запустил?",
        "The graphics card is flat out. Playing, are we?": "Видеокарта на пределе. Играем, значит?",
        "Busy, but nothing I cannot handle.": "Нагрузка есть, но я справляюсь.",
        "A lot is open. Not that I am counting.": "Много всего открыто. Не то чтобы я считала.",
        "All quiet. Thanks to me, obviously.": "Всё тихо. Благодаря мне, разумеется.",

        // ---- Luka's connection ----
        "Ping": "Пинг", "Downloading": "Загрузка", "Down": "Приём", "Up": "Отдача",
        " MB/s": " МБ/с", " KB/s": " КБ/с", "0 KB/s": "0 КБ/с", " MB": " МБ", " KB": " КБ",
        "No connection": "Нет связи", "Back online": "Связь вернулась", "Downloaded ": "Скачано ",
        "I cannot see the connection from here.": "Отсюда мне связь не видно.",
        "The line is down. It will come back; they always do.": "Связи нет. Вернётся — она всегда возвращается.",
        "And we are back. No need to fuss.": "Вот и вернулась. Незачем было волноваться.",
        "Answers are coming late. Something is in the way.": "Ответы приходят с опозданием. Что-то мешает.",
        "Something is coming down: ": "Что-то качается: уже ", " so far. I am watching it.": ". Я присматриваю.",
        "That is the download done: ": "Загрузка закончена: пришло ", " came in.": ".",
        "A lot is coming in. Downloading something nice?": "Много всего приходит. Качаешь что-то хорошее?",
        "A lot is going out. Sharing, are we?": "Много всего уходит. Делимся, значит?",
        "A little slow, but steady.": "Медленновато, но ровно.",
        "A quiet line. Just the way I like it.": "Тихая линия. Как я люблю.",

        " Mbps": " Мбит/с", "Test": "Тест", "Testing": "Замер", "Download": "Приём", "Upload": "Отдача", "Down ": "Приём ", "Up ": "Отдача ",
        "Stop the test": "Остановить замер", "Test the speed": "Измерить скорость", "Last test: ": "Последний замер: ",
        "Finding the nearest server. One moment.": "Ищу ближайший сервер. Минутку.",
        "Measuring the way down: ": "Меряю приём: пока ", " so far.": ".", "Now the way up: ": "Теперь отдача: пока ",
        "The test did not go through. Try again in a while.": "Замер не удался. Попробуй чуть позже.",
        ", up ": ", отдача ", ", ping ": ", пинг ", " ms. ": " мс. ",
        "Nothing to complain about.": "Жаловаться не на что.", "Quite decent.": "Вполне прилично.", "I have seen faster.": "Видала и побыстрее.", "Oh dear. That is slow.": "Ох. Это очень медленно.",

        // ---- Rin's sign ----
        "New": "Новое", "Update": "Обновление",

        // ---- Settings ----
        "Connected": "Подключён", "Removed": "Убрано", "Couldn't write settings.json": "Не удалось записать settings.json",
        "Remove hooks": "Убрать хуки",
        "Needs repair": "Нужна починка", "Repair hooks": "Починить хуки", "settings.json is not valid JSON": "settings.json — не валидный JSON",
        "If hooks break": "Если хуки сломались", "Ask me": "Спросить", "Repair": "Чинить сама", "Do nothing": "Ничего",
        "Claude Code hooks need repair. Open Settings.": "Хуки Claude Code сломались. Открой настройки.",
        "Claude Code is not connected. Open Settings.": "Claude Code не подключён. Открой настройки.",
        "Claude Code hooks repaired": "Хуки Claude Code починены",
        "Hooks that were connected and went stale are repaired by themselves, with a dated backup. New hooks are never added without your click.": "Хуки, которые уже были подключены и устарели, чинятся сами, с резервной копией. Новые без твоего клика не добавляются.",
        "Kisel tells you when the hooks are missing or stale. The change is made only after you confirm it here.": "Kisel скажет, если хуков нет или они устарели. Менять файл он будет только после твоего подтверждения здесь.",
        "Kisel does not check the hooks.": "Kisel не проверяет хуки.", "Nothing to change in ": "Нечего менять в ",
        "This is the exact change to ": "Вот точное изменение в ", ". A backup is saved first as ": ". Сначала сохраняется копия: ",
        "Write change": "Записать", "Cancel": "Отмена", "Key saved in ": "Ключ сохранён: ", "Anthropic API key": "Ключ Anthropic API", "Save": "Сохранить",
        "Token saved in ": "Токен сохранён: ", "Personal access token (read-only)": "Личный токен (только чтение)", "Remove": "Убрать",
        "GitHub token removed": "Токен GitHub убран", "Screen": "Экран", ", Kisel is here": ", Kisel здесь", "Kisel moved to ": "Kisel переехал на ",
        "Follow primary": "За основным", "Following the primary monitor": "Следую за основным монитором",
        "Kisel follows your primary monitor (": "Kisel держится основного монитора (", "), also after a restart": "), и после перезапуска тоже",
        "Kisel stays on ": "Kisel остаётся на ", ", also after a restart": ", и после перезапуска тоже",
        "Character": "Персонаж", "Teto watches the computer": "Тето следит за компьютером", "Luka watches the connection": "Лука следит за связью",
        "Rin announces notifications": "Рин сообщает об уведомлениях", "Zundamon shows and steers Spotify": "Зундамон показывает Spotify и управляет им",
        "Look and sound": "Вид и звук", "Sounds": "Звуки", "Reduce motion": "Меньше движения",
        "Close at once when the pointer leaves": "Закрывать сразу, как уходит курсор", "Close ": "Закрывать через ", " s after the pointer leaves": " с после ухода курсора",
        "Place": "Место", "Top": "Сверху", "Bottom": "Снизу", "Left": "Слева", "Right": "Справа",
        "In the middle of the edge": "Посередине края", "Toward the top": "Ближе к верху", "Toward the bottom": "Ближе к низу",
        "Toward the left": "Ближе к левому краю", "Toward the right": "Ближе к правому краю",
        "Start when I sign in": "Запускать при входе в систему", "Stay clear of the taskbar": "Не заезжать на панель задач",
        "System": "Как в системе", "Dark": "Тёмная", "Light": "Светлая", "Language": "Язык",
        "Updates": "Обновления", "Asking GitHub...": "Спрашиваю GitHub...", " is the newest": " — новейшая версия", " is out (you have ": " уже вышла (у тебя ",
        "Downloading ": "Скачиваю ", "Installing. Kisel will be right back.": "Устанавливаю. Kisel сейчас вернётся.",
        "Check for updates": "Проверить обновления", "Update and restart": "Обновить и перезапустить",
        "Check for updates by itself": "Проверять обновления самому",
        "Always allowed": "Разрешено всегда", "Nothing yet. \"Always\" on a card adds a rule here.": "Пока пусто. «Всегда» на карточке добавляет правило сюда.",
        " rule": " правило", " rules": " правил", "Clear": "Очистить", "Rules cleared": "Правила очищены", "Quit Kisel": "Выйти из Kisel",
        "Saved": "Сохранено", "Couldn't reach ": "Не достучаться до ",
        "There is no Windows release yet": "Релиза для Windows пока нет",
        "GitHub does not show the releases just now. Try again in a while.": "GitHub сейчас не показывает релизы. Попробуй чуть позже.",
        "The release does not look right": "С релизом что-то не так", "Could not write to the temporary folder": "Не удалось записать во временную папку",
        "The download does not match the release. Nothing was installed.": "Скачанный файл не совпадает с релизом. Ничего не установлено.",
        "Could not start the installer": "Не удалось запустить установщик"
    })
}
