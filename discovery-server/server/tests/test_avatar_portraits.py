import importlib.util
import json
from pathlib import Path


def test_approved_generator_reference_vectors():
    module_path = Path(__file__).resolve().parents[1] / 'avatar.py'
    assert module_path.exists(), 'native portrait generator replaces glyph specs'
    module_spec = importlib.util.spec_from_file_location('portrait_avatar', module_path)
    module = importlib.util.module_from_spec(module_spec)
    module_spec.loader.exec_module(module)
    fixture = Path(__file__).resolve().parents[3] / 'alchemists-loop/tests/avatar_reference.json'
    cases = json.loads(fixture.read_text(encoding='utf-8'))['cases']
    for case in cases:
        assert module.portrait_spec(case['seed'], case['gender']) == case['spec']
    for gender, pool in [('male', {'cinder', 'glass', 'salt'}), ('female', {'herbalist', 'night', 'copper'})]:
        specs = [module.portrait_spec(str(i), gender) for i in range(100)]
        assert {spec['archetype'] for spec in specs} == pool
        assert len({json.dumps(spec, sort_keys=True) for spec in specs}) == 100
