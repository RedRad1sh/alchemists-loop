# Android-интеграция ALCHEMIST'S LOOP

Проект уже содержит фасады и два варианта сборки. В репозитории намеренно нет
`.aar`, ключей подписи, App ID рекламных кабинетов и store credentials.
Секреты не должны попадать в Git.

## 1. Общая настройка

- Godot 4.7.x, Android export template с Gradle.
- `minSdk 24`, `targetSdk 36`, Compatibility renderer, только `arm64-v8a` для
  первого закрытого теста (при необходимости добавить `armeabi-v7a`).
- Сохранения: `user://alchemy_save.json` + backup/temp; служебные данные:
  `user://alchemists_loop_user.json`; оба файла удаляются через кнопку удаления
  данных.
- Build features: `google_play` для GP и `rustore` для RuStore.
- В релизном CI задавать `ALCHEMY_STORE`, `ALCHEMY_PRIVACY_URL` и реальные SKU
  только через секреты/консоли, не в GDScript.
- `tests/**` из экспорта НЕ исключать: `tests/selftest.gd` объявляет глобальный
  класс `Selftest`, на который ссылается `main.gd` (`run/main_scene`), а кэш
  классов `export_filter`/`exclude_filter` не перегенерирует.
- Runtime-конфиг читается цепочкой «env → ProjectSettings → дефолт» (F1/T24):
  CI прописывает значения в `project.godot` секции `[application]`
  (`config/alchemy_server`, `config/alchemy_store`,
  `config/rustore_application_id`, `config/rustore_deeplink_scheme`,
  `config/privacy_policy_url`). Как выглядит в дереве на самом деле:
  `config/alchemy_server` хранится пустым; ключей `config/alchemy_store`,
  `config/rustore_application_id` и `config/rustore_deeplink_scheme` в файле
  нет вовсе — для читателя отсутствующий ключ и пустая строка одно и то же
  (дефолт `""` = «не задано»); `config/privacy_policy_url` — непустой
  example.com-плейсхолдер, и это безопасно: `App.privacy_url_is_real`
  считает placeholder «не настроено» (см. ниже в этом разделе), так что
  поведение совпадает с пустым значением. env (`ALCHEMY_SERVER`,
  `ALCHEMY_STORE`, `ALCHEMY_PRIVACY_URL`, `RUSTORE_APPLICATION_ID`,
  `RUSTORE_DEEPLINK_SCHEME`) остаётся приоритетным для
  staging/локального запуска.
- Точный вызов релизного CI (keystore живёт в Editor Settings/CI-секретах, его
  путей и паролей в репозитории нет — Godot подхватывает их сам при наличии):
  ```
  godot --headless --export-release "Google Play" build/alchemists-loop-gp.aab
  godot --headless --export-release "RuStore" build/alchemists-loop-rustore.aab
  ```
  Перед экспортом CI обязан подставить реальные значения в `project.godot` и
  задать `package/unique_name` (в `export_presets.cfg` стоит
  `com.alchemistsloop.game` — заменить на reverse-domain владельца; `com.example.*`
  отклоняют оба стора) и сверить `version/code` с §6 ТЗ-04 (формулы в репозитории нет).
- Реальный `ALCHEMY_PRIVACY_URL` обязателен: placeholder `example.com/...`
  считается «не настроено» (кнопка «Политика конфиденциальности» не откроет
  мёртвую ссылку), а без живой https-политики сборка не готова к стору.


## 2. Google Play

1. Установить официальный `GodotGooglePlayBilling` v3.x для Godot 4.2+ в
   `addons/GodotGooglePlayBilling` и включить плагин.
2. Создать в Play Console продукты с SKU из `data/monetization.json`:
   `al_loop_ether_500`, `al_loop_ether_1500`, `al_loop_sage_gold_1`,
   `al_loop_starter_2026`, `al_loop_remove_ads`.
3. Добавить лицензионных тестеров; проверять purchase/restore/consume после
   загрузки AAB во внутренний или закрытый трек. В приложении покупки не
   выдаются по SKU из UI: только после callback с purchase token.
4. Фасад ищет `GodotGooglePlayBilling`, `BillingClient` или
   `GooglePlayBilling` и нормализует callback в `{provider, sku, token, state}`.
   Если выбранная версия addon использует другой autoload, зарегистрировать его
   под одним из этих имён либо добавить имя в
   `platform/google_play_billing.gd`.
5. Для production включить серверную проверку purchase token через Google Play
   Developer API. Service-account JSON не хранить в приложении.

## 3. RuStore

1. Взять официальные `rustore-billing-release.aar` и `RustoreBilling.gdap`
   совместимой версии, положить в `android/plugins/`, включить плагин.
