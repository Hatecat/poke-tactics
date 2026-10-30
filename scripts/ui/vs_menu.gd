extends Control
## Pantalla del modo VS: apodo y equipo, alojar o unirse por IP y la sala con el rival (ping, tablero que elige
## el anfitrión y "¡Listo!"). Cuando los dos están listos, el anfitrión manda "start" (VsMatch) y empieza el combate.

var _nick_edit: LineEdit
var _team_select: OptionButton
var _team_hint: Label
var _port_edit: LineEdit
var _ip_edit: LineEdit
var _join_port_edit: LineEdit
var _connect_box: VBoxContainer
var _status: RichTextLabel
var _cancel_button: Button
var _room: PanelContainer
var _rival_label: RichTextLabel
var _board_box: VBoxContainer
var _board_hint: Label
var _topology_select: OptionButton
var _biome_select: OptionButton
var _ready_button: Button
var _ready_label: Label
## Equipo propio tal como se mandó en "ready" (el "start" del anfitrión debe traerlo igual).
var _my_team_data: Array = []
var _ready_sent := false
var _their_team_data: Variant = null
var _ping_left := 0.0


func _ready() -> void:
	theme = UiKit.theme()
	set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(UiKit.background())
	Audio.music("menu")
	Audio.ambience("")
	Game.mode = "quick"
	Game.vs = {}
	var root := VBoxContainer.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.offset_left = 16
	root.offset_top = 16
	root.offset_right = -16
	root.offset_bottom = -16
	root.add_theme_constant_override("separation", 12)
	add_child(root)
	root.add_child(UiKit.screen_header(tr("Combate VS"), tr("← Menú"), _back))
	var center := CenterContainer.new()
	center.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(center)
	var cols := HBoxContainer.new()
	cols.add_theme_constant_override("separation", 24)
	center.add_child(cols)
	cols.add_child(_build_setup())
	_room = _build_room()
	cols.add_child(_room)
	Net.connected.connect(_refresh)
	Net.opponent_found.connect(_on_opponent)
	Net.opponent_left.connect(_on_opponent_left)
	Net.failed.connect(_on_failed)
	Net.message.connect(_on_message)
	_refresh()


## Columna izquierda: apodo, equipo y conexión.
func _build_setup() -> PanelContainer:
	var panel := UiKit.panel()
	panel.custom_minimum_size.x = 560
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	panel.add_child(box)

	box.add_child(UiKit.section(tr("Tu apodo")))
	_nick_edit = LineEdit.new()
	_nick_edit.max_length = Protocol.NICK_MAX
	_nick_edit.placeholder_text = tr("Entrenador")
	_nick_edit.text = Game.nick
	_nick_edit.text_changed.connect(func(t: String) -> void: Game.nick = t)
	box.add_child(_nick_edit)

	box.add_child(UiKit.section(tr("Tu equipo")))
	_team_select = OptionButton.new()
	for t in Game.teams:
		_team_select.add_item(tr("%s  (%d Pokémon)") % [t.name, t.members.size()])
	_team_select.select(Game.current_team)
	_team_select.item_selected.connect(func(i: int) -> void:
		Game.select_team(i)
		_refresh())
	box.add_child(_team_select)
	_team_hint = UiKit.hint("")
	_team_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_team_hint)
	box.add_child(UiKit.hint(tr("En VS todos los Pokémon luchan a nivel 50.")))
	box.add_child(HSeparator.new())

	_connect_box = VBoxContainer.new()
	_connect_box.add_theme_constant_override("separation", 10)
	box.add_child(_connect_box)
	_connect_box.add_child(UiKit.section(tr("Alojar una partida")))
	var host_row := HBoxContainer.new()
	host_row.add_theme_constant_override("separation", 8)
	host_row.add_child(UiKit.label(tr("Puerto:"), 17, UiKit.TEXT_DIM))
	_port_edit = _small_edit(str(Protocol.DEFAULT_PORT), 110)
	host_row.add_child(_port_edit)
	var host_button := UiKit.primary_button(tr("Alojar"), _host, 18)
	host_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	host_row.add_child(host_button)
	_connect_box.add_child(host_row)
	_connect_box.add_child(UiKit.section(tr("Unirse a una partida")))
	var join_row := HBoxContainer.new()
	join_row.add_theme_constant_override("separation", 8)
	_ip_edit = _small_edit("", 220)
	_ip_edit.placeholder_text = tr("IP del anfitrión")
	join_row.add_child(_ip_edit)
	_join_port_edit = _small_edit(str(Protocol.DEFAULT_PORT), 110)
	join_row.add_child(_join_port_edit)
	var join_button := UiKit.button(tr("Unirse"), _join, 18)
	join_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	join_row.add_child(join_button)
	_connect_box.add_child(join_row)

	_status = RichTextLabel.new()
	_status.bbcode_enabled = true
	_status.fit_content = true
	_status.scroll_active = false
	_status.custom_minimum_size.x = 520
	box.add_child(_status)
	_cancel_button = UiKit.ghost_button(tr("Cancelar"), _cancel, 17)
	box.add_child(_cancel_button)
	return panel


