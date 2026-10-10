# Отчёт форк-агента: SocialUI S1

## Статус

Готово: задачи 4–6 SocialUI реализованы в worktree `feature/social-client-ui`
от базы `8fbc1cd`.

## Что сделано

- Создан `game/social/social_ui.gd`: полноэкранный modal surface `z_index=20`,
  группа `modal_ui`, dim-клик, сегменты друзей/заявок, поиск, рейтинг-кэш и
  fallback через `Net.house_get`, строки друзей/заявок и состояния дружбы.
- Добавлена лента: пузырьки сообщений, дата-разделители, optimistic-ввод через
  `Social`, офлайн-плашка, блокировка ввода для Светика с текстом
  «Светик писем не читает — он же дух».
- Добавлена модалка `z_index=21` с честным текстом об удалении переписки у обоих,
  действиями «Удалить из друзей»/«Заблокировать»/«Отмена» и безопасным разбором
  неизвестных/422-ответов.
- Подключены SocialUI, demo actions `social`, `social_requests`,
  `social_thread`, `social_confirm`, обработчики friend respond/remove/block,
  Esc/ad-предикаты и проверки `modal_ui`.
- Добавлены минимальные helpers рейтинга в `online.gd` и статические helpers
  `SocialUI._friend_state_text`/`SocialUI.attach`.
- Добавлены проверки в `suite_social.gd` и `suite_journal_misc.gd`.

## Коммиты

- `302c277` — `клиент S1: экран друзей, лента и модалка действий`
- Отчёт добавляется отдельным коммитом после этого файла.

## Проверки

- Selftest: `SELFTEST PASS (929/929)`.
- Демо-кадры успешно созданы через GUI-харнесом:
  - `previews/social_friends.png`
  - `previews/social_requests.png`
  - `previews/social_thread.png`
  - `previews/social_confirm.png`
- `--headless --shot` намеренно не использовался для финальных кадров:
  Godot сообщает `SHOT FAIL: нет рендера (не запускай --shot вместе с --headless)`.

## Отклонения от плана

- Пагинация/`_load_older` не добавлялись согласно R7.
- Зона Task 7/8 (кнопки в рейтинге/гостях и кликабельный production-тост)
  не расширялась; оставлены только требуемые для Task 4 ruling helpers.
- Имена рейтинговых helpers выбраны как `social_rating_cache_has` и
  `social_rating_row_by_nick`, поверх существующего `_rating_cache`.

## Concerns

- Selftest сохраняет штатные предупреждения проекта о недостающих аудиофайлах и
  renderer RID allocations при завершении; при этом счётчик selftest зелёный.
- Кадры были визуально проверены; в ленте пузырьки имеют минимальную ширину,
  чтобы кириллица не схлопывалась в вертикальную колонку.
