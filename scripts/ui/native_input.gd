extends Node
## Native keyboard on the web build.
##
## Godot's own virtual keyboard is unreliable on phones, so tapping a text field
## drops a real HTML <input> over the page: the phone then opens its normal
## keyboard, IME included, and whatever is typed is mirrored back into the
## LineEdit. Desktop and native builds simply do nothing.

const INPUT_ID := "gd-text-input"

var _fields := {}
var _active: LineEdit = null
var _clock := 0.0


func available() -> bool:
	return OS.has_feature("web")


func attach(field: LineEdit, hint: String = "") -> void:
	if not available():
		return
	_fields[field] = hint
	field.gui_input.connect(func(event: InputEvent) -> void:
		if event is InputEventMouseButton and (event as InputEventMouseButton).pressed:
			open(field)
		elif event is InputEventScreenTouch and (event as InputEventScreenTouch).pressed:
			open(field))


func open(field: LineEdit) -> void:
	if not available():
		field.grab_focus()
		return
	_active = field
	_clock = 0.0
	var hint := String(_fields.get(field, ""))
	if hint == "":
		hint = field.placeholder_text
	JavaScriptBridge.eval(
		"(function(value, hint) {" +
		"  var el = document.getElementById('%s');" % INPUT_ID +
		"  if (!el) {" +
		"    el = document.createElement('input');" +
		"    el.id = '%s';" % INPUT_ID +
		"    el.type = 'text';" +
		"    el.setAttribute('autocapitalize', 'off');" +
		"    el.setAttribute('autocorrect', 'off');" +
		"    el.setAttribute('spellcheck', 'false');" +
		"    el.style.cssText = 'position:fixed;left:6%;width:88%;top:8px;height:46px;" +
		"z-index:2147483647;font-size:18px;padding:0 12px;border-radius:10px;" +
		"border:2px solid #8f7fac;background:#14101f;color:#f2e9ff;box-sizing:border-box';" +
		"    document.body.appendChild(el);" +
		"  }" +
		"  el.value = value;" +
		"  el.placeholder = hint;" +
		"  el.style.display = 'block';" +
		"  el.focus();" +
		"  el.click();" +
		"})(%s, %s);" % [JSON.stringify(field.text), JSON.stringify(hint)],
		true)


## Copies whatever the HTML field holds into the LineEdit and hides it.
func close(field: LineEdit = null) -> void:
	var target := field if field != null else _active
	if target != null and available():
		var text := _peek()
		if text != "":
			target.text = text
	if available():
		JavaScriptBridge.eval(
			"(function(){var el = document.getElementById('%s');" % INPUT_ID +
			"if (el) { el.blur(); el.style.display = 'none'; }})();", true)
	_active = null


func _peek() -> String:
	var value: Variant = JavaScriptBridge.eval(
		"(function(){var el = document.getElementById('%s');" % INPUT_ID +
		"return el ? el.value : '';})()", true)
	return "" if value == null else str(value)


func _process(delta: float) -> void:
	if _active == null:
		return
	_clock += delta
	if _clock < 0.15:
		return
	_clock = 0.0
	var text := _peek()
	if text != _active.text:
		_active.text = text


func _exit_tree() -> void:
	if available():
		JavaScriptBridge.eval(
			"(function(){var el = document.getElementById('%s');" % INPUT_ID +
			"if (el) { el.remove(); }})();", true)
