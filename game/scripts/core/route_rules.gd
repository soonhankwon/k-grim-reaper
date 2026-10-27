class_name RouteRules
extends RefCounted
## Pure route interpretation; the authored paths determine encounter and reward order.

static func enabled(state: Dictionary) -> bool:
	return not state.config.get("routes", []).is_empty()

static func find(config: Dictionary, route_id: String) -> Dictionary:
	for route: Dictionary in config.routes:
		if route.id == route_id: return route
	return {}

static func current(state: Dictionary) -> Dictionary:
	if not enabled(state): return {}
	return state.config.routes[0] if state.route.choice.is_empty() else find(state.config, state.route.choice)

static func step(state: Dictionary) -> int:
	return int(state.route.step) if enabled(state) else int(state.encounter)

static func last(state: Dictionary) -> bool:
	return step(state) >= state.config.encounters.size() - 1

static func offer(state: Dictionary) -> Dictionary:
	if last(state): return {}
	if enabled(state):
		var route := current(state)
		if route.is_empty(): return {}
		return state.config.reward_definitions.get(route.rewards[step(state)], {})
	return state.config.reward_offers.get(state.config.encounters[state.encounter].id, {})
