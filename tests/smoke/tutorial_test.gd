extends Node
## Plays Level 0 "Morning Chores" headless on a fresh profile, doing what a new player does at each station:
## patch the silo crack, wrench the Dummy-Bot, heal on the porch, stop a real Nibbler with the wrench,
## repair its damage, climb the catwalk and ring the dinner bell. The pistol stays a later build choice.
## Run from the project folder:
##   <godot> --headless --path . --fixed-fps 60 res://tests/smoke/tutorial_test.tscn
## Exits 0 when every check passes, 1 otherwise.

const MAIN_SCENE := "res://scenes/main/main.tscn"

var _profile: String = OS.get_temp_dir().path_join("tutorial_test_profile_%d.json" % OS.get_process_id())
var _main: Node
var _director: WaveDirector
var _tutorial: TutorialDirector
var _farmer: Farmer
var _failures: PackedStringArray = PackedStringArray()
var _checks: int = 0
var _finished: bool = false
var _melee_hits: int = 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	SaveManager.use_profile(_profile, true)
	_check(not SaveManager.tutorial_completed, "a fresh profile hasn't done Level 0")
	_main = (load(MAIN_SCENE) as PackedScene).instantiate()
	_main.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(_main)
	_run.call_deferred()


func _run() -> void:
	await _frames(10)
	_director = _main.get_node(^"WaveDirector") as WaveDirector
	_tutorial = _main.get_node_or_null(^"TutorialDirector") as TutorialDirector
	_farmer = GameState.players[0] as Farmer
	var silo := GameState.silo
	var hud := _main.get_node(^"HUD") as Hud

	_section("Start")
	_check(_tutorial != null, "a TutorialDirector runs on a fresh profile")
	if _tutorial == null:
		_finish()
		return
	_check(_director.phase == WaveDirector.Phase.TUTORIAL, "the wave director waits in TUTORIAL (%s)" % _director.phase_name())
	_check(hud._hint_label.visible and "V bonk" in hud._hint_label.text,
		"the normal weapon and control hint stays visible")
	_check(hud._phase_label.text == "MORNING CHORES" and hud._weapon_label.visible,
		"the normal phase and weapon HUD remains during Level 0")
	_check(hud._tutorial_lesson.visible and "silo" in hud._tutorial_lesson.text.to_lower(),
		"the first lesson explains what the silo protects")
	_check(_tutorial._marker.get_node_or_null(^"GroundRim") != null
			and _tutorial._marker.get_node_or_null(^"Bubble") == null,
		"a low ground ring guides the player without a floating icon")
	var shed := get_tree().get_first_node_in_group(ToolShed.GROUP_SHED) as ToolShed
	_check(not shed.is_open(), "the tool shed is shuttered throughout the melee lesson")
	_check(not _farmer.weapons.get_weapon(&"pistol").is_available(), "a new player starts with melee only")
	await _frames(300)
	_check(_director.phase == WaveDirector.Phase.TUTORIAL and _director.wave == 1, "no clock runs while the chores wait")

	_section("1 Silo")
	_check(_tutorial.step == TutorialDirector.Step.SILO, "starts on the silo step")
	var cracks := silo.get_cracks()
	_check(cracks.size() == 1, "the silo has sprung one leak")
	_check(is_equal_approx(silo.structure, silo.max_structure - TutorialDirector.CRACK_POOL), "Structure is down to 900 / 1000")
	var crack: SiloCrack = cracks[0]
	var stand := crack.global_position + crack.global_basis.z * 1.5
	stand.y = 0.2
	_farmer.teleport_to(stand)
	await _frames(5)
	Input.action_press(&"interact")
	await _frames(5)
	_check(hud._repair_bar.visible and "repair" in hud._prompt_label.text.to_lower(),
		"the normal repair prompt and progress bar teach sealing")
	var sealed := await _wait_until(func() -> bool: return silo.get_cracks().is_empty(), 12.0)
	Input.action_release(&"interact")
	_check(sealed > 0.0, "holding Interact seals the crack (%.1f s)" % sealed)
	_check(sealed > 0.9 and sealed < 1.5, "a Small crack takes about 1.2 s with the wrench (%.1f s)" % sealed)
	_check(is_equal_approx(silo.structure, silo.max_structure), "Structure is back to full")
	await _wait_until(func() -> bool: return _tutorial.step == TutorialDirector.Step.DUMMY, 4.0)

	_section("2 Dummy-Bot")
	_check(_tutorial.step == TutorialDirector.Step.DUMMY, "the Dummy-Bot step follows")
	var dummy := _main.get_node_or_null(^"TutorialDummy") as TutorialDummy
	_check(dummy != null, "the Dummy-Bot popped up")
	var al_before := GameState.parts[&"al"]
	_farmer.teleport_to(TutorialDirector.DUMMY_POSITION + Vector3(0.0, 0.2, 2.0))
	await _frames(30)
	_check("bonk" in hud._prompt_label.text.to_lower(), "the normal action prompt teaches the wrench attack")
	# Swing the real wrench at the dummy three times, one cooldown apart.
	var wrench := _farmer.weapons.current
	var hp_before := dummy.health.current
	for i in 3:
		_face(dummy)
		wrench.attack()
		await _frames(40)
		if i == 0:
			_check(dummy.health.current < hp_before, "a wrench hit hurts the dummy (%.0f -> %.0f)" % [hp_before, dummy.health.current])
	_check(dummy.health.is_dead(), "three swings pop it (75 HP: 25, 25, then the x1.5 finisher)")
	await _wait_until(func() -> bool: return _tutorial.step == TutorialDirector.Step.PORCH, 12.0)
	_check(GameState.parts[&"al"] >= al_before + TutorialDirector.STARTER_AL,
		"the dummy drops only a starter handful of Aluminium (%d -> %d)" % [al_before, GameState.parts[&"al"]])
	_check(_farmer.health.current <= 80.01 and _farmer.health.current > 50.0, "its spring bonked Pip for 20 (HP %.0f)" % _farmer.health.current)

	_section("3 Porch")
	_check(_tutorial.step == TutorialDirector.Step.PORCH, "the Porch step follows")
	var zone := _main.get_node(^"Farm/PorchHealZone") as HealZone
	_farmer.teleport_to(Vector3(zone.global_position.x, 0.6, zone.global_position.z))
	await _wait_until(func() -> bool: return _tutorial.step == TutorialDirector.Step.PRACTICE, 8.0)
	_check(_farmer.health.current >= _farmer.health.max_health - 0.01, "standing on the porch heals to full (HP %.0f)" % _farmer.health.current)
	_check(_tutorial.step == TutorialDirector.Step.PRACTICE, "healing leads straight into melee defense")
	_check(not shed.is_open(), "the shed stays shut during melee training")

	_section("4 Practice defense")
	var practice := _main.get_node_or_null(^"Robots/PracticeNibbler") as Robot
	_check(practice != null, "one Nibbler approaches the silo before wave 1")
	_check(_director.phase == WaveDirector.Phase.TUTORIAL, "practice does not start the wave clock")
	var structure_before := silo.structure
	await _wait_until(func() -> bool: return silo.structure < structure_before, 25.0)
	_check(silo.structure < structure_before, "the Nibbler demonstrates silo damage")
	_check(not hud._silo_alert.visible, "the practice hit keeps the tutorial lesson in focus")
	_check(not practice.is_physics_processing(), "practice Nibbler pauses after one hit")
	_check(silo.get_cracks().size() == 1, "the hit opens a repairable leak")
	var away := practice.global_position - silo.global_position
	away.y = 0.0
	_farmer.teleport_to(practice.global_position + away.normalized() * 1.9 + Vector3.UP * 0.2)
	await _frames(10)
	_check(_farmer.weapons.current == wrench and not _farmer.weapons.get_weapon(&"pistol").is_available(),
		"the wrench is the only available weapon for the live rehearsal")
	wrench.hit_landed.connect(func(target: Node, _packet: DamagePacket) -> void:
		if target == practice:
			_melee_hits += 1)
	for i in 3:
		if _tutorial.step != TutorialDirector.Step.PRACTICE or not is_instance_valid(practice):
			break
		_face(practice)
		wrench.attack()
		await _frames(40)
	_check(_melee_hits > 0, "wrench swings damage the live Nibbler")
	_check(_tutorial.step == TutorialDirector.Step.REPAIR, "stopping the Nibbler completes defense practice")
	await _wait_until(func() -> bool: return _tutorial.step == TutorialDirector.Step.REPAIR, 2.0)
	_check(_tutorial.step == TutorialDirector.Step.REPAIR, "the lesson asks for repair after the attack")
	var practice_crack: SiloCrack = silo.get_cracks()[0]
	var repair_stand := practice_crack.global_position + practice_crack.global_basis.z * 1.5
	repair_stand.y = 0.2
	_farmer.teleport_to(repair_stand)
	await _frames(5)
	Input.action_press(&"interact")
	await _wait_until(func() -> bool: return silo.get_cracks().is_empty(), 8.0)
	Input.action_release(&"interact")
	_check(silo.get_cracks().is_empty(), "patching the new leak completes the defense loop")
	_check(_tutorial.step == TutorialDirector.Step.CATWALK, "the catwalk follows the melee defense loop")

	_section("5 Catwalk")
	var ladder := silo.get_node(^"Ladder") as Node3D
	_farmer.teleport_to(ladder.global_position + Vector3(0.0, 0.3, 0.5))
	await _frames(5)
	Input.action_press(&"move_forward")
	await _wait_until(func() -> bool: return _farmer.state == Farmer.State.CLIMBING, 3.0)
	await _wait_until(func() -> bool: return _farmer.global_position.y >= 7.6, 6.0)
	Input.action_release(&"move_forward")
	_check(_farmer.state == Farmer.State.CLIMBING, "Pip climbs the silo ladder (y %.1f)" % _farmer.global_position.y)
	await _press_action(&"jump")
	await _wait_until(func() -> bool: return not _farmer.input.enabled, 4.0)
	_check(not _farmer.input.enabled, "the vista sweep holds Pip still on the catwalk")
	await _wait_until(func() -> bool: return _tutorial.step == TutorialDirector.Step.BELL, 12.0)
	_check(_tutorial.step == TutorialDirector.Step.BELL, "the sweep ends at the dinner bell")
	_check(_farmer.input.enabled, "control returns after the sweep")

	_section("6 Dinner bell")
	var bell := _main.get_node(^"Farm/DinnerBell") as DinnerBell
	_farmer.teleport_to(bell.global_position + Vector3(0.0, 0.2, 1.0))
	await _frames(5)
	var al_at_bell := GameState.parts[&"al"]
	Input.action_press(&"interact")
	await _wait_until(func() -> bool: return _director.phase != WaveDirector.Phase.TUTORIAL, 4.0)
	Input.action_release(&"interact")
	_check(_director.phase == WaveDirector.Phase.SIREN and _director.wave == 1, "the bell starts wave 1's siren (%s)" % _director.phase_name())
	_check(GameState.parts[&"al"] == al_at_bell + TutorialDirector.EARLY_BIRD_AL, "finishing the chores pays the Early Bird +5 Al")
	_check(not _farmer.weapons.get_weapon(&"pistol").is_available(), "wave 1 begins without a pistol")
	_check(not shed.is_open(), "the shed stays shut through wave 1's siren")
	_check(GameState.parts[&"al"] < int(StatService.next_cost(&"attack.pistol").get(&"al", 20)),
		"the starter payout cannot buy the pistol before wave 1")
	_check(SaveManager.tutorial_completed, "Level 0 is saved as done")
	await _frames(10)
	_check(hud._hint_label.visible and hud._tutorial_action.is_empty(),
		"the normal HUD continues after the tutorial action clears")
	_check(not hud._tutorial_lesson.visible, "the lesson clears for normal play")
	await _wait_until(func() -> bool: return _director.phase == WaveDirector.Phase.SPAWNING, 6.0)
	_check(_director.phase == WaveDirector.Phase.SPAWNING, "wave 1 attacks after the siren")
	_check(not shed.is_open(), "the shed stays shut while wave 1 attacks")
	await _frames(120)
	_check(_main.get_node_or_null(^"TutorialDirector") == null, "the tutorial cleans itself up")
	_check(_main.get_node_or_null(^"TutorialDummy") == null, "and so does the Dummy-Bot")

	_section("Profile")
	SaveManager.load_profile()
	_check(SaveManager.tutorial_completed, "the finished flag survives a save and reload")
	_finish()


