"""Small dependency guard for combat layering; behavior is covered by Godot tests."""
from pathlib import Path
import re

root = Path(__file__).resolve().parent.parent
violations = []
# Authored item/tag identities belong to content, never engine/UI branches.
content_ids = {'sword', 'seal', 'lantern', 'ring', 'hat', 'bell', 'yakgwa',
               'rope', 'sandals', 'order', 'coin', 'mirror', 'weapon', 'keepsake', 'talisman'}
for path in sorted((root / 'game/scripts').rglob('*.gd')):
    code = '\n'.join(line for line in path.read_text().splitlines() if not line.lstrip().startswith('#'))
    relative = path.relative_to(root).as_posix()
    literals = set(re.findall(r'[\"\']([a-z][a-z0-9_]*)[\"\']', code))
    identity_literals = literals & content_ids
    if identity_literals:
        violations.append(f'{relative}: Authored content IDs in code: {sorted(identity_literals)}')
    rules = [(r'\bawait\b', 'Runtime timing belongs to ActionQueue, not await chains.')]
    if 'scripts/core/' in relative:
        rules += [
            (r'\b(?:get_tree|create_tween|create_timer|call_deferred)\s*\(', 'Core must not schedule scene work.'),
            (r'extends\s+(?:Node\w*|Control|CanvasItem)\b', 'Core must remain scene-independent.'),
            (r'\b(?:ActionQueue|CombatPlayback|BattleSession)\b', 'Core cannot depend on application/playback.'),
        ]
    if path.name in {'combat_simulator.gd', 'inventory_rules.gd', 'effect_applier.gd', 'grid_rules.gd', 'reward_rules.gd', 'route_rules.gd', 'event_rules.gd'}:
        rules += [(r'\bsignal\s+\w+|\b(?:load|preload|randf|randi|randomize)\s*\(', 'Pure rules use value inputs only.')]
    if path.name in {'item_data.gd', 'effect_unit.gd'}:
        rules += [(r'\bfunc\s+|\bsignal\s+', 'Content Resources contain fields only, never behavior.')]
    if 'scripts/playback/' in relative:
        rules += [(r'\b(?:CombatResolver|CombatSimulator|InventoryModel|BattleSession)\b', 'Playback may not access simulation or canonical models.')]
    if 'scripts/ui/' in relative:
        rules += [
            (r'\bCombatResolver\b|\bCombatSimulator\.resolve\s*\(', 'UI commands must go through BattleSession.'),
            (r'\.state_snapshot\s*\(', 'UI must render the presentation snapshot.'),
            (r'\binventory\.(?:place|move_to_stash|undo|add_item)\s*\(', 'Gameplay layout mutations must be persisted through BattleSession.'),
        ]
    for pattern, reason in rules:
        if re.search(pattern, code):
            violations.append(f'{relative}: {reason}')
if violations:
    raise SystemExit('\n'.join(violations))
print('ARCHITECTURE: PASS')
