# Локальная сборка для Codex и Claude на Windows

Этот форк использует Lua-плагин Automaat внутри Lightroom Classic и локальный MCP-сервер.
Скрипт `scripts/start-local.mjs` запускает собранный сервер из этого checkout и по умолчанию
включает все группы инструментов (`core`, `develop`, `masks`). Явно заданное значение
`LIGHTROOM_MCP_TOOLSETS` имеет приоритет; `LIGHTROOM_MCP_READ_ONLY` продолжает работать.

## Сборка и установка

Требуется Node.js 20+ и Lightroom Classic. Из корня репозитория:

```powershell
npm.cmd --prefix server ci
node server/dist/index.js install-plugin
```

Плагин копируется в `%APPDATA%\Adobe\Lightroom\Modules\LightroomMCP.lrplugin`.
В Lightroom откройте File → Plug-in Manager → Add, выберите эту папку.
Сервер плагина запускается автоматически; Lightroom должен оставаться открытым.

После изменения Lua-файлов обновите установленную копию и перезапустите Lightroom.
`install-plugin` сохраняет уже установленную папку: для обновления сначала сделайте её
резервную копию вне репозитория, затем скопируйте поверх содержимое
`plugin/LightroomMCP.lrplugin`. После изменения TypeScript достаточно `npm.cmd --prefix server run build`
и перезапуска MCP-клиентов.

## Codex и Claude Code

Из корня репозитория, после резервного копирования конфигураций:

```powershell
$repoPath = (Resolve-Path .).Path
$nodePath = (Get-Command node.exe).Source
$launcherPath = Join-Path $repoPath 'scripts\start-local.mjs'
codex mcp add lightroom -- $nodePath $launcherPath
claude mcp add --scope user --transport stdio lightroom -- $nodePath $launcherPath
claude mcp add --scope local --transport stdio lightroom -- $nodePath $launcherPath
```

Пользовательская запись Claude Code действует в других проектах, локальная — в этом checkout.
Репозиторный `.mcp.json` также запускает локальный launcher; он требует запуска Claude Code
из корня checkout и предварительной сборки сервера.

## Claude Desktop

В `%APPDATA%\Claude\claude_desktop_config.json` добавьте запись `lightroom` в существующий
объект `mcpServers`, сохранив остальные серверы. В `args` нужен абсолютный путь к launcher:

```json
{
  "mcpServers": {
    "lightroom": {
      "command": "C:\\Program Files\\nodejs\\node.exe",
      "args": ["C:\\path\\to\\lightroom-mcp\\scripts\\start-local.mjs"]
    }
  }
}
```

После изменения конфигураций перезапустите Codex и Claude Desktop, а для Claude Code
откройте новую сессию. Проверка ниже сама запускает MCP-процессы с записанными конфигурациями;
она не перезапускает приложения и не доказывает, что уже открытый чат обновил список инструментов.

## Проверка подключения

```powershell
claude mcp get lightroom
node server/scripts/verify-local.mjs
```

Вторая команда читает конфигурации Codex, Claude Code и Claude Desktop, одновременно
открывает три MCP-соединения, проверяет инструменты проявки, читает выделенный снимок
и его настройки. Изменений снимков нет. Требуется установленный Codex CLI.

Для явного теста записи на одном известном снимке:

```powershell
node server/scripts/smoke-photo.mjs PHOTO_ID
```

Команда создаёт одну виртуальную копию, сохраняет snapshot, получает превью, увеличивает
экспозицию на 0,5 EV и контраст на 10, проверяет значения и изменение превью, затем
восстанавливает snapshot и проверяет настройки исходного снимка. Оставляет копию и snapshot
для просмотра. При ошибке после создания snapshot также пытается восстановить копию;
результат восстановления записывается в отчёт. Выбирайте снимок, у которого эти значения
ещё не достигли максимума.

JSON-отчёты и JPEG «до / после / восстановлено» сохраняются в `.cache/verification/`.
Эта папка исключена из Git: отчёты могут содержать пути и метаданные личных фотографий.
Превью из кеша Lightroom может запаздывать после правки; тест ждёт обновления и читает его дважды.

## Проверено 15 ноября 2026

- Windows, Node.js 22.23.2, Lightroom Classic 15.6, исходная версия сервера 0.27.0.
- Три одновременных соединения видят 72 инструмента, включая `set_develop_settings`.
- Чтение EXIF и Develop, JPEG-превью 1920×1280 для Sony ARW.
- Правка экспозиции 0 → 0,5 EV и контраста 0 → 10 на виртуальной копии подтверждена чтением.
- Превью изменилось; snapshot восстановил все возвращаемые Develop-настройки копии.
- Возвращаемые Develop-настройки оригинала до и после проверки совпали.

Маски, Denoise и пакетная обработка этим запуском не проверялись.
