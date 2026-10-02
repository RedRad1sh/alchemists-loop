/* Превью для приемки UI «Atheneum» (итерация-1 после отката).
 * Оставлено: сет иконок + меню вкладок (pill-сегмент). Остальной UI показан
 * «как есть в игре» в обоих режимах; режимы отличаются ТОЛЬКО вкладками.
 * «ДО» вкладок = дефолтный TabContainer Godot, «ПОСЛЕ» = pill + иконки 16 px. */
(() => {
const ICONS = ["bolt","star","trend_up","volume","volume_off","book","user","home","bag","flask",
  "cauldron","globe","trophy","sliders","repeat","x","check","chevron_right","chevron_down",
  "search","mail","map","plus","info","lock","fire","drop","clock","gift","dots","leaf","gem",
  "stop","settings","play","wind","mountain"];

const GLYPH_MAP = [
  ["✦", "star", "задания/ачивки (сейчас глиф в шапке)"],
  ["▲ + «▲N»", "trend_up + пилюля", "улучшения (кандидат на след. итерацию)"],
  ["♪", "volume / volume_off", "звук"],
  ["Ж", "book", "журнал"],
  ["⚡", "bolt", "эфир в строках и статусах"],
  ["↻ / ✕", "repeat / x", "BrewBar: повтор и сброс"],
  ["— (нет)", "flask cauldron globe home trophy sliders", "меню вкладок: иконки разделов (оставлено)"],
];

const CHECKLIST = [
  ["UX-08", "Дефолтный скин TabContainer, «Инструменты» на краю", "fixed", "pill-меню: круглое обрамление, текст и иконка по центру, 6 разделов помещаются на 540 px"],
  ["ICONS", "Иконок не было (глифы ✦ ▲ ♪ Ж, риск тофу)", "fixed", "сет 37 SVG 24×24 stroke 2 + вариант 16 px для вкладок; используется во вкладках, остальное — запас"],
  ["UX-01…07", "Шапка, строка ресурсов, бейджи", "fixed", "итерация-2, блок 1 (вариант A): иконки сета, тач 44×44, бейдж-пилюля, пузырь Светика не перекрывает кнопки"],  ["UX-12…16", "BrewBar: бейджи, ряд контролов, прогресс", "fixed", "итерация-2, блок 2 (вариант B): пилюли внутри орбов, «ВАРИТЬ» справа, «Стоп» без скачков вёрстки"],  ["UX-17…21", "Эксперимент: рамки, чипы, поиск", "keep", "ячейки выбора 4×N остаются КАК БЫЛО (решение приемки); изменений нет"],  ["UX-22…24", "Дом: disabled-CTA, кнопки выбора", "fixed", "итерация-2, блок 4: карточки категорий 2×N без ценников, чип «куплено: N», CTA постройки под превью"],  ["UX-25…27", "Попапы: действия, крестик, стек", "fixed", "итерация-2, блок 3: ОДНА кнопка по центру, без крестика (тап по фону), рецептная строка A+B→C, чипы, поля 24 px"],  ["UX-28…32", "Фокус, safe-area, скролл, motion", "rework", "не начинали; бэклог"],
  ["WORLD-5", "Мир и Рейтинг: простыни строк", "fixed", "итерация-2, блок 5: карточки списков, медаль топ-3, чип очков, своя строка закрепом, «Обновить» иконкой 44"],
];

const PALETTE = [
  ["BG0", "#0a0f16", "фон экрана"], ["BG1", "#121a24", "панели, дорожка вкладок"],
  ["BG2", "#18222e", "ховер вкладок"], ["BG3", "#0d141d", "поля ввода"],
  ["LINE", "#24313f", "рамка дорожки вкладок"], ["LINE_STRONG", "#35485c", "рамки полей"],
  ["INK1", "#eaf2f7", "основной текст"], ["INK2", "#a9b8c6", "неактивная вкладка"],
  ["INK3", "#7e8d9c", "приглушённый"], ["ACCENT", "#3ad6c6", "активная вкладка, фокус"],
  ["ACCENT_INK", "#052622", "текст на акценте"], ["GOLD", "#e9b44c", "награды"],
  ["GOLD_INK", "#241a05", "текст на золоте"], ["DANGER", "#e5705f", "ошибки"],
  ["SUCCESS", "#6fcf8e", "успех"], ["VIOLET", "#b49aff", "Светик"],
];

const ic = (n, s = 20) => `<span class="ic" style="--icon:url('../../assets/ui/icons/${n}.svg');width:${s}px;height:${s}px"></span>`;
const orb = (col, cnt) => `
  <span class="orb" style="background:radial-gradient(circle at 35% 30%, #ffffff40, transparent 45%), ${col}">
    ${cnt ? `<span class="cnt">${cnt}</span>` : ""}
  </span>`;

/* ---------- блоки экрана: всё как в текущей игре (после отката) ---------- */
function header(mode) {
  if (mode === "after") {
    // блок 1, вариант A: иконки, 44x44, бейдж-пилюля; цвета кнопок как в игре
    return `<div class="head">
      <div class="title">ПЕТЛЯ АЛХИМИКА</div>
      <button class="hbtn gold">${ic("star", 20)}</button>
      <button class="hbtn">${ic("trend_up", 20)}<span class="bnum">1</span></button>
      <button class="hbtn">${ic("volume", 20)}</button>
      <button class="hbtn">${ic("book", 20)}</button>
      <span class="orb" style="width:40px;height:40px;background:radial-gradient(circle at 35% 30%, #9fe8b0, #2f8f5b)"></span>
    </div>`;
  }
  return `<div class="head">
    <div class="title">ПЕТЛЯ АЛХИМИКА</div>
    <button class="hbtn gold">✦</button>
    <button class="hbtn">▲<span class="bnum">1</span></button>
    <button class="hbtn">♪</button>
    <button class="hbtn">Ж</button>
    <span class="orb" style="width:36px;height:36px;background:radial-gradient(circle at 35% 30%, #9fe8b0, #2f8f5b)"></span>
  </div>`;
}
function resrow() {
  return `<div class="resrow"><span class="val">⚡ Эфир: 120 / 230 &nbsp;·&nbsp; резерв: 0 &nbsp;·&nbsp; +1.05/с</span>
    <button class="wbtn gold">Дом</button><button class="wbtn teal">Лавка</button></div>
   <div class="subline">Веществ открыто: 11 / 57 &nbsp;·&nbsp; Рецептов: 7 / 53</div>
   <div class="questline">✦ Светик: Первая пара — 0/1</div>`;
}
const TABS = [["flask","Эксперимент"],["cauldron","Лаборатория"],["globe","Мир"],["home","Дом"],["trophy","Рейтинг"],["sliders","Инструменты"]];
function tabs(mode, active) {
  if (mode === "before") {
    return `<div class="tabs old">${TABS.map(([i, n], k) =>
      `<span class="tab${k === active ? " on" : ""}">${n}</span>`).join("")}</div>`;
  }
  return `<div class="tabs">${TABS.map(([i, n], k) =>
    `<span class="tab${k === active ? " on" : ""}">${ic(i, 16)}<span class="tl">${n}</span></span>`).join("")}</div>`;
}
const CELLS = [["#5aa7e8","Вода"],["#cee8ef","Воздух"],["#c4a47c","Земля"],["#e0764f","Огонь"],
               ["#a8e8ff","Лёд"],["#96d691","Росток"],["#ddd0a2","Пыль"],["#acc8e4","Туман"]];
function cells() {
  return `<div class="cells">${CELLS.map(([c, n]) =>
    `<span class="cell">${orb(c, 0)}<span class="cn">${n}</span></span>`).join("")}</div>`;
}

/* ---------- экраны ---------- */
function screenLab(mode) {
  return `<div class="screen">
    ${header(mode)}${resrow()}${tabs(mode, 1)}
    <div class="panel" style="flex:1">
      <div style="display:flex;align-items:center;gap:18px;justify-content:center;padding:14px 0 6px">
        <div style="text-align:center">${orb("#e0764f")}<div class="muted" style="font-size:11px;margin-top:4px">A</div></div>
        <div style="width:170px;height:110px;border-radius:0 0 85px 85px;background:linear-gradient(#4a5468,#333c4e);position:relative">
          <div style="position:absolute;top:-10px;left:-8px;right:-8px;height:26px;border-radius:50%;background:#5b6579"></div>
        </div>
        <div style="text-align:center">${orb("#5aa7e8")}<div class="muted" style="font-size:11px;margin-top:4px">B</div></div>
      </div>
      <div class="sect">Родник</div>
      <div style="display:flex;gap:14px;justify-content:center;padding:4px 0 8px">
        ${orb("#e0764f")}${orb("#5aa7e8")}${orb("#c4a47c")}${orb("#cee8ef")}
      </div>
      <div class="subline" style="font-size:13px">Каждые 6 с: +1 «Вода».</div>
      <div class="sect" style="color:#fff;font-size:16px;font-weight:400">Книга рецептов</div>
      <div class="inputwrap"><input class="input" placeholder="Поиск вещества по названию…"></div>
    </div>
    <div class="brewbar">
      <div class="brow">
        <button class="btn k0" style="min-width:48px;height:42px">Все</button>
        ${ORBS.map((o, i) => `<span class="orb src" style="background:radial-gradient(circle at 35% 30%, ${o.hi}, ${o.lo})">${i === 1 ? "◆" : "▲"}<span class="cnt${mode === "after" ? " in" : ""}">100</span></span>`).join("")}
        ${mode === "after"
          ? `<button class="btn k1" style="min-width:40px;height:42px">↻</button>
             <button class="btn k0" style="min-width:40px;height:42px">✕</button>
             <button class="btn k1" style="height:52px;padding:0 20px;font-size:15px;margin-left:auto">ВАРИТЬ</button>`
          : `<button class="btn k1" style="height:52px;padding:0 26px;font-size:16px">ВАРИТЬ</button>
             <button class="btn k1" style="min-width:34px;height:42px">↻</button>
             <button class="btn k0" style="min-width:34px;height:42px">✕</button>`}
      </div>
      <div class="prog"><i style="width:42%"></i></div>
      <div class="brow" style="margin-top:8px">
        <span class="bstatus">Перетащи ингредиенты в лунки или нажми «Варить».</span>
        ${mode === "after" ? `<button class="btn k1" style="min-width:76px;height:32px;opacity:.45" disabled>Стоп</button>` : ""}
      </div>
    </div>
  </div>`;
}

function screenExperiment(mode) {
  return `<div class="screen">
    ${header(mode)}${resrow()}${tabs(mode, 0)}
    <div style="display:flex;align-items:center;gap:10px">
      <div class="sect" style="flex:1;font-size:20px;color:#fff;font-weight:800">ЭКСПЕРИМЕНТ</div>
      <button class="btn k2" style="height:36px;padding:0 12px;font-size:13px">✦ Светик · 10 ⚡</button>
    </div>
    <div class="subline" style="font-size:13px">«Вода» в котле · выбери второй реагент.</div>
    <div class="panel double" style="flex:1">
      <div style="display:flex;align-items:center;gap:8px">
        <div style="flex:1;font-weight:700;font-size:14px">ВЫБРАТЬ ВТОРОЙ</div>
        <span class="muted" style="font-size:11px">8 / 11</span>
        <button class="btn k0" style="height:40px;padding:0 14px">Закрыть</button>
      </div>
      <div class="subline" style="font-size:12px">Нажми на ячейку — вещество сразу появится на поле.</div>
      <div class="inputwrap"><input class="input" placeholder="Найти второй реагент…"></div>
      <div class="chips">
        <button class="chip on">Недавние</button><button class="chip">Светик</button>
        <button class="chip">Стихии</button><button class="chip">Все</button>
      </div>
      ${cells()}
      <div class="subline" style="font-size:11px;text-align:center">Ячейки 4×N — как в текущей игре, без строк-таблиц.</div>
    </div>
  </div>`;
}

function screenHouse(mode) {
  const cats = [["Окно", 1], ["Ковёр", 3], ["Стул", 1], ["Растение", 1]];
  if (mode === "after") {
    // блок 4 согласован: карточки 2×N, без ценников, чип «куплено: N»
    return `<div class="screen">
      ${header(mode)}${resrow()}${tabs(mode, 3)}
      <div class="panel" style="flex:1;overflow:hidden">
        <div class="poptitle" style="font-size:22px;text-align:center">ДОМ СВЕТИКА</div>
        <div class="popsub" style="text-align:center">Уют, обстановка и произвольные цвета — видно другим игрокам.</div>
        <div class="housescene"><div class="fire"></div></div>
        <button class="btn k2 donecta" disabled>Домик построен ✓</button>
        <div class="sect" style="color:#fff;font-size:14px;font-weight:600">Обстановка</div>
        <div class="subline" style="font-size:12px">Коллекция: 12/90 · купленное ставится бесплатно</div>
        <div style="display:grid;grid-template-columns:1fr 1fr;gap:10px">
          ${cats.map(([nm, owned]) => `<div class="hcard">
            <div class="hthumb"><i></i></div>
            <div style="display:flex;align-items:center;gap:8px;margin-top:8px">
              <div style="flex:1"><b style="color:#eaf2f7;font-size:14px">${nm}</b><br>
                <span class="chip${owned ? "" : " mut"}">куплено: ${owned}</span></div>
              <button class="btn k1" style="height:40px;padding:0 14px;font-size:12px">Выбрать</button>
            </div>
          </div>`).join("")}
        </div>
      </div>
    </div>`;
  }
  const furn = [["🪟","Окно · 1/10","Классическое"],["🧶","Ковёр · 3/10","Восточный"],
                ["🪑","Стул · 1/10","Классический"],["🪴","Растение · 1/10","В горшке"]];
  return `<div class="screen">
    ${header(mode)}${resrow()}${tabs(mode, 3)}
    <div class="panel" style="flex:1;overflow:hidden">
      <div class="poptitle" style="font-size:22px;text-align:center">ДОМ СВЕТИКА</div>
      <div class="popsub" style="text-align:center">Уют, обстановка и произвольные цвета — видно другим игрокам.</div>
      <div class="housescene"><div class="fire"></div></div>
      <button class="btn k2 donecta" disabled>Домик построен ✓</button>
      <div class="sect" style="color:#fff;font-size:14px;font-weight:400">Обстановка</div>
      <div class="subline" style="font-size:12px">Коллекция: 12/90 · купленное ставится бесплатно</div>
      ${furn.map(([e, nm, v]) => `<div class="furnrow">
        <span class="thumb" style="font-size:20px">${e}</span><span class="nm">${nm}</span>
        <button class="btn k1" style="height:44px;padding:0 18px">${v} ✓</button>
      </div>`).join("")}
    </div>
  </div>`;
}

function screenPopup(mode) {
  if (mode === "after") {
    // согласовано: иконка+заголовок слева, орб 96, рецептная строка, чипы,
    // ОДНА кнопка по центру, без крестика (закрытие — тап по фону/карточке)
    return `<div class="screen">
      ${header(mode)}${resrow()}${tabs(mode, 1)}
      <div class="panel" style="flex:1"></div>
      <div class="dim"><div class="popcard" style="width:360px;padding:24px">
        <div style="display:flex;align-items:center;gap:10px">${ic("flask", 22, "#59d9d2")}
          <div class="poptitle" style="font-size:20px;margin:0">НОВЫЙ РЕЦЕПТ!</div></div>
        <div style="display:flex;justify-content:center;margin:14px 0">${orb("#96d691", 96)}</div>
        <div style="display:flex;justify-content:center;align-items:center;gap:8px">
          ${orb("#e0764f", 32)}<span class="muted">+</span>${orb("#96d691", 32)}<span class="muted">→</span>${orb("#ff9d64", 32)}
          <b style="color:#eaf2f7">Цветок</b></div>
        <div style="display:flex;justify-content:center;gap:8px;margin:12px 0">
          <span class="chip">Обычный</span><span class="chip gold">+12 ⚡ награда</span></div>
        <div class="popsub">автор: redrad1sh</div>
        <div class="popactions" style="justify-content:center">
          <button class="btn k1" style="width:200px;height:48px">Забрать</button>
        </div>
      </div></div>
    </div>`;
  }
  return `<div class="screen">
    ${header(mode)}${resrow()}${tabs(mode, 1)}
    <div class="panel" style="flex:1"></div>
    <div class="dim"><div class="popcard">
      <div class="poptitle">НОВЫЙ РЕЦЕПТ!</div>
      <div style="display:flex;justify-content:center">${orb("#96d691")}</div>
      <div class="popsub">Огонь + Росток → Цветок<br>+12 эфира</div>
      <div class="popactions">
        <button class="btn k2">Забрать</button>
        <button class="btn k0">Закрыть</button>
      </div>
    </div></div>
  </div>`;
}

function screenRating(mode) {
  const rows = [["redrad1sh", 41, 1280], ["mira", 33, 990], ["alx", 27, 860], ["ты", 11, 340]];
  if (mode === "after") {
    return `<div class="screen">
      ${header(mode)}${resrow()}${tabs(mode, 4)}
      <div class="panel" style="flex:1;overflow:hidden">
        <div class="poptitle" style="font-size:20px;text-align:center">РЕЙТИНГ ИГРОКОВ</div>
        <div class="popsub" style="text-align:center">Кто сколько открыл — и чей домик можно посмотреть.</div>
        <div class="mechip">Ты: 14 место · 11 открытий · 340 ⚡</div>
        ${rows.map(([nm, d, p], i) => `<div class="rtcard${nm === "ты" ? " me" : ""}">
          <span class="rk${i < 3 ? " m" + i : ""}">${i + 1}</span>
          <span class="orb" style="width:28px;height:28px;background:radial-gradient(circle at 35% 30%, #9fe8b0, #2f8f5b)"></span>
          <span style="flex:1"><b style="color:#eaf2f7;font-size:14px">${nm}</b><br>
            <span class="muted" style="font-size:11px">${d} открытий</span></span>
          <span class="chip gold">${p} ⚡</span></div>`).join("")}
        <div style="display:flex;align-items:center;gap:8px;margin-top:8px">
          <span class="muted" style="font-size:12px;flex:1">Первооткрытия · вещества · очки целей</span>
          <button class="btn k1" style="min-width:44px;height:40px">${ic("repeat", 18)}</button></div>
      </div>
    </div>`;
  }
  return `<div class="screen">
    ${header(mode)}${resrow()}${tabs(mode, 4)}
    <div class="panel" style="flex:1;overflow:hidden">
      <div class="poptitle" style="font-size:20px;text-align:center">РЕЙТИНГ ИГРОКОВ</div>
      <div class="popsub" style="text-align:center">Кто сколько открыл — и чей домик можно посмотреть.</div>
      <div class="popsub" style="text-align:center;color:#f5e5bf">Ты: 14 место · 11 открытий · 340 очков</div>
      <div class="popsub" style="text-align:center">Первооткрытия · вещества · очки целей</div>
      <button class="btn k1" style="width:100%;height:40px;margin:8px 0">Обновить</button>
      ${rows.map(([nm, d, p], i) => `<div class="muted" style="font-size:14px;color:#e8f1f8;padding:5px 0">${i + 1}. ${nm} — ${d} открытий, ${p} очков</div>`).join("")}
    </div>
  </div>`;
}

function screenWorld(mode) {
  if (mode === "after") {
    return `<div class="screen">
      ${header(mode)}${resrow()}${tabs(mode, 2)}
      <div class="panel" style="flex:1;overflow:hidden">
        <div class="sect" style="color:#eaf2f7;font-size:20px;font-weight:800">Мир живых открытий</div>
        <div class="muted" style="font-size:13px">Связь установлена · 57 веществ в мире</div>
        <div class="chalcard">${ic("trophy", 20, "#ffd96e")}
          <span style="flex:1"><b style="color:#eaf2f7;font-size:13px">Цель дня: вещество из «Родник»</b><br>
          <span class="chip gold">+25 ⚡</span></span></div>
        <div class="sect" style="color:#59e0d6;font-size:15px">Свежие открытия</div>
        ${[["mira", "Пар", "2 мин"], ["alx", "Кирпич", "9 мин"], ["redrad1sh", "Сталь", "21 мин"]].map(([n, it, ago]) =>
          `<div class="feedcard"><span class="orb" style="width:24px;height:24px;background:radial-gradient(circle at 35% 30%, #b7f0b9, #6fbf72)"></span>
           <span style="flex:1;color:#cfd8e0;font-size:12px">${n} открыл «${it}»</span>
           <span class="muted" style="font-size:11px">${ago}</span></div>`).join("")}
        <div class="sect" style="color:#eaf2f7;font-size:15px">Все вещества</div>
        <div class="inputwrap"><input class="input" placeholder="Поиск по миру: имя, id, автор…"></div>
        ${[["Пар", "mira"], ["Кирпич", "alx"]].map(([n, a]) => `<div class="wcard">
          <span class="orb" style="width:32px;height:32px;background:radial-gradient(circle at 35% 30%, #b7f0b9, #6fbf72)"></span>
          <span style="flex:1"><b style="color:#eaf2f7;font-size:14px">${n}</b><br>
          <span class="muted" style="font-size:11px">автор: ${a}</span></span>${ic("chevron_right", 14)}</div>`).join("")}
      </div>
    </div>`;
  }
  return `<div class="screen">
    ${header(mode)}${resrow()}${tabs(mode, 2)}
    <div class="panel" style="flex:1;overflow:hidden">
      <div class="sect" style="color:#eaf2f7;font-size:20px;font-weight:800">Мир живых открытий</div>
      <div class="muted" style="font-size:14px">Связь установлена · 57 веществ в мире</div>
      <div class="sect" style="color:#ffd96e;font-size:16px">Гонка первооткрытий</div>
      <div style="color:#f5e5bf;font-size:13px">Цель дня: вещество из «Родник» · награда 25 ⚡</div>
      <div class="sect" style="color:#8cf2e8;font-size:16px">Свежие открытия</div>
      <div class="muted" style="font-size:12px;color:#c4cdd6">mira открыла «Пар» · 2 мин назад<br>alx открыл «Кирпич» · 9 мин назад</div>
      <div class="sect" style="color:#eaf2f7;font-size:18px">Все вещества</div>
      <div class="inputwrap"><input class="input" placeholder="Поиск по миру: имя, id, автор…"></div>
      <div style="color:#e8f1f8;font-size:14px;padding:4px 0">Пар · автор mira<br>Кирпич · автор alx</div>
    </div>
  </div>`;
}

const SCREENS = [["lab", "Лаборатория", screenLab], ["exp", "Эксперимент", screenExperiment],
  ["house", "Дом", screenHouse], ["popup", "Попап", screenPopup],
  ["rating", "Рейтинг", screenRating], ["world", "Мир", screenWorld]];

/* ---------- views ---------- */
const content = document.getElementById("content");
let view = "screens", screenKey = "lab", mode = "after";

function phone(modeName, screenFn, scale) {
  return `<div class="phone-wrap">
    <div class="phone-label">${modeName === "before" ? "До · дефолтные вкладки Godot" : "После · pill-меню с иконками"}</div>
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
    </div>
    <p class="lead" style="margin-top:14px">После отката итерации-1 режимы отличаются только меню вкладок:
      остальной UI показан ровно таким, какой он сейчас в игре (ячейки в Эксперименте, прежняя шапка и BrewBar).</p>`;
  content.querySelectorAll("[data-screen]").forEach(b =>
    b.onclick = () => { screenKey = b.dataset.screen; render(); });
}

function renderIcons() {
  content.innerHTML = `
    <div class="h2">Икон-сет «Atheneum» (оставлен)</div>
    <p class="lead">37 SVG: сетка 24×24, stroke 2, round cap/join, база белая (в Godot тонируется modulate,
      здесь — CSS mask). Есть вариант 16 px для меню вкладок (<code>assets/ui/icons16/</code>).
      Генератор: <code>tools/make_icons.py</code>.</p>
    <div class="grid icon-grid">
      ${ICONS.map(n => `<div class="icon-cell">${ic(n, 24)}<span class="nm">${n}</span></div>`).join("")}
    </div>
    <div class="h3">Где применяется сейчас и кандидаты на замену глифов</div>
    <table class="check-table"><tr><th>Глиф сейчас</th><th>Иконка сета</th><th>Назначение</th></tr>
    ${GLYPH_MAP.map(([a, b, c]) => `<tr><td style="color:#e5705f">${a}</td><td style="color:#6fcf8e">${b}</td><td class="muted">${c}</td></tr>`).join("")}
    </table>`;
}

function renderTokens() {
  content.innerHTML = `
    <div class="h2">Токены (справочно для итерации-2)</div>
    <p class="lead">После отката в игре используются только цвета вкладок (ACCENT/INK/BG/LINE) и кегль 11 SemiBold.
      Остальная палитра — задел на следующий заход редизайна.</p>
    <div class="grid" style="grid-template-columns:repeat(auto-fill,minmax(320px,1fr))">
      ${PALETTE.map(([n, h, u]) => `<div class="swatch"><span class="chipcol" style="background:${h}"></span>
        <span><span class="nm">${n}</span><br><span class="hex">${h}</span></span>
        <span class="use">${u}</span></div>`).join("")}
    </div>`;
}

function renderComponents() {
  const strip = (m) => `
    <div class="stack">
      ${tabs(m, 1)}
      <div style="display:flex;gap:10px;align-items:center">
        ${ic("flask", 24)}${ic("cauldron", 24)}${ic("globe", 24)}${ic("home", 24)}${ic("trophy", 24)}${ic("sliders", 24)}
      </div>
    </div>`;
  content.innerHTML = `
    <div class="h2">Меню вкладок: до и после</div>
    <p class="lead">Единственный изменённый компонент игры. Было: прямоугольники Godot с рамкой, текст 14 px,
      «Инструменты» на краю. Стало: пилюля-дорожка, круглое обрамление активной вкладки, иконка 16 px +
      текст 11 px SemiBold по центру, все 6 разделов внутри 540 px.</p>
    <div class="cmp">
      <div class="col"><h4>До</h4><div class="phone" data-mode="before"
        style="position:relative;inset:auto;transform:none;width:auto;height:auto;border:0;border-radius:12px;padding:14px;
        display:flex;flex-direction:column;gap:12px;background:var(--bg0)">${strip("before")}</div></div>
      <div class="col"><h4>После</h4><div class="phone" data-mode="after"
        style="position:relative;inset:auto;transform:none;width:auto;height:auto;border:0;border-radius:12px;padding:14px;
        display:flex;flex-direction:column;gap:12px;background:var(--bg0)">${strip("after")}</div></div>
    </div>`;
}

function renderChecklist() {
  const cnt = (s) => CHECKLIST.filter(c => c[2] === s).length;
  content.innerHTML = `
    <div class="h2">Итоги приемки: итерация-1 + итерация-2</div>
    <p class="lead">Принято и оставлено: <b style="color:#6fcf8e">${cnt("fixed")}</b> (меню вкладок, сет иконок).
      Откачено на приемке итерации-1 и позже переделано по согласованным мокам: блоки 1–5 итерации-2
      (шапка, BrewBar, попапы, дом, мир/рейтинг). Эксперимент не тронут по вашему решению (ячейки 4×N).
      Каждый блок: мок-кадр в ветке → ваше «ок» → изолированный коммит → синхронизация превью.</p>
    <table class="check-table">
      <tr><th style="width:90px">ID</th><th>Блок</th><th style="width:100px">Статус</th><th>Решение</th></tr>
      ${CHECKLIST.map(([id, t, s, f]) => `<tr><td><b>${id}</b></td><td>${t}</td>
        <td><span class="pill ${s === "fixed" ? "fixed" : s === "rework" ? "partial" : "backlog"}">${
          s === "fixed" ? "оставлено" : s === "rework" ? "откат" : "бэклог"}</span></td>
        <td class="muted">${f}</td></tr>`).join("")}
    </table>`;
}

function fitTabs() {
  document.querySelectorAll('.phone[data-mode="after"] .tabs').forEach(t => {
    t.classList.remove("tight", "tighter");
    if (t.scrollWidth > t.clientWidth + 1) {
      t.classList.add("tight");
      if (t.scrollWidth > t.clientWidth + 1) t.classList.add("tighter");
    }
  });
}

function render() {
  document.body.dataset.mode = mode === "before" ? "before" : "after";
  document.getElementById("m-before").classList.toggle("on", mode === "before");
  document.getElementById("m-after").classList.toggle("on", mode === "after");
  document.getElementById("m-both").classList.toggle("on", mode === "both");
  document.getElementById("meta-line").textContent =
    view === "screens" ? `экран: ${SCREENS.find(s => s[0] === screenKey)[1]} · ${mode === "both" ? "сравнение" : mode === "before" ? "ДО" : "ПОСЛЕ"}` : "";
  ({ screens: renderScreens, icons: renderIcons, tokens: renderTokens,
     components: renderComponents, checklist: renderChecklist })[view]();
  requestAnimationFrame(fitTabs);
}

document.querySelectorAll(".nav").forEach(b => b.onclick = () => {
  document.querySelectorAll(".nav").forEach(x => x.classList.remove("on"));
  b.classList.add("on"); view = b.dataset.view; render();
});
document.getElementById("m-before").onclick = () => { mode = "before"; render(); };
document.getElementById("m-after").onclick = () => { mode = "after"; render(); };
document.getElementById("m-both").onclick = () => { mode = "both"; render(); };
document.addEventListener("keydown", (e) => {
  if (e.key === "b") { mode = "both"; render(); }
  if (e.key === "1") { mode = "before"; render(); }
  if (e.key === "2") { mode = "after"; render(); }
});
render();
})();
