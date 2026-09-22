extends Node
# Центральная шина событий. UI подписывается, логика эмитит.

signal energy_changed(value: float)
signal genome_changed(ids: Array)
signal stage_changed(old_index: int, new_index: int)
signal offline_gained(amount: float, seconds: int)
signal toast_requested(text: String)
signal creature_pet
