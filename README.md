# claude-plugins

Маркетплейс личных плагинов Claude Code.

## Установка

```
/plugin marketplace add porohkun/claude-plugins
/plugin install project-hygiene@claude-plugins
```

Для разработки без установки:

```
claude --plugin-dir ./plugins/project-hygiene
```

## Что нужно поставить отдельно

`project-hygiene` приводит стиль кода через консольный CleanupCode из ReSharper. Он ставится
отдельно от плагина для Visual Studio:

```
dotnet tool install -g JetBrains.ReSharper.GlobalTools
```

После установки доступна команда `jb`. Версию стоит держать близкой к версии плагина в студии:
на разных версиях один и тот же профиль даёт разный результат.

Без этого инструмента чистка работает, но шаг приведения стиля пропускается.

## Плагины

| Плагин | Что делает |
|---|---|
| `project-hygiene` | Чистит проект и документацию от осадка принятых решений, приводит к единому виду |

## Раскладка

```
claude-plugins/
├─ .claude-plugin/
│  └─ marketplace.json          — каталог: перечень плагинов и их источники
├─ plugins/
│  └─ project-hygiene/
│     ├─ .claude-plugin/
│     │  └─ plugin.json         — манифест плагина
│     ├─ skills/
│     │  ├─ big-cleanup/
│     │  │  └─ SKILL.md         — полная чистка, с участием пользователя
│     │  └─ keep-clean/
│     │     └─ SKILL.md         — уборка после своих изменений
│     └─ standard.md            — эталон: целевое состояние проекта
└─ README.md
```

Всё, кроме `plugin.json`, лежит в корне плагина, а не внутри `.claude-plugin/`: скиллы оттуда не
подхватываются.

## Как связаны части

`standard.md` — источник правды: что считается чистым проектом. Оба скилла на него ссылаются
через `${CLAUDE_PLUGIN_ROOT}` и сами правил не содержат. Меняется представление об оптимальном —
правится `standard.md`, скиллы не трогаются.

Правила конкретного проекта в эталон не попадают: им место в `CLAUDE.md` того проекта.
