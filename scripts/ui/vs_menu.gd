extends Control
## Pantalla del modo VS: apodo y equipo; por Internet (servidor de salas: lista de salas públicas, crear una
## pública o privada, entrar con código, emparejamiento rápido) o por IP directa (alojar / unirse); y la sala con
## el rival (ping, tablero que elige el anfitrión y "¡Listo!"). Cuando los dos están listos, el anfitrión (lado 0)
## manda "start" (VsMatch) y empieza el combate.

## Segundos entre actualizaciones de la lista de salas.
const LIST_EVERY := 5.0

var _nick_edit: LineEdit
var _team_select: OptionButton
var _team_hint: Label
var _port_edit: LineEdit
var _ip_edit: LineEdit
var _join_port_edit: LineEdit
var _connect_box: VBoxContainer
var _relay_box: VBoxContainer
var _direct_box: VBoxContainer
var _server_edit: LineEdit
var _status: RichTextLabel
var _cancel_button: Button
var _leave_room_button: Button
var _lobby: PanelContainer
var _room_name_edit: LineEdit
var _private_check: CheckBox
var _code_edit: LineEdit
var _room_list: VBoxContainer
var _list_left := 0.0
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
	_lobby = _build_lobby()
	cols.add_child(_lobby)
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
	box.add_child(UiKit.label(tr("Tu marcador: {record}").format({"record": Game.vs_record_text()}), 16, UiKit.TEXT_DIM))
	box.add_child(HSeparator.new())

	_connect_box = VBoxContainer.new()
	_connect_box.add_theme_constant_override("separation", 10)
	box.add_child(_connect_box)
	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 8)
	_connect_box.add_child(tabs)
	var group := ButtonGroup.new()
	for i in 2:
		var tab := UiKit.button(tr("Por Internet") if i == 0 else tr("IP directa"), _show_way.bind(i), 17)
		tab.toggle_mode = true
		tab.button_group = group
		tab.button_pressed = i == 0
		tab.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		tabs.add_child(tab)

	_relay_box = VBoxContainer.new()
	_relay_box.add_theme_constant_override("separation", 10)
	_connect_box.add_child(_relay_box)
	_relay_box.add_child(UiKit.section(tr("Servidor de salas")))
	var server_row := HBoxContainer.new()
	server_row.add_theme_constant_override("separation", 8)
	_server_edit = _small_edit(Game.vs_server, 330)
	_server_edit.placeholder_text = tr("dirección:puerto")
	_server_edit.text_submitted.connect(func(_t: String) -> void: _connect_server())
	server_row.add_child(_server_edit)
	var server_button := UiKit.primary_button(tr("Conectar"), _connect_server, 18)
	server_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	server_row.add_child(server_button)
	_relay_box.add_child(server_row)
	var relay_hint := UiKit.hint(tr("Los dos jugadores os conectáis al mismo servidor: no hace falta abrir puertos."))
	relay_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_relay_box.add_child(relay_hint)

	_direct_box = VBoxContainer.new()
	_direct_box.add_theme_constant_override("separation", 10)
	_direct_box.visible = false
	_connect_box.add_child(_direct_box)
	_direct_box.add_child(UiKit.section(tr("Alojar una partida")))
	var host_row := HBoxContainer.new()
	host_row.add_theme_constant_override("separation", 8)
	host_row.add_child(UiKit.label(tr("Puerto:"), 17, UiKit.TEXT_DIM))
	_port_edit = _small_edit(str(Protocol.DEFAULT_PORT), 110)
	host_row.add_child(_port_edit)
	var host_button := UiKit.primary_button(tr("Alojar"), _host, 18)
	host_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	host_row.add_child(host_button)
	_direct_box.add_child(host_row)
	_direct_box.add_child(UiKit.section(tr("Unirse a una partida")))
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
	_direct_box.add_child(join_row)
	var direct_hint := UiKit.hint(tr("Fuera de tu red local, el anfitrión tiene que abrir ese puerto (UDP) en su router."))
	direct_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_direct_box.add_child(direct_hint)

	_status = RichTextLabel.new()
	_status.bbcode_enabled = true
	_status.fit_content = true
	_status.scroll_active = false
	_status.custom_minimum_size.x = 520
	box.add_child(_status)
	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 8)
	box.add_child(buttons)
	_leave_room_button = UiKit.button(tr("Salir de la sala"), _leave_room, 17)
	buttons.add_child(_leave_room_button)
	_cancel_button = UiKit.ghost_button(tr("Desconectar"), _cancel, 17)
	buttons.add_child(_cancel_button)
	return panel


