# Промпт для замены музыки в тизере (60с)

Целевая структура — под раскадровку тизера. Критично: **большой импакт ровно на 0:50**,
финальный аккорд/фанфара на **0:57.5**, чистое окончание к **1:00**.

---

## 1) Suno / Udio (Custom, Instrumental ON) — style prompt

```
Dark mystical fantasy electronic trailer, 100 BPM, D minor, instrumental.
Alchemy vibe: deep sub drone and sparse music-box plucks open; a soft heartbeat
kick grows into a warm four-on-the-floor groove with plucked synth arps;
middle section thins to gentle celesta bells (cozy, offline calm); then a
16th-note arp build with a white-noise riser into a MASSIVE half-time impact
at 0:50 — epic orchestral hit, glowing pads, magical shimmer; triumphant but
cozy outro with soft fanfare horns; clean ending at 1:00. Warm, enchanted,
bassy, video-game teaser. No vocals.
```

### Structure-теги (в поле lyrics, Instrumental):

```
[Intro: dark sub drone D, distant chimes, sparkle]
[Build 0:07: heartbeat kick, music-box plucks]
[Groove 0:15: warm bass, four-on-floor, synth arps]
[Break 0:32: celesta bells only, gentle, magical]
[Riser 0:41: rising 16th arps, noise sweep, drums mute at 0:47]
[Drop 0:50: half-time, orchestral impact, epic warm pads]
[Outro 0:55: soft fanfare, shimmer, clean end at 1:00]
```

## 2) Stable Audio / MusicGen / Kling Sound (один абзац)

```
Dark enchanting fantasy game-trailer music, 100 BPM, D minor, instrumental:
deep sub-bass drone with sparse music-box plucks, heartbeat kick building into
a warm four-on-the-floor groove with plucked synth arps, a gentle celesta-bell
middle section, then a rising arp build and noise riser into a huge half-time
orchestral impact at 50 seconds, epic warm pads and soft horn fanfare outro,
ending cleanly at 60 seconds. Cinematic, magical, cozy, bassy.
```

## 3) Русская версия (если генератор понимает RU)

```
Тёмная мистическая электроника для игрового тизера, 100 BPM, ре минор, без вокала.
Глубокий саб-дрон и редкие «музыкально-шкатулочные» пиццикато; мягкий хартбит-кик
перерастает в тёплый грув с арпеджио; середина — нежные колокольчика челесты;
затем билд на 16-х и шумовой райзер в огромный полутактовый импакт на 50-й секунде,
эпичные тёплые пэды и мягкая фанфара в конце, чистое завершение на 60-й секунде.
Кинематографично, волшебно, уютно.
```

---

## Карта таймингов (что где должно произойти)

| Время | Сцена тизера | Что в музыке |
|---|---|---|
| 0:00–0:05 | искра в кольце | тёмный дрон, редкие блики |
| 0:05.2 | склейка → Эксперимент | мягкий акцент |
| 0:08.5 | орбы в котёл | перкуссия/хартбит ок |
| 0:13.5 | склейка → Мир | новый элемент (арп/грув) |
| 0:22.0 | поп Светика | акцент |
| 0:32.0 | офлайн-секция | снять биты, нежно (колокольчика) |
| 0:41.4 | склейка → Редкость | билд |
| 0:47–0:50 | легендарка | райзер, барабаны молчат |
| **0:50.0** | **финальный импакт** | **БОЛЬШОЙ дроп/хит** |
| 0:57.5 | лого+CTA | фанфара/финальный аккорд |
| 1:00 | конец | тишина, чистый хвост |

## Как поменять (я сделаю остальное)

1. Сгенерируй трек (лучше 60–75с), скачай WAV/MP3.
2. Скажи мне время дропа (если знаешь) — или я сам найду его по энергии
   (onset-детект) и сдвину трек так, чтобы дроп встал ровно на 0:50.
3. Я пересоберу микс (SFX игры лягут поверх) и перемонтирую видео —
   кадры рендерить заново не нужно, замена только аудиодорожки.

Файл положить как `teaser/audio/music.wav` (любой формат — сконвертирую).