2. Названия singleton/API зависят от версии пакета из кабинета RuStore. В
   адаптере предусмотрены `RuStoreGodotPayClient`, `RuStoreGodotPay`,
   `RustoreBilling` и `RuStoreBilling`; перед сборкой сверить фактический
   контракт `.aar/.gdap` и при необходимости добавить его имя в адаптер.
3. В RuStore Console завести те же логические товары с рублёвыми ценами.
   Реальные SKU задаются в `data/monetization.json`, app id и deeplink scheme —
   через `RUSTORE_APPLICATION_ID` и `RUSTORE_DEEPLINK_SCHEME`.
4. В activity/manifest обязательно обработать deeplink, `singleTop` и вызов
   `proceedIntent`/`onNewIntent` по документации SDK; это нужно для СБП/SberPay.
5. Для consumable после выдачи вызвать `confirm_purchase`/
   `confirm_two_step_purchase`; восстановление на старте делает `get_purchases`.
   Серверную проверку `subscriptionToken`/invoice id включить перед релизом.

## 4. Реклама и согласия

- Google build: AdMob; RuStore build: Яндекс Mobile Ads. Фасад ищет
  `AdMob/GodotAdMob/MobileAds` или `YandexMobileAds/YandexAds`.
- SDK не инициализируется до решения пользователя о рекламе. Единственный
  разрешающий режим — `granted`; при `unknown` и `denied` рекламный адаптер не
  поднимается (ни клиент, ни debug-стаб) и оба формата показывают отказ.
  Смена согласия в Лавке применяется без перезапуска. NPA/контекстная реклама
  без согласия сейчас не крутится вовсе — режим включается вместе с реальным
  плагином, когда есть чем проверить имена его API.
- Rewarded: добровольная кнопка, cooldown 150 с, не более 5/день. Награда
  начисляется только по сигналу «ролик досмотрен» (`rewarded`), закрытие окна
  без награды (`rewarded_closed`) — отказ, а не награда.
- Interstitial: отдельный метод с cooldown 1500 с; единственная граница показа —
  смена вкладки при полностью закрытых модальных окнах. Не показывать в первые
  10 минут первой сессии, в первые два дня и во время открытий/варки.
- Стаб доступен только отладочной сборке: `ALCHEMY_ADS_STUB=1` и `--ads-stub` в
  release не срабатывают, поэтому `adb shell am start … --esa args,--ads-stub`
  на релизном APK бесплатной рекламы не даёт.

## 5. Релизный smoke-чек

- [ ] GP: pending, cancel, successful purchase, restore, consume, refund.
- [ ] RuStore: PAID → confirm, cancel, restore, deeplink после внешней оплаты.
- [ ] Сервер собран с `ALCHEMY_RECEIPT_VALIDATION_URL` + `ALCHEMY_RECEIPT_SERVICE_KEY`
  (оба, иначе гейт выключен), валидатор отвечает, и песочная покупка в релизной
  сборке реально выдаёт валюту. Без этой пары `/api/receipt/verify` отвечает 503,
  клиент показывает «Сервер не подтвердил покупку» и **ни одна покупка в релизе
  не выдаётся** — это не деградация, а fail-closed контракт (T22). Отдельно:
  `_validate_receipt_with_vendor` в `server.py` помечен `TODO(release)` и пока
  возвращает `vendor_validation_not_implemented`; выложить сборку раньше, чем там
  появится реальный вызов магазина, = выложить сборку без IAP вовсе.
- [ ] Процесс убит между callback и save: повторный restore не даёт двойную награду.
- [ ] Плагин отсутствует: игра остаётся играбельной, магазин показывает статус.
- [ ] Consent `unknown/denied`: реклама не стартует, события аналитики не уходят.
- [ ] Экспорт создаёт локальную копию и запрашивает `GET /api/account/export`.
- [ ] Удаление данных удаляет локальный прогресс и отправляет
  `DELETE /api/account?device_id=...`; мировые вещества сохраняются, но
  авторство анонимизируется.
- [ ] AAB анализируется на 16 KB page size; target API 36.
- [ ] `ALCHEMY_PRIVACY_URL` / `config/privacy_policy_url` — реальный https-документ
  (не `example.com`/`localhost`): кнопка «Политика конфиденциальности» открывает его,
  а placeholder ведёт себя как «не настроено».
- [ ] В релизной сборке без настроенного https-сервера (`ALCHEMY_SERVER`/
  `config/alchemy_server`) игра живёт офлайн: `http://` в продакшене отклоняется,
  а не молча греется `127.0.0.1`.