## Columna derecha: la sala con el rival.
func _build_room() -> PanelContainer:
	var panel := UiKit.panel()
	panel.custom_minimum_size.x = 440
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	panel.add_child(box)
	box.add_child(UiKit.section(tr("Sala")))
	_rival_label = RichTextLabel.new()
	_rival_label.bbcode_enabled = true
	_rival_label.fit_content = true
	_rival_label.scroll_active = false
	box.add_child(_rival_label)
	box.add_child(HSeparator.new())
	_board_box = VBoxContainer.new()
	_board_box.add_theme_constant_override("separation", 8)
	box.add_child(_board_box)
	_board_box.add_child(UiKit.heading(tr("Tablero (lo elige el anfitrión)")))
	_topology_select = OptionButton.new()
	_topology_select.add_item(tr("Cuadrado"))
	_topology_select.add_item(tr("Hexagonal"))
	_topology_select.select(Game.topology)
	_board_box.add_child(_topology_select)
	_biome_select = OptionButton.new()
	_biome_select.add_item(tr("Escenario al azar"))
	for kind in Biome.Kind.TEST:
		_biome_select.add_item(tr(Biome.NAMES[kind]))
	_board_box.add_child(_biome_select)
	_board_hint = UiKit.hint(tr("El anfitrión elige el tablero."))
	box.add_child(_board_hint)
	box.add_child(HSeparator.new())
	_ready_button = UiKit.primary_button(tr("¡Listo!"), _send_ready, 22)
	_ready_button.custom_minimum_size.y = 52
	box.add_child(_ready_button)
	_ready_label = UiKit.hint("")
	_ready_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_ready_label)
	return panel


func _small_edit(text: String, width: float) -> LineEdit:
	var e := LineEdit.new()
	e.text = text
	e.custom_minimum_size = Vector2(width, UiKit.CONTROL_H)
	return e


func _process(delta: float) -> void:
	_ping_left -= delta
	if _ping_left <= 0.0 and not Net.opponent.is_empty():
		_ping_left = 0.5
		_refresh_rival()


func _refresh() -> void:
	var members: Array = Game.player_team.map(func(m: TeamMember) -> String: return TeamMember.display(m.data, m.gender))
	_team_hint.text = ", ".join(members) if not members.is_empty() else tr("Este equipo está vacío: elige otro o complétalo en el editor.")
	var online := Net.is_online()
	_connect_box.visible = not online
	_cancel_button.visible = online
	_nick_edit.editable = not online
	_team_select.disabled = _ready_sent
	_room.visible = not Net.opponent.is_empty()
	if not online:
		return
	if Net.opponent.is_empty():
		if Net.mode == Net.Mode.HOST:
			_status.text = tr("Esperando a un rival en el puerto {port}.\nTu IP en la red local: [b]{ips}[/b]").format(
				{"port": _port_edit.text, "ips": ", ".join(_local_ips())})
		else:
			_status.text = tr("Conectando con {ip}…").format({"ip": _ip_edit.text})
	else:
		_status.text = tr("Conectado.")
	_board_box.visible = Net.side == 0
	_board_hint.visible = Net.side != 0
	_topology_select.disabled = _ready_sent
	_biome_select.disabled = _ready_sent
	_ready_button.disabled = _ready_sent or members.is_empty()
	_refresh_rival()


