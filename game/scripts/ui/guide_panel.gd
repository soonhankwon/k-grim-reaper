class_name GuidePanel
extends PanelContainer
## Contextual instructions use only the currently presented snapshot.

var heading: Label
var body: Label
var footer: Label

func _ready() -> void:
	position = Vector2(974, 76)
	size = Vector2(272, 250)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.bg_color = Color("242a2b")
	style.border_color = Color("8b7955")
	style.set_border_width_all(2)
	style.content_margin_left = 16
	style.content_margin_right = 16
	style.content_margin_top = 14
	style.content_margin_bottom = 14
	add_theme_stylebox_override("panel", style)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 9)
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(column)
	heading = _label(19, Color("e0bb74"))
	body = _label(15, Color("ecdfbf"))
	footer = _label(12, Color("a6cbb3"))
	column.add_child(heading)
	column.add_child(body)
	column.add_child(footer)

func _label(font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label

func refresh(view: Dictionary, busy: bool, blocked: bool) -> void:
	if blocked:
		heading.text = "저장 확인"
		body.text = "진행이 잠겼습니다. 저장 파일에 대한 안내를 확인하세요."
		footer.text = "기존 저장은 자동으로 덮어쓰지 않습니다."
		return
	match view.phase:
		"packing":
			heading.text = "보따리 준비"
			body.text = "물건을 끌거나 선택한 뒤 빈칸을 눌러 배치하세요.\n\n물건마다 표시된 범위에 따라 효과가 달라질 수 있습니다."
			footer.text = "R 회전 · Ctrl+Z 되돌리기\n물건에 마우스를 올려 효과 확인"
		"battle":
			heading.text = "전투 중"
			body.text = "보따리의 물건을 눌러 사용하세요. 기력과 턴당 사용 횟수를 확인하세요.\n\n적의 다음 행동을 보고 턴을 끝내세요."
			footer.text = "배치는 전투가 끝난 뒤 바꿀 수 있습니다."
			if not EventRules.resolution(view).is_empty() and view.get("event", {}).get("status", "") in ["carried", "left"]:
				footer.text = "유품을 보따리에 가지고 있다면 오른쪽 버튼으로 이야기를 들을 수 있습니다."
		"reward":
			heading.text = "보상과 정리"
			if view.reward.selected.is_empty():
				body.text = "아래에서 보상을 고르세요. 선택한 물건이 보관대에 나타납니다.\n\n보따리에 넣은 뒤 보상 확정을 누르세요."
			else:
				body.text = "선택한 보상을 보따리에 넣은 뒤 보상 확정을 누르세요.\n\n자리가 부족하면 기존 물건을 꺼낼 수 있습니다."
			footer.text = "확정 전에는 후보 변경 또는 건너뛰기가 가능합니다."
		"victory":
			heading.text = "길이 열렸습니다"
			body.text = "다음 길목에 앞서 물건을 다시 배치할 수 있습니다.\n\n준비가 끝나면 오른쪽 버튼을 누르세요."
			footer.text = "보따리에 넣은 물건은 다음 전투에서 사용할 수 있습니다."
		"event":
			heading.text = "길가의 선택"
			body.text = "유품은 보관대에 둔 채로 챙길 수 있습니다. 그 자리에 둘 수도 있습니다." if EventRules.resolution(view).get("allow_stash", false) else "유품을 챙기려면 보따리에 넣고 확정하세요. 그 자리에 둘 수도 있습니다."
			footer.text = "다음 만남에서 보따리에 넣고 있어야 유품을 보여 줄 수 있습니다."
		"event_result":
			heading.text = "선택의 결과"
			body.text = "이번 선택의 결과를 확인하고 사건을 마치세요."
			footer.text = "사건을 마치면 이번 인도가 끝납니다." if not EventRules.resolution(view).is_empty() else "이후 보상을 받고 길을 이어갑니다."
		"route":
			heading.text = "갈림길"
			body.text = "아래 두 길의 다음 적과 첫 행동을 비교하세요.\n\n원하는 길을 누르면 다음 길목으로 이동합니다."
			footer.text = "선택은 확정 시 저장됩니다."
		"defeat":
			heading.text = "다시 준비하기"
			body.text = "이번 인도는 여기까지입니다. 배치와 방어 방법을 바꿔 다시 도전해 보세요."
			footer.text = "오른쪽 버튼으로 새 인도를 시작합니다."
		"complete":
			heading.text = "인도 완료"
			body.text = "이번 인도를 마쳤습니다. 다른 배치나 경로로 다시 도전해 보세요." if not EventRules.resolution(view).is_empty() else "세 길목을 통과했습니다. 다른 배치나 경로로 다시 연습해 보세요."
			footer.text = "오른쪽 버튼으로 새 인도를 시작합니다."
	if busy: footer.text = "행동 결과를 재생 중입니다. 건너뛰기를 사용할 수 있습니다."
