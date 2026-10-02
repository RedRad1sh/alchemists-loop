/* Превью для приемки UI «Atheneum» v2.
 * «ДО» собирается по фактическим значениям из кода (main.gd, game/*.gd) и кадрам
 * previews/*.png; «ПОСЛЕ» — по токенам game/ui/design_tokens.gd. */
(() => {
const ICONS = ["bolt","star","trend_up","volume","volume_off","book","user","home","bag","flask",
  "cauldron","globe","trophy","sliders","repeat","x","check","chevron_right","chevron_down",
  "search","mail","map","plus","info","lock","fire","drop","clock","gift","dots","leaf","gem",
  "stop","settings","play","wind","mountain"];

const GLYPH_MAP = [
  ["✦", "star", "шапка: задания/ачивки"],
  ["▲ + «▲N»", "trend_up + пилюля-бейдж", "шапка: улучшения"],
  ["♪", "volume / volume_off", "шапка: звук"],
  ["Ж", "book", "шапка: журнал"],
  ["⚡", "bolt", "эфир в строках и статусах"],
  ["↻", "repeat", "BrewBar: повтор"],
  ["✕", "x", "BrewBar: сброс, крестик попапа"],
  ["✓ / ● / ○ / ·", "check / dots", "статусы и отметки"],
  ["⚗", "gem", "престиж «Перегонка»"],
  ["— (нет)", "cauldron / flask / globe / trophy / sliders", "вкладки: иконки разделов"],
];

const CHECKLIST = [
  ["UX-01", "Шапка: 5 крипто-кнопок 46×36 без иконок", "fixed", "иконки star/trend_up/volume/book, тач 44×44"],
  ["UX-02", "Бейдж «▲1» внутри текста кнопки", "fixed", "пилюля CountBadge поверх кнопки (UiIcon.badge)"],
  ["UX-03", "Бренд 24 px ExtraBold без трекинга", "partial", "кегль 21 + трекинг в токенах; внедрение заголовков — фаза 5"],
  ["UX-04", "Пузырь Светика перекрывает «Дом/Лавка»", "fixed", "якорь пузыря ниже строки ресурсов (companion.gd, превью: после)"],
  ["UX-05", "Орб Светика поверх вкладок и скроллбара", "partial", "закреплён в safe-зоне; финально с safe-area (фаза 5)"],
  ["UX-06", "Эфир/резерв/прирост в одной строке", "fixed", "KPI-чип: иконка bolt + значение + прирост отдельно"],
  ["UX-07", "«Дом» gold и «Лавка» teal — две главные", "fixed", "обе вторичные с иконками, равный вес"],
  ["UX-08", "Дефолтный скин TabContainer, обрезка «Инструменты»", "fixed", "pill-сегмент + иконки, кегль 13 SemiBold, помещается на 540 px"],
  ["UX-09", "6 вкладок вне thumb-зоны", "backlog", "нижняя навигация 5+Ещё — фаза 5 (Task 10)"],
  ["UX-10", "Порядок вкладок не по частоте", "partial", "иконки ускоряют поиск; порядок трогает тесты — фаза 5"],
  ["UX-11", "Interstitial на каждую смену вкладки", "backlog", "продуктовое решение по монетизации — отдельно"],
  ["UX-12", "Бейдж «100» поверх орба", "fixed", "пилюля внутри орба снизу по центру, SemiBold 11"],
  ["UX-13", "8 контролов в ряд, «ВАРИТЬ» в середине", "fixed", "ряд источников → прогресс+ВАРИТЬ справа (thumb-зона)"],
  ["UX-14", "Прогресс без подписи", "fixed", "подпись «КОТЁЛ» капсом с трекингом над полосой"],
  ["UX-15", "Контент уезжает под BrewBar, нет safe-area", "partial", "высота панели учтена; safe-area inset — фаза 5"],
  ["UX-16", "«Стоп» сдвигает статус при появлении", "fixed", "кнопка резервирует место: disabled вместо visible"],
  ["UX-17", "Двойная рамка поля эксперимента", "fixed", "шторка выбора без собственного контура"],
  ["UX-18", "Строка реагента 64 px, описание трункится", "fixed", "72 px, описание переносится, цена с иконкой bolt"],
  ["UX-19", "Чипы фильтров в трёх разных стилях", "fixed", "сегмент-чипы: активный = accent-soft + accent"],
  ["UX-20", "Поиск без рамки/иконки/фокуса", "fixed", "Theme LineEdit: рамка, фокус-акцент, иконка search"],
  ["UX-21", "Пустая зона 300 px внизу панели", "partial", "шторка тянется до поля; финально с нижней навигацией"],
  ["UX-22", "Disabled-CTA «Домик построен ✓» во всю ширину", "fixed", "инфо-строка с иконкой check"],
  ["UX-23", "4 одинаковых teal-кнопки выбора варианта", "fixed", "компактные вторичные 112×40 со стрелкой"],
  ["UX-24", "Подпись под сценой дома обрезается", "fixed", "перенос + отступ от CTA-зоны"],
  ["UX-25", "Два равных действия в попапе, нет крестика", "fixed", "крестик 44 px, главное действие одно (accent)"],
  ["UX-26", "Все заголовки попапов капсом жёлтым", "partial", "токен gold только для наград; интонации — фаза 5"],
  ["UX-27", "Модалки флагами visible, нет стека", "backlog", "стек экранов — фаза 5 (Task 11)"],
  ["UX-28", "Нет видимого фокуса", "fixed", "focus = accent-outline 2 px во всех фабриках"],
  ["UX-29", "Нет safe-area inset", "backlog", "фаза 5 (Task 14)"],
  ["UX-30", "Скроллбар поверх панелей", "fixed", "Theme: тонкая пилюля-ползунок, прозрачная дорожка"],
  ["UX-31", "Disabled неотличим, нет loading", "partial", "disabled-токены готовы; skeleton сетей — фаза 5"],
  ["UX-32", "Нет переходов кнопок/вкладок", "backlog", "motion-пакет — фаза 5 (Task 13)"],
];

const PALETTE = [
  ["BG0", "#0a0f16", "фон экрана"],
  ["BG1", "#121a24", "панели, карточки"],
  ["BG2", "#18222e", "кнопки, приподнятые поверхности"],
  ["BG3", "#0d141d", "поля ввода, дорожки прогресса"],
  ["LINE", "#24313f", "рамки карточек"],
  ["LINE_STRONG", "#35485c", "рамки полей, ховер"],
  ["INK1", "#eaf2f7", "основной текст"],
  ["INK2", "#a9b8c6", "вторичный текст"],
  ["INK3", "#7e8d9c", "приглушённый, плейсхолдеры"],
  ["ACCENT", "#3ad6c6", "действие, эфир, фокус"],
  ["ACCENT_INK", "#052622", "текст на акценте (9.4:1)"],
  ["GOLD", "#e9b44c", "награды, престиж"],
  ["GOLD_INK", "#241a05", "текст на золоте (8.9:1)"],
  ["DANGER", "#e5705f", "ошибки, сброс"],
  ["SUCCESS", "#6fcf8e", "успех, готовность"],
  ["VIOLET", "#b49aff", "Светик, духи"],
];

const TYPES = [
  ["DISPLAY", "26/32 ExtraBold +0.6", "ПЕТЛЯ АЛХИМИКА", 800, 26, 0.6],
  ["H1", "21/27 ExtraBold +0.2", "Эксперимент", 800, 21, 0.2],
  ["H2", "17/23 Bold", "Книга рецептов", 700, 17, 0],
  ["H3", "15/21 SemiBold", "Родник управляет стихией", 600, 15, 0],
  ["BODY", "15/22 Regular", "Перетащи ингредиенты в лунки котла.", 400, 15, 0],
  ["SMALL", "13/18 Medium", "Каждые 6 с: +1 «Вода».", 500, 13, 0],
  ["CAPTION", "11/15 SemiBold +0.6", "ПОЛЕ ЭКСПЕРИМЕНТА", 600, 11, 0.6],
  ["BTN", "15/20 SemiBold", "ВАРИТЬ", 600, 15, 0.1],
  ["TAB", "13/18 SemiBold +0.2", "Лаборатория", 600, 13, 0.2],
];

const ic = (n, s = 20) => `<span class="ic" style="--icon:url('../../assets/ui/icons/${n}.svg');width:${s}px;height:${s}px"></span>`;
const orb = (col, glyph, cnt, mode) => `
  <span class="orb" style="background:radial-gradient(circle at 35% 30%, #ffffff55, transparent 45%), ${col}">
    <span class="gly">${mode === "before" ? glyph : ""}</span>
    ${cnt ? `<span class="cnt">${cnt}</span>` : ""}
  </span>`;

/* ---------- общие блоки экрана ---------- */
function header(mode) {
  const btns = mode === "before"
    ? `<button class="hbtn gold">✦</button>
       <button class="hbtn">▲<span class="bnum">1</span></button>
       <button class="hbtn">♪</button>
       <button class="hbtn">Ж</button>`
    : `<button class="hbtn">${ic("star", 20)}</button>
       <button class="hbtn">${ic("trend_up", 20)}<span class="bnum">1</span></button>
       <button class="hbtn">${ic("volume", 20)}</button>
       <button class="hbtn">${ic("book", 20)}</button>`;
  return `<div class="head">
    <div class="title">ПЕТЛЯ АЛХИМИКА</div>
    ${btns}
    <span class="orb" style="width:36px;height:36px;background:radial-gradient(circle at 35% 30%, #9fe8b0, #2f8f5b)"></span>
  </div>`;
}
function resrow(mode) {
  return mode === "before"
    ? `<div class="resrow"><span class="val">⚡ Эфир: 120 / 230 &nbsp;·&nbsp; резерв: 0 &nbsp;·&nbsp; +1.05/с</span>
        <button class="wbtn gold">Дом</button><button class="wbtn teal">Лавка</button></div>
       <div class="subline">Веществ открыто: 11 / 57 &nbsp;·&nbsp; Рецептов: 7 / 53</div>
       <div class="questline">✦ Светик: Первая пара — 0/1</div>`
    : `<div class="resrow">${ic("bolt", 18)}<span class="kpi">120 / 230</span>
        <span class="val muted" style="color:var(--ink3)">+1.05/с · резерв 0</span>
        <button class="wbtn">${ic("home", 16)}Дом</button>
        <button class="wbtn">${ic("bag", 16)}Лавка</button></div>
       <div class="subline">Веществ открыто: 11 / 57 &nbsp;·&nbsp; Рецептов: 7 / 53</div>
       <div class="questline">${ic("star", 14)} Светик: Первая пара — 0/1</div>`;
}
const TABS = [["flask","Эксперимент"],["cauldron","Лаборатория"],["globe","Мир"],["home","Дом"],["trophy","Рейтинг"],["sliders","Инструменты"]];
function tabs(mode, active) {
  return `<div class="tabs">${TABS.map(([i, n], k) =>
    `<span class="tab${k === active ? " on" : ""}">${mode === "after" ? ic(i, 14) : ""}${n}</span>`).join("")}</div>`;
}

/* ---------- экраны ---------- */
function screenLab(mode) {
  return `<div class="screen">
    ${header(mode)}${resrow(mode)}${tabs(mode, 1)}
    <div class="panel" style="flex:1">
      <div style="display:flex;align-items:center;gap:18px;justify-content:center;padding:14px 0 6px">
        <div style="text-align:center">${orb("#e0764f", "▲", 0, mode)}<div class="muted" style="font-size:11px;margin-top:4px">A</div></div>
        <div style="width:170px;height:110px;border-radius:0 0 85px 85px;background:linear-gradient(#4a5468,#333c4e);position:relative">
          <div style="position:absolute;top:-10px;left:-8px;right:-8px;height:26px;border-radius:50%;background:#5b6579"></div>
        </div>
        <div style="text-align:center">${orb("#5aa7e8", "◆", 0, mode)}<div class="muted" style="font-size:11px;margin-top:4px">B</div></div>
      </div>
      <div class="sect">Родник</div>
      <div style="display:flex;gap:14px;justify-content:center;padding:4px 0 8px">
        ${orb("#e0764f", "▲", 0, mode)}${orb("#5aa7e8", "◆", 0, mode)}${orb("#c4a47c", "▲", 0, mode)}${orb("#cee8ef", "≋", 0, mode)}
      </div>
      <div class="subline" style="font-size:13px">Каждые 6 с: +1 «Вода».</div>
      <div class="sect" style="${mode === "before" ? "color:#fff;font-size:16px" : ""}">Книга рецептов</div>
      <div class="inputwrap">${ic("search", 16)}<input class="input" placeholder="Поиск вещества по названию…"></div>
    </div>
    <div class="brewbar">
      ${mode === "before" ? `
      <div class="brewrow">
        <button class="btn k0" style="height:42px;padding:0 12px">Все</button>
        ${orb("#e0764f", "▲", 100, mode)}${orb("#5aa7e8", "◆", 100, mode)}${orb("#c4a47c", "▲", 100, mode)}${orb("#cee8ef", "≋", 100, mode)}
        <button class="btn k1" style="height:52px;padding:0 26px;font-size:16px">ВАРИТЬ</button>
        <button class="btn k1" style="height:42px;width:44px">↻</button>
        <button class="btn k0" style="height:42px;width:44px">✕</button>
      </div>
      <div class="prog"><i></i></div>
      <div class="statusrow">Перетащи ингредиенты в лунки или нажми «Варить».</div>` : `
      <div class="brewrow">
        <button class="btn k0" style="height:44px;padding:0 12px">Все</button>
        ${orb("#e0764f", "", 100, mode)}${orb("#5aa7e8", "", 100, mode)}${orb("#c4a47c", "", 100, mode)}${orb("#cee8ef", "", 100, mode)}
      </div>
      <div class="brew-mid">
        <div class="grow"><span class="prog-lbl">Котёл</span><div class="prog"><i></i></div></div>
        <button class="btn k1" style="height:52px;padding:0 24px;font-size:15px">${ic("cauldron", 18)}ВАРИТЬ</button>
      </div>
      <div class="statusrow">
        <span style="flex:1">Перетащи ингредиенты в лунки или нажми «Варить».</span>
        <button class="btn k1" style="width:44px;height:44px">${ic("repeat", 18)}</button>
        <button class="btn k0" style="width:44px;height:44px">${ic("x", 18)}</button>
        <button class="btn k1" style="height:44px;padding:0 14px" disabled>Стоп</button>
      </div>`}
    </div>
  </div>`;
}

function screenExperiment(mode) {
  const rows = [["#5aa7e8","◆","Вода","Текучая влага — первостихия. Вода · ID water"],
                ["#cee8ef","≋","Воздух","Ветер и небо — первостихия. Воздух · ID air"],
                ["#c4a47c","▲","Земля","Почва и камень — первостихия. Земля · ID earth"],
                ["#e0764f","▲","Огонь","Жар и пламя — первостихия. Огонь · ID fire"]];
  return `<div class="screen">
    ${header(mode)}${resrow(mode)}${tabs(mode, 0)}
    <div style="display:flex;align-items:center;gap:10px">
      <div class="sect" style="flex:1;${mode === "before" ? "font-size:20px;color:#fff;font-weight:800" : "font-size:21px;font-weight:800"}">ЭКСПЕРИМЕНТ</div>
      <button class="btn k2" style="height:36px;padding:0 12px;font-size:13px">${mode === "after" ? ic("star", 14) : "✦"} Светик · 10 ⚡</button>
    </div>
    <div class="subline" style="font-size:13px">«Вода» в котле · выбери второй реагент.</div>
    <div class="panel double" style="flex:1">
      <div style="display:flex;align-items:center;gap:8px">
        <div style="flex:1;font-weight:${mode === "before" ? 700 : 600};font-size:${mode === "before" ? 14 : 15}px">ВЫБРАТЬ ВТОРОЙ</div>
        <span class="muted" style="font-size:11px">4 / 11</span>
        <button class="btn k0" style="height:40px;padding:0 14px">Закрыть</button>
      </div>
      <div class="subline" style="font-size:${mode === "before" ? 12 : 13}px">Первый реагент уже на canvas. Выбери второй — пара уйдёт на серверную проверку.</div>
      <div class="inputwrap">${ic("search", 16)}<input class="input" placeholder="Найти второй реагент…"></div>
      <div class="chips">
        <button class="chip on">Недавние</button><button class="chip">Светик</button>
        <button class="chip">Стихии</button><button class="chip">Все</button>
      </div>
      ${rows.map(([c, g, nm, ds]) => `<div class="rowitem">
        ${orb(c, g, 100, mode)}
        <div style="flex:1;min-width:0"><div class="nm">${nm}</div><div class="ds">${ds}</div></div>
        <span class="cost">${mode === "after" ? ic("bolt", 13) : "⚡"}100</span>
        <span class="chev">${mode === "after" ? ic("chevron_right", 16) : "›"}</span>
      </div>`).join("")}
    </div>
    ${mode === "before" ? `<div class="bubble">Привет! Я — Светик. Давай сварим что-нибудь!</div>` : ``}
  </div>`;
}

function screenHouse(mode) {
  const furn = [["home","Окно · 1/10","Классическое"],["map","Ковёр · 3/10","Восточный"],
                ["user","Стул · 1/10","Классический"],["leaf","Растение · 1/10","В горшке"]];
  return `<div class="screen">
    ${header(mode)}${resrow(mode)}${tabs(mode, 3)}
    <div class="panel" style="flex:1;overflow:hidden">
      <div class="poptitle" style="font-size:${mode === "before" ? 22 : 21}px;text-align:center">ДОМ СВЕТИКА</div>
      <div class="popsub" style="text-align:center">Уют, обстановка и произвольные цвета — видно другим игрокам.</div>
      <div class="housescene"><div class="fire"></div></div>
      ${mode === "before"
        ? `<button class="btn k2 donecta" disabled>Домик построен ✓</button>`
        : `<div class="inforow">${ic("check", 16)}Домик построен — уют виден гостям и в рейтинге.</div>`}
      <div class="sect" style="${mode === "before" ? "color:#fff;font-size:14px;font-weight:400" : ""}">Обстановка</div>
      <div class="subline" style="font-size:12px">Коллекция: 12/90 · купленное ставится бесплатно</div>
      ${furn.map(([i, nm, v]) => `<div class="furnrow">
        <span class="thumb">${ic(i, 20)}</span><span class="nm">${nm}</span>
        ${mode === "before"
          ? `<button class="btn k1" style="height:44px;padding:0 18px">${v} ✓</button>`
          : `<button class="btn k0" style="height:40px;padding:0 12px;font-size:13px">${v}${ic("chevron_right", 14)}</button>`}
      </div>`).join("")}
    </div>
  </div>`;
}

function screenPopup(mode) {
  return `<div class="screen">
    ${header(mode)}${resrow(mode)}${tabs(mode, 1)}
    <div class="panel" style="flex:1"></div>
    <div class="dim"><div class="popcard">
      ${mode === "after" ? `<button class="btn k0 popx" style="width:44px;height:44px">${ic("x", 18)}</button>` : ``}
      <div class="poptitle">НОВЫЙ РЕЦЕПТ!</div>
      <div style="display:flex;justify-content:center">${orb("#96d691", "✿", 0, mode)}</div>
      <div class="popsub">Огонь + Росток → Цветок<br>+12 эфира</div>
      <div class="popactions">
        <button class="btn k2" style="${mode === "after" ? "background:var(--accent);color:var(--accent-ink)" : ""}">Забрать</button>
        <button class="btn k0 secondary">Закрыть</button>
      </div>
    </div></div>
  </div>`;
}

const SCREENS = [["lab", "Лаборатория", screenLab], ["exp", "Эксперимент", screenExperiment],
  ["house", "Дом", screenHouse], ["popup", "Попап", screenPopup]];

/* ---------- рендер_views ---------- */
const content = document.getElementById("content");
let view = "screens", screenKey = "lab", mode = "after";

function phone(modeName, screenFn, scale) {
  return `<div class="phone-wrap">
    <div class="phone-label">${modeName === "before" ? "До · текущий UI" : "После · Atheneum v2"}</div>
    <div style="width:${540 * scale}px;height:${960 * scale}px">
      <div class="phone" data-mode="${modeName}" style="transform:scale(${scale})">${screenFn(modeName)}</div>
    </div>
  </div>`;
}

function renderScreens() {
  const fn = SCREENS.find(s => s[0] === screenKey)[2];
  const both = mode === "both";
  const scale = both ? 0.56 : 0.72;
  content.innerHTML = `
    <div class="screen-tabs">
      ${SCREENS.map(([k, n]) => `<button class="seg${k === screenKey ? " on" : ""}" data-screen="${k}">${n}</button>`).join("")}
    </div>
    <div class="stage">
      ${both ? phone("before", fn, scale) + phone("after", fn, scale) : phone(mode, fn, scale)}
    </div>`;
  content.querySelectorAll("[data-screen]").forEach(b =>
    b.onclick = () => { screenKey = b.dataset.screen; render(); });
}

function renderIcons() {
  content.innerHTML = `
    <div class="h2">Икон-сет «Atheneum»</div>
    <p class="lead">37 векторных иконки: сетка 24×24, stroke 2, round cap/join, база белая (в Godot тонируется
      <code>modulate</code>, здесь — CSS mask). Источник: <code>assets/ui/icons/*.svg</code>,
      генератор <code>tools/make_icons.py</code>. Раньше иконок не было вовсе — только Unicode-глифы.</p>
    <div class="grid icon-grid">
      ${ICONS.map(n => `<div class="icon-cell">${ic(n, 24)}<span class="nm">${n}</span></div>`).join("")}
    </div>
    <div class="h3">Что заменило глифы</div>
    <table class="check-table"><tr><th>Было</th><th>Стало</th><th>Где</th></tr>
    ${GLYPH_MAP.map(([a, b, c]) => `<tr><td style="color:#e5705f">${a}</td><td style="color:#6fcf8e">${b}</td><td class="muted">${c}</td></tr>`).join("")}
    </table>`;
}

function renderTokens() {
  content.innerHTML = `
    <div class="h2">Токены: цвет, типографика, геометрия</div>
    <p class="lead">16 цветовых токенов вместо 148 хардкод-RGB из кода; 9 ролей типографики вместо 8 случайных
      кеглей; тач-минимум 44 px вместо 36–42. Контрасты текста ≥ 4.5:1 (WCAG AA).</p>
    <div class="grid" style="grid-template-columns:repeat(auto-fill,minmax(320px,1fr))">
      ${PALETTE.map(([n, h, u]) => `<div class="swatch"><span class="chipcol" style="background:${h}"></span>
        <span><span class="nm">${n}</span><br><span class="hex">${h}</span></span>
        <span class="use">${u}</span></div>`).join("")}
    </div>
    <div class="h3">Типографика (Manrope)</div>
    <div class="stack">
      ${TYPES.map(([r, m, s, w, sz, ls]) => `<div class="type-row" style="width:100%">
        <span class="role">${r}<br>${m}</span>
        <span class="sample" style="font-weight:${w};font-size:${sz}px;letter-spacing:${ls}px">${s}</span>
      </div>`).join("")}
    </div>
    <div class="h3">Геометрия</div>
    <p class="lead">spacing 4/8/12/16/20/24/32 · radius ctrl 10 / card 14 / sheet 18 / pill ∞ ·
      hit ≥ 44×44 (шапка 44) · elevation 3 уровня · скрим модалок #04080c @ 66%</p>`;
}

function cmpCol(title, modeName, inner) {
  return `<div class="col"><h4>${title}</h4><div class="phone" data-mode="${modeName}"
    style="position:relative;inset:auto;transform:none;width:auto;height:auto;border:0;border-radius:12px;padding:14px;
    display:flex;flex-direction:column;gap:12px;background:var(--bg0)">${inner}</div></div>`;
}
function renderComponents() {
  const set = (m) => `
    <div class="stack">
      <div style="display:flex;gap:8px;flex-wrap:wrap">
        <button class="btn k0" style="height:${m === "before" ? 38 : 44}px;padding:0 16px">Вторичная</button>
        <button class="btn k1" style="height:${m === "before" ? 38 : 44}px;padding:0 16px">ВАРИТЬ</button>
        <button class="btn k2" style="height:${m === "before" ? 38 : 44}px;padding:0 16px">Награда</button>
        <button class="btn k1" style="height:${m === "before" ? 38 : 44}px;padding:0 16px" disabled>Disabled</button>
      </div>
      <div class="chips"><button class="chip on">Активный</button><button class="chip">Обычный</button><button class="chip">Ещё</button></div>
      <div class="inputwrap">${ic("search", 16)}<input class="input" placeholder="Поиск вещества…"></div>
      <div class="prog" style="width:100%"><i></i></div>
      <div style="display:flex;gap:10px;align-items:center">
        ${orb("#e0764f", "▲", 100, m)}${orb("#5aa7e8", "◆", 7, m)}
        <button class="hbtn${m === "before" ? " gold" : ""}">${m === "before" ? "✦" : ic("star", 20)}</button>
        <button class="hbtn">${m === "before" ? "▲<span class='bnum'>1</span>" : ic("trend_up", 20) + "<span class='bnum'>1</span>"}</button>
      </div>
      <div class="tabs" style="width:100%">
        <span class="tab on">${m === "after" ? ic("flask", 15) : ""}Эксперимент</span>
        <span class="tab">${m === "after" ? ic("cauldron", 15) : ""}Лаборатория</span>
        <span class="tab">${m === "after" ? ic("globe", 15) : ""}Мир</span>
      </div>
    </div>`;
  content.innerHTML = `
    <div class="h2">Компоненты: до и после</div>
    <p class="lead">Одни и те же компоненты в двух режимах. Обратите внимание: контраст текста на акценте
      (было 3.07:1 белым по #20a49b → стало 9.4:1 тёмными чернилами по #3ad6c6), видимый фокус,
      бейдж-пилюля вместо «наклейки», единые радиусы и состояния.</p>
    <div class="cmp">${cmpCol("До", "before", set("before"))}${cmpCol("После", "after", set("after"))}</div>`;
}

function renderChecklist() {
  const cnt = (s) => CHECKLIST.filter(c => c[2] === s).length;
  content.innerHTML = `
    <div class="h2">Чек-лист находок (UX-01…UX-32)</div>
    <p class="lead">Исправлено сейчас: <b style="color:#6fcf8e">${cnt("fixed")}</b> ·
      частично (токены готовы, внедрение в фазе 5): <b style="color:#e9b44c">${cnt("partial")}</b> ·
      бэклог: <b style="color:#a9b8c6">${cnt("backlog")}</b>.
      Полные формулировки и доказательства — <code>docs/ui-ux/2026-10-01-ui-ux-analysis.md</code>.</p>
    <table class="check-table">
      <tr><th style="width:70px">ID</th><th>Недостаток</th><th style="width:90px">Статус</th><th>Правка</th></tr>
      ${CHECKLIST.map(([id, t, s, f]) => `<tr><td><b>${id}</b></td><td>${t}</td>
        <td><span class="pill ${s}">${s === "fixed" ? "исправлено" : s === "partial" ? "частично" : "бэклог"}</span></td>
        <td class="muted">${f}</td></tr>`).join("")}
    </table>`;
}

function render() {
  document.body.dataset.mode = mode === "before" ? "before" : "after";
  document.getElementById("m-before").classList.toggle("on", mode === "before");
  document.getElementById("m-after").classList.toggle("on", mode === "after");
  document.getElementById("m-both").classList.toggle("on", mode === "both");
  document.getElementById("meta-line").textContent =
    view === "screens" ? `экран: ${SCREENS.find(s => s[0] === screenKey)[1]} · режим: ${mode === "both" ? "сравнение" : mode === "before" ? "ДО" : "ПОСЛЕ"}` : "";
  ({ screens: renderScreens, icons: renderIcons, tokens: renderTokens,
     components: renderComponents, checklist: renderChecklist })[view]();
}

document.querySelectorAll(".nav").forEach(b => b.onclick = () => {
  document.querySelectorAll(".nav").forEach(x => x.classList.remove("on"));
  b.classList.add("on"); view = b.dataset.view; render();
});
document.getElementById("m-before").onclick = () => { mode = mode === "both" ? "before" : "before"; render(); };
document.getElementById("m-after").onclick = () => { mode = "after"; render(); };
document.getElementById("m-both").onclick = () => { mode = "both"; render(); };
document.addEventListener("keydown", (e) => {
  if (e.key === "b") { mode = "both"; render(); }
  if (e.key === "1") { mode = "before"; render(); }
  if (e.key === "2") { mode = "after"; render(); }
});
render();
})();