func _refresh_rival() -> void:
	if Net.opponent.is_empty():
		return
	var ping := Net.rtt()
	_rival_label.text = tr("Rival: [b]{nick}[/b]  ·  {ping} ms").format({"nick": Net.opponent.nick, "ping": ping if ping >= 0 else "—"})
	var mine := tr("Tú: listo") if _ready_sent else tr("Tú: eligiendo")
	var theirs := tr("Rival: listo") if _their_team_data != null else tr("Rival: eligiendo")
	_ready_label.text = "%s  ·  %s" % [mine, theirs]


## Direcciones IPv4 de este PC en la red local (para dárselas al rival).
func _local_ips() -> PackedStringArray:
	var ips := PackedStringArray()
	for ip in IP.get_local_addresses():
		if ip.count(".") == 3 and not ip.begins_with("127.") and not ip.begins_with("169.254."):
			ips.append(ip)
	return ips if not ips.is_empty() else PackedStringArray(["127.0.0.1"])


func _host() -> void:
	_start_net(Net.host(int(_port_edit.text)))


func _join() -> void:
	if _ip_edit.text.strip_edges().is_empty():
		_status.text = tr("Escribe la IP del anfitrión.")
		return
	_start_net(Net.join(_ip_edit.text.strip_edges(), int(_join_port_edit.text)))


func _start_net(err: Error) -> void:
	Game.nick = Protocol.clean_nick(_nick_edit.text)
	_nick_edit.text = Game.nick
	Game.save()
	Net.nick = Game.nick
	_ready_sent = false
	_their_team_data = null
	if err != OK:
		_status.text = "[color=#ff8a80]%s[/color]" % tr("No se pudo abrir la conexión (¿el puerto está en uso?).")
		return
	_refresh()


func _cancel() -> void:
	Net.close()
	_ready_sent = false
	_their_team_data = null
	_status.text = ""
	_refresh()


func _back() -> void:
	Net.close()
	Game.save()
	get_tree().change_scene_to_file("res://scenes/main_menu.tscn")


func _on_opponent() -> void:
	Audio.sfx("ui_place", -4.0)
	_refresh()


func _on_opponent_left(code: String) -> void:
	_ready_sent = false
	_their_team_data = null
	_status.text = "[color=#ffcc80]%s[/color]" % Protocol.reason_text(code)
	_refresh()


func _on_failed(code: String) -> void:
	_ready_sent = false
	_their_team_data = null
	_refresh()
	_status.text = "[color=#ff8a80]%s[/color]" % Protocol.reason_text(code)


func _send_ready() -> void:
	if _ready_sent or Game.player_team.is_empty():
		return
	_ready_sent = true
	_my_team_data = VsMatch.team_data(Game.player_team)
	Net.send({"t": "ready", "team": _my_team_data})
	_refresh()
	_try_start()


func _on_message(msg: Dictionary) -> void:
	match msg.t:
		"ready":
			var why := VsMatch.illegal_reason(msg.get("team"))
			if not why.is_empty():
				_status.text = "[color=#ff8a80]%s[/color]" % VsMatch.reason_text(why)
				return
			_their_team_data = msg.team
			_refresh()
			_try_start()
		"start":
			if Net.side != 1 or not _ready_sent:
				return
			# El anfitrión no puede cambiar nuestro equipo.
			var teams: Variant = msg.get("teams")
			var why := "format"
			if teams is Array and teams.size() == 2 and teams[1] == _my_team_data:
				why = VsMatch.apply_start(msg, 1)
			if why.is_empty():
				get_tree().change_scene_to_file("res://scenes/battle.tscn")
			else:
				_status.text = "[color=#ff8a80]%s[/color]" % VsMatch.reason_text(why)


## El anfitrión arranca cuando los dos están listos.
func _try_start() -> void:
	if Net.side != 0 or not _ready_sent or _their_team_data == null:
		return
	var msg := VsMatch.make_start(_my_team_data, _their_team_data, _topology_select.selected,
		_biome_select.selected - 1, [Game.nick, Net.opponent.nick])
	Net.send(msg)
	var why := VsMatch.apply_start(msg, 0)
	if why.is_empty():
		get_tree().change_scene_to_file("res://scenes/battle.tscn")
	else:
		_status.text = "[color=#ff8a80]%s[/color]" % VsMatch.reason_text(why)
