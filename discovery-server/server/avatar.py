import unicodedata

TYPES_BY_GENDER = {
    'male': ('cinder', 'glass', 'salt'),
    'female': ('herbalist', 'night', 'copper'),
}
MASK = 0xffffffff


def portrait_spec(seed: str, gender: str = 'male') -> dict:
    pool = TYPES_BY_GENDER[gender]
    h = 2166136261
    for char in unicodedata.normalize('NFC', gender + ':' + seed):
        h = ((h ^ ord(char)) * 16777619) & MASK

    def pick(n):
        nonlocal h
        h = (h + 0x6D2B79F5) & MASK
        t = ((h ^ (h >> 15)) * (h | 1)) & MASK
        t ^= (t + (((t ^ (t >> 7)) * (t | 61)) & MASK)) & MASK
        return ((t ^ (t >> 14)) & MASK) * n // 4294967296

    archetype = pool[pick(3)]
    prefix = {'night': 'hood', 'salt': 'cap'}.get(archetype, archetype)
    return {
        'gender': gender, 'archetype': archetype,
        'face': pick(3), 'hairStyle': prefix + '-' + str(pick(3)),
        'expression': pick(4), 'nose': pick(3), 'accessory': pick(4),
        'outfit': pick(3), 'palette': pick(6), 'skin': pick(6),
        'hairColor': pick(6), 'detail': pick(3),
    }