func _face(dummy: Node3D) -> void:
	var to := dummy.global_position - _farmer.global_position
	_farmer.camera_rig.yaw = atan2(-to.x, -to.z)
	_farmer.facing_yaw = _farmer.camera_rig.yaw


func _finish() -> void:
	if _finished:
		return
	_finished = true
	print("")
	if _failures.is_empty():
		print("TUTORIAL TEST PASSED (%d checks)" % _checks)
	else:
		print("TUTORIAL TEST FAILED: %d of %d checks" % [_failures.size(), _checks])
		for failure in _failures:
			print("  - " + failure)
	DirAccess.remove_absolute(_profile)
	get_tree().quit(0 if _failures.is_empty() else 1)


func _wait_until(condition: Callable, timeout: float) -> float:
	var waited := 0.0
	while not condition.call():
		await get_tree().physics_frame
		waited += 1.0 / Engine.physics_ticks_per_second
		if waited > timeout:
			return -1.0
	return waited


func _press_action(action: StringName) -> void:
	Input.action_press(action)
	await _frames(2)
	Input.action_release(action)
	await _frames(2)


func _frames(count: int) -> void:
	for i in count:
		await get_tree().physics_frame


func _section(title: String) -> void:
	print("\n== %s ==" % title)


func _check(ok: bool, what: String) -> void:
	if _finished:
		return
	_checks += 1
	print(("  PASS  " if ok else "  FAIL  ") + what)
	if not ok:
		_failures.append(what)
