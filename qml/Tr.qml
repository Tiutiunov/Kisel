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
        "That looks like a binary file": "Похоже, это не текстовый файл", 
        "The request failed": "Запрос не удался",

        // ---- Zundamon's player ----
        "Nothing playing": "Ничего не играет", "Open Spotify and it shows up here": "Открой Spotify, и трек появится тут",
        "Previous track": "Предыдущий трек", "Pause": "Пауза", "Play": "Играть", "Next track": "Следующий трек",

        // ---- Teto's monitor ----
        "Memory": "Память", "RAM": "ОЗУ", "CPU, the last minute": "CPU за последнюю минуту", "Ping, the last minute": "Пинг за последнюю минуту", "Clean memory": "Очистить память",
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
        "What they are": "Что это",
        "A plugin that Kisel installs into Claude Code. kisel-prompts joins a session to this chat.": "Плагин, который Kisel ставит в Claude Code. kisel-prompts соединяет сессию с этим чатом.",
        "1. You need the claude command": "1. Нужна команда claude",
        "Open a terminal and run: claude --version. If it is not found, install Claude Code's command line first: npm install -g @anthropic-ai/claude-code. The desktop app alone is not enough for the button.": "Открой терминал и выполни: claude --version. Если команда не найдена, сначала поставь Claude Code для командной строки: npm install -g @anthropic-ai/claude-code. Одного приложения для кнопки мало.",
        "2. Press Install mods": "2. Нажми «Установить моды»",
        "Kisel runs the two commands shown under the button. Nothing else on your computer is changed. It takes a few seconds; the line above turns to Installed.": "Kisel выполнит две команды, показанные под кнопкой. Больше на компьютере ничего не меняется. Это несколько секунд; строка выше сменится на «Установлены».",
        "3. Start a new session": "3. Запусти новую сессию",
        "Plugins load when a session starts. Close the Claude Code chat or terminal you had open and start it again.": "Плагины загружаются при старте сессии. Закрой открытый чат или терминал Claude Code и запусти заново.",
        "4. Write from Kisel": "4. Пиши из Kisel",
        "Click the bar, open Chat. Within a couple of seconds the field reads Write to Claude Code. What you send goes to the session as your own prompt; Claude's replies appear here too.": "Кликни по таблетке, открой Chat. Через пару секунд поле станет «Написать в Claude Code». Отправленное уходит в сессию как твой собственный промпт, ответы Claude появляются здесь же.",
        "What else shows up": "Что ещё появится",
        "The rings in the chat are your limits: the five-hour window, the week, and how full the session's context is. Miku holds Claude's little one there.": "Кольца в чате это твои лимиты: пятичасовое окно, неделя и заполненность контекста сессии. Мику там держит зверька Claude.",
        "If the field still says Message Claude": "Если поле всё ещё «Написать Claude»",
        "No session is listening. Check that the session was started after installing, and that Kisel sees it (Miku reacts when Claude works). The session and Kisel must run under the same Windows user.": "Ни одна сессия не слушает. Проверь, что сессия запущена после установки и что Kisel её видит (Мику реагирует, когда Claude работает). Сессия и Kisel должны работать под одним пользователем Windows.",
        "Doing it by hand": "Вручную",
        "The same two commands work in any terminal. To take the mod out: Remove mods here, or claude plugin uninstall kisel-prompts@kisel.": "Те же две команды работают в любом терминале. Чтобы убрать мод: «Убрать моды» здесь, или claude plugin uninstall kisel-prompts@kisel.",
        "What it can and cannot do": "Что он умеет и чего нет",
        "It only passes text: your prompts in, Claude's words and the limit figures out, through a folder in your home folder (.kisel, inbox). It never answers a permission for you.": "Он только передаёт текст: твои промпты туда, слова Claude и цифры лимитов обратно, через папку в твоей домашней папке (.kisel, inbox). На запросы разрешений он за тебя не отвечает никогда.",
        "How the mods work": "Как работают моды",
        "Installed, an update is ready": "Установлены, есть обновление", "Update mods": "Обновить моды",
        "Claude Code mods": "Моды для Claude Code", "Installed": "Установлены", "Partly installed": "Установлены не все", "Working on it": "Ставлю",
        "Checking": "Проверяю", "Claude Code was not found": "Claude Code не найден", "This build has no mods to install": "В этой сборке модов нет",
        "Couldn't install": "Не получилось поставить", "Not installed": "Не установлены", "Install the rest": "Доставить", "Install mods": "Установить моды", "Remove mods": "Убрать моды",
        "A plugin for Claude Code. It joins your session to the chat here: what you write goes to it as your prompt, and Claude's replies and your limits come back. It loads in sessions started after this.": "Плагин для Claude Code. Он соединяет твою сессию с чатом здесь: написанное уходит в неё как твой промпт, а ответы Claude и лимиты приходят обратно. Загружается в сессиях, запущенных после установки.",
        "No Claude Code session is listening. Install the mods in Settings.": "Ни одна сессия Claude Code не слушает. Установи моды в настройках.",
        "Write to Claude Code": "Написать в Claude Code", "Sent. Claude takes it when it is free.": "Отправлено. Claude возьмёт, когда освободится.",
        "Claude Code has it": "Claude Code принял", "5 hours": "5 часов", "Week": "Неделя", "Context": "Контекст", "Spend": "Расход", "until ": "до ", "It goes to your session as your own prompt": "Уйдёт в твою сессию как твой собственный промпт", "Couldn't send it": "Не получилось отправить",
        "Needs repair": "Нужна починка", "Repair hooks": "Починить хуки", "settings.json is not valid JSON": "settings.json — не валидный JSON",
        "If hooks break": "Если хуки сломались", "Ask me": "Спросить", "Repair": "Чинить сама", "Do nothing": "Ничего",
        "Claude Code hooks need repair. Open Settings.": "Хуки Claude Code сломались. Открой настройки.",
        "Claude Code is not connected. Open Settings.": "Claude Code не подключён. Открой настройки.",
        "Claude Code hooks repaired": "Хуки Claude Code починены",
        "Hooks that were connected and went stale are repaired by themselves, with a dated backup. New hooks are never added without your click.": "Хуки, которые уже были подключены и устарели, чинятся сами, с резервной копией. Новые без твоего клика не добавляются.",
        "Kisel tells you when the hooks are missing or stale. The change is made only after you confirm it here.": "Kisel скажет, если хуков нет или они устарели. Менять файл он будет только после твоего подтверждения здесь.",
        "Kisel does not check the hooks.": "Kisel не проверяет хуки.", "Nothing to change in ": "Нечего менять в ",
        "This is the exact change to ": "Вот точное изменение в ", ". A backup is saved first as ": ". Сначала сохраняется копия: ",
        "Write change": "Записать", "Cancel": "Отмена", "Save": "Сохранить",
        "Token saved in ": "Токен сохранён: ", "Personal access token (read-only)": "Личный токен (только чтение)", "Remove": "Убрать",
        "GitHub token removed": "Токен GitHub убран", "Screen": "Экран", ", Kisel is here": ", Kisel здесь", "Kisel moved to ": "Kisel переехал на ",
        "Follow primary": "За основным", "Following the primary monitor": "Следую за основным монитором",
        "Kisel follows your primary monitor (": "Kisel держится основного монитора (", "), also after a restart": "), и после перезапуска тоже",
        "Kisel stays on ": "Kisel остаётся на ", ", also after a restart": ", и после перезапуска тоже",
        "Look and sound": "Вид и звук", "Sounds": "Звуки", "Reduce motion": "Меньше движения",
        "Close at once when the pointer leaves": "Закрывать сразу, как уходит курсор", "Close ": "Закрывать через ", " s after the pointer leaves": " с после ухода курсора",
        "Place": "Место", "Top": "Сверху", "Bottom": "Снизу", "Left": "Слева", "Right": "Справа",
        "In the middle of the edge": "Посередине края", "Load": "Нагрузка", "Frequency": "Частота", "Temperature": "Температура", "Fan": "Вентилятор", "Threads": "Потоки", " MHz": " МГц", " W": " Вт", "It is roasting in here. Give it some air.": "Тут жарища. Дай ему подышать.", "Drive ": "Диск ", " is nearly full. Tidy up, will you?": " почти забит. Прибери там, а?", " free": " свободно", " rpm": " об/мин", " TB": " ТБ", "The bar never hides": "Таблетка не прячется", " s": " с", "The bar hides after ": "Таблетка прячется через ", " of rest": " покоя", "Volume: ": "Громкость: ", "The latest notifications": "Последние уведомления", "Show text": "Показать текст", "Hide text": "Скрыть текст", "now": "сейчас", " min": " мин", " h": " ч", " d": " д", "Nothing yet! I will shout the moment something comes.": "Пока ничего! Как только что-то придёт, я закричу.", "Align": "Выровнять", "Centre": "По центру", "Toward the top": "Ближе к верху", "Toward the bottom": "Ближе к низу",
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
        "Could not start the installer": "Не удалось запустить установщик",
        "Services": "Сервисы", "Characters": "Персонажи", "Theme": "Тема",
        "Effort": "Усилие", "Low": "Низкое", "Medium": "Среднее", "High": "Высокое", "Higher": "Выше", "Max": "Макс",
        "Quick question": "Быстрый вопрос", "A quick question": "Быстрый вопрос", "Outside your sessions and projects.": "Вне твоих сессий и проектов.",
        "Ask a quick question": "Задай быстрый вопрос", "Claude is answering...": "Claude отвечает...", "Looking it up...": "Ищет в сети...", "Auto": "Авто", "Start over": "Начать заново",
        "The claude command is not signed in. Open a terminal, run claude, then /login.": "Команда claude не вошла в аккаунт. Открой терминал, запусти claude, затем /login.",
        "On stage": "На сцене", "Who does what": "Кто чем занят", "Notifications": "Уведомления", "Internet": "Интернет", "Music": "Музыка", "Computer": "Компьютер",
        "Show in Discord that I work with Claude Code": "Показывать в Discord, что я работаю с Claude Code",
        "Show the session's name too": "Показывать и название сессии",
        "Discord Application ID": "Application ID из Discord",
        "Connected to Discord": "Подключено к Discord",
        "Needs an Application ID": "Нужен Application ID",
        "Discord did not take this Application ID": "Discord не принял этот Application ID",
        "Discord is not running": "Discord не запущен",
        "An Application ID is a long number": "Application ID — это длинное число",
        "Discord shows an activity under the name of a Discord application. Make one called Kisel at discord.com/developers/applications, copy its Application ID here, and add a picture named kisel under Rich Presence, Art Assets if you want one. The ID is a public number, not a password.": "Discord показывает активность под именем Discord-приложения. Создай приложение с названием Kisel на discord.com/developers/applications, скопируй сюда его Application ID и, если хочешь картинку, добавь её под именем kisel в Rich Presence, Art Assets. ID — открытый номер, не пароль."
    })
}