## Columna derecha antes de tener rival por Internet: emparejamiento rápido, crear sala, código y lista.
func _build_lobby() -> PanelContainer:
	var panel := UiKit.panel()
	panel.custom_minimum_size.x = 520
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	panel.add_child(box)
	var quick := UiKit.primary_button(tr("Partida rápida"), _quick_match, 22)
	quick.custom_minimum_size.y = 52
	box.add_child(quick)
	box.add_child(UiKit.hint(tr("Te une a la primera sala pública que espera rival, o abre una.")))
	box.add_child(HSeparator.new())

	box.add_child(UiKit.heading(tr("Crear una sala")))
	var create_row := HBoxContainer.new()
	create_row.add_theme_constant_override("separation", 8)
	_room_name_edit = _small_edit("", 220)
	_room_name_edit.max_length = Protocol.ROOM_NAME_MAX
	_room_name_edit.placeholder_text = tr("Nombre de la sala")
	create_row.add_child(_room_name_edit)
	_private_check = CheckBox.new()
	_private_check.text = tr("Privada")
	_private_check.tooltip_text = tr("No sale en la lista: solo se entra con el código.")
	create_row.add_child(_private_check)
	var create := UiKit.button(tr("Crear"), _create_room, 17)
	create.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	create_row.add_child(create)
	box.add_child(create_row)

	box.add_child(UiKit.heading(tr("Entrar con un código")))
	var code_row := HBoxContainer.new()
	code_row.add_theme_constant_override("separation", 8)
	_code_edit = _small_edit("", 220)
	_code_edit.max_length = 5
	_code_edit.placeholder_text = tr("Código")
	_code_edit.text_submitted.connect(func(_t: String) -> void: _join_code())
	code_row.add_child(_code_edit)
	var enter := UiKit.button(tr("Entrar"), _join_code, 17)
	enter.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	code_row.add_child(enter)
	box.add_child(code_row)
	box.add_child(HSeparator.new())

	var list_head := HBoxContainer.new()
	list_head.add_child(UiKit.heading(tr("Salas públicas")))
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list_head.add_child(spacer)
	list_head.add_child(UiKit.ghost_button(tr("Actualizar"), _ask_list, 15))
	box.add_child(list_head)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size.y = 230
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	box.add_child(scroll)
	_room_list = VBoxContainer.new()
	_room_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_room_list.add_theme_constant_override("separation", 6)
	scroll.add_child(_room_list)
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
	if _lobby.visible:
		_list_left -= delta
		if _list_left <= 0.0:
			_ask_list()
	_ping_left -= delta
	if _ping_left <= 0.0 and not Net.opponent.is_empty():
		_ping_left = 0.5
		_refresh_rival()


func _refresh() -> void:
	var members: Array = Game.player_team.map(func(m: TeamMember) -> String: return TeamMember.display(m.data, m.gender))
	_team_hint.text = ", ".join(members) if not members.is_empty() else tr("Este equipo está vacío: elige otro o complétalo en el editor.")
	var online := Net.is_online()
	var in_lobby := Net.mode == Net.Mode.RELAY and Net.is_accepted() and Net.room.is_empty()
	_connect_box.visible = not online
	_cancel_button.visible = online
	_leave_room_button.visible = Net.mode == Net.Mode.RELAY and not Net.room.is_empty()
	_nick_edit.editable = not online
	_team_select.disabled = _ready_sent
	_room.visible = not Net.opponent.is_empty()
	if in_lobby and not _lobby.visible:
		_list_left = 0.0  # la lista, nada más llegar
	_lobby.visible = in_lobby
	if not online:
		return
	if Net.opponent.is_empty():
		if Net.mode == Net.Mode.RELAY:
			if not Net.is_accepted():
				_status.text = tr("Conectando con el servidor {server}…").format({"server": Game.vs_server})
			elif Net.room.is_empty():
				_status.text = tr("Conectado al servidor {server}.").format({"server": Game.vs_server})
			else:
				var room_name: String = Net.room.name if not Net.room.name.is_empty() else tr("Sala de {nick}").format({"nick": Game.nick})
				_status.text = tr("[b]{name}[/b]  ·  código [b][color=#ffcc40]{code}[/color][/b]\nEsperando a un rival. Pásale el código para que entre.").format(
					{"name": room_name, "code": Net.room.code})
		elif Net.mode == Net.Mode.HOST:
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
	if Game.vs_record.rivals.has(Net.opponent.nick):
		_rival_label.text += "\n" + tr("Contra {nick}: {record}").format({"nick": Net.opponent.nick, "record": Game.vs_record_text(Net.opponent.nick)})
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


## Muestra la conexión por servidor (0) o por IP directa (1).
func _show_way(way: int) -> void:
	_relay_box.visible = way == 0
	_direct_box.visible = way == 1


func _connect_server() -> void:
	var text := _server_edit.text.strip_edges()
	if text.is_empty():
		_status.text = tr("Escribe la dirección del servidor.")
		return
	Game.vs_server = text
	var address := text
	var port := Protocol.DEFAULT_PORT
	# "dirección:puerto" (una IPv6 sin corchetes tiene más de un ":" y va sin puerto).
	if text.count(":") == 1:
		address = text.get_slice(":", 0)
		port = int(text.get_slice(":", 1))
	elif text.begins_with("[") and "]:" in text:
		address = text.get_slice("]:", 0).trim_prefix("[")
		port = int(text.get_slice("]:", 1))
	_start_net(Net.join_relay(address, port))


func _quick_match() -> void:
	Net.send({"t": "room_join", "code": ""})


func _create_room() -> void:
	Net.send({"t": "room_create", "name": Protocol.clean_text(_room_name_edit.text, Protocol.ROOM_NAME_MAX),
		"public": not _private_check.button_pressed})


func _join_code() -> void:
	var code := _code_edit.text.strip_edges().to_upper()
	if code.is_empty():
		_status.text = tr("Escribe el código de la sala.")
		return
	Net.send({"t": "room_join", "code": code})


func _ask_list() -> void:
	_list_left = LIST_EVERY
	if Net.mode == Net.Mode.RELAY and Net.is_accepted():
		Net.send({"t": "lobby_list"})


func _leave_room() -> void:
	Net.leave_room()
	_ready_sent = false
	_their_team_data = null
	_refresh()


## Lista de salas públicas que manda el servidor.
func _show_rooms(rooms: Array) -> void:
	UiKit.clear(_room_list)
	if rooms.is_empty():
		_room_list.add_child(UiKit.hint(tr("No hay salas públicas. Crea una o usa Partida rápida.")))
		return
	# Primero las que esperan rival.
	rooms.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a.players) < int(b.players))
	for r: Dictionary in rooms:
		var row := PanelContainer.new()
		row.add_theme_stylebox_override("panel", UiKit.flat_style(UiKit.SURFACE_1, UiKit.RADIUS_S, 8))
		var line := HBoxContainer.new()
		line.add_theme_constant_override("separation", 10)
		row.add_child(line)
		var info := VBoxContainer.new()
		info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		info.add_theme_constant_override("separation", 0)
		var nick := Protocol.clean_nick(str(r.get("nick", "")))
		var room_name := Protocol.clean_text(str(r.get("name", "")), Protocol.ROOM_NAME_MAX)
		info.add_child(UiKit.label(room_name if not room_name.is_empty() else tr("Sala de {nick}").format({"nick": nick}), 17))
		var ping := int(r.get("ping", -1))
		info.add_child(UiKit.label(tr("{nick}  ·  {ping} ms").format({"nick": nick, "ping": ping if ping >= 0 else "—"}),
			UiKit.FONT_SMALL, UiKit.TEXT_DIM))
		line.add_child(info)
		var full := int(r.get("players", 1)) >= 2
		if full:
			line.add_child(UiKit.label(tr("En partida"), UiKit.FONT_SMALL, UiKit.TEXT_DIM))
		else:
			var enter := UiKit.button(tr("Entrar"), func() -> void: Net.send({"t": "room_join", "code": str(r.code)}), 16)
			enter.disabled = r.get("mine") == true
			line.add_child(enter)
		_room_list.add_child(row)


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
	if not get_window().has_focus():
		DisplayServer.window_request_attention()
	_refresh()


func _on_opponent_left(code: String) -> void:
	_ready_sent = false
	_their_team_data = null
	_refresh()
	_status.text = "[color=#ffcc80]%s[/color]" % Protocol.reason_text(code)


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
		"lobby_list":
			if msg.get("rooms") is Array:
				_show_rooms(msg.rooms)
		"room":
			_refresh()
		"lobby_error":
			_status.text = "[color=#ff8a80]%s[/color]" % Protocol.reason_text(str(msg.code))
		"ready":
			var why := VsMatch.illegal_reason(msg.get("team"))
			if not why.is_empty():
				_status.text = "[color=#ff8a80]%s[/color]" % VsMatch.reason_text(why)
				return
			_their_team_data = msg.team
			Audio.sfx("ui_confirm", -4.0)
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
