//conveyor2 is pretty much like the original, except it supports corners, but not diverters.
//note that corner pieces transfer stuff clockwise when running forward, and anti-clockwise backwards.

/obj/machinery/conveyor
	icon = 'icons/obj/machines/recycling.dmi'
	icon_state = "conveyor0"
	name = "conveyor belt"
	desc = "A conveyor belt."
	layer = BELOW_OBJ_LAYER	// so they appear under stuff
	anchored = TRUE

	var/operating = 0	// 1 if running forward, -1 if backwards, 0 if off
	var/operable = 1	// true if can operate (no broken segments in this belt run)
	var/forwards		// this is the default (forward) direction, set by the map dir
	var/backwards		// hopefully self-explanatory
	var/movedir			// the actual direction to move stuff in

	var/id = ""			// the control ID	- must match controller ID

/obj/machinery/conveyor/centcom_auto
	id = "round_end_belt"

	// create a conveyor
/obj/machinery/conveyor/New(loc, newdir, on = 0)
	..(loc)
	if(newdir)
		set_dir(newdir)

	if(dir & (dir-1)) // Diagonal. Forwards is *away* from dir, curving to the right.
		forwards = turn(dir, 135)
		backwards = turn(dir, 45)
	else
		forwards = dir
		backwards = turn(dir, 180)

	if(on)
		operating = 1
		setmove()



/obj/machinery/conveyor/proc/setmove()
	if(operating == 1)
		movedir = forwards
	else if(operating == -1)
		movedir = backwards
	else operating = 0
	update_icon()

/obj/machinery/conveyor/on_update_icon()
	if(MACHINE_IS_BROKEN(src))
		icon_state = "conveyor-broken"
		operating = 0
		return
	if(!operable)
		operating = 0
	if(!is_powered())
		operating = 0
	icon_state = "conveyor[operating]"

	// machine process
	// move items to the target location
/obj/machinery/conveyor/Process()
	if(inoperable())
		return
	if(!operating)
		return
	use_power_oneoff(100)

	/**
	 * the list of all items that will be moved this ptick
	 * moved items will be all in loc
	 */
	var/list/affecting = list()

	var/items_moved = 0
	for(var/thing in loc)
		if(thing == src)
			continue
		if(items_moved >= 10)
			break
		var/atom/movable/AM = thing
		if(!AM.anchored && AM.simulated)
			affecting += AM
			items_moved++
	if(length(affecting))
		addtimer(new Callback(src, PROC_REF(post_process), affecting), 1) // slight delay to prevent infinite propagation due to map order

/obj/machinery/conveyor/proc/post_process(list/affecting)
	for(var/A in affecting)
		if(TICK_CHECK)
			break
		var/atom/movable/AM = A
		if(AM.loc == src.loc) // prevents the object from being affected if it's not currently here.
			step(A,movedir)

// attack with item, place item on conveyor
/obj/machinery/conveyor/use_tool(obj/item/I, mob/living/user, list/click_params)
	if ((. = ..()))
		return

	if(isCrowbar(I))
		if(!MACHINE_IS_BROKEN(src))
			var/obj/item/conveyor_construct/C = new/obj/item/conveyor_construct(src.loc)
			C.id = id
			transfer_fingerprints_to(C)
		to_chat(user, SPAN_NOTICE("You remove the conveyor belt."))
		qdel(src)
		return TRUE

	else
		user.unequip_item(get_turf(src))
		return TRUE

// attack with hand, move pulled object onto conveyor
/obj/machinery/conveyor/physical_attack_hand(mob/user)
	if(!user.pulling)
		return
	if(user.pulling.anchored)
		return
	if((user.pulling.loc != user.loc && get_dist(user, user.pulling) > 1))
		return
	if(ismob(user.pulling))
		var/mob/M = user.pulling
		M.stop_pulling()
		step(user.pulling, get_dir(user.pulling.loc, src))
		user.stop_pulling()
		return TRUE
	else
		step(user.pulling, get_dir(user.pulling.loc, src))
		user.stop_pulling()
		return TRUE

// make the conveyor broken
// also propagate inoperability to any connected conveyor with the same ID
/obj/machinery/conveyor/set_broken(new_state)
	. = ..()
	if(. && new_state)
		var/obj/machinery/conveyor/C = locate() in get_step(src, dir)
		if(C)
			C.set_operable(dir, id, 0)

		C = locate() in get_step(src, turn(dir,180))
		if(C)
			C.set_operable(turn(dir,180), id, 0)

//set the operable var if ID matches, propagating in the given direction

/obj/machinery/conveyor/proc/set_operable(stepdir, match_id, op)

	if(id != match_id)
		return
	operable = op

	update_icon()
	var/obj/machinery/conveyor/C = locate() in get_step(src, stepdir)
	if(C)
		C.set_operable(stepdir, id, op)

// the conveyor control switch

/obj/machinery/conveyor_switch

	name = "conveyor switch"
	desc = "A conveyor control switch."
	icon = 'icons/obj/machines/recycling.dmi'
	icon_state = "switch-off"
	var/position = 0			// 0 off, -1 reverse, 1 forward
	var/last_pos = -1			// last direction setting
	var/operated = 1			// true if just operated

	var/id = "" 				// must match conveyor IDs to control them

	var/list/conveyors		// the list of converyors that are controlled by this switch
	anchored = TRUE



/obj/machinery/conveyor_switch/New(loc, newid)
	..(loc)
	if(!id)
		id = newid
	update_icon()

	spawn(5)		// allow map load
		conveyors = list()
		for(var/obj/machinery/conveyor/C in world)
			if(C.id == id)
				conveyors += C

// update the icon depending on the position

/obj/machinery/conveyor_switch/on_update_icon()
	if(position<0)
		icon_state = "switch-rev"
	else if(position>0)
		icon_state = "switch-fwd"
	else
		icon_state = "switch-off"


// timed process
// if the switch changed, update the linked conveyors

/obj/machinery/conveyor_switch/Process()
	if(!operated)
		return
	operated = 0

	for(var/obj/machinery/conveyor/C in conveyors)
		C.operating = position
		C.setmove()

// attack with hand, switch position
/obj/machinery/conveyor_switch/interface_interact(mob/user)
	if(!CanInteract(user, DefaultTopicState()))
		return FALSE
	do_switch()
	operated = 1
	update_icon()

	// find any switches with same id as this one, and set their positions to match us
	for(var/obj/machinery/conveyor_switch/S in world)
		if(S.id == src.id)
			S.position = position
			S.update_icon()
	return TRUE

/obj/machinery/conveyor_switch/proc/do_switch(mob/user)
	if(position == 0)
		if(last_pos < 0)
			position = 1
			last_pos = 0
		else
			position = -1
			last_pos = 0
	else
		last_pos = position
		position = 0

/obj/machinery/conveyor_switch/use_tool(obj/item/I, mob/living/user, list/click_params)
	if(isCrowbar(I))
		var/obj/item/conveyor_switch_construct/C = new/obj/item/conveyor_switch_construct(src.loc)
		C.id = id
		transfer_fingerprints_to(C)
		to_chat(user, SPAN_NOTICE("You deattach the conveyor switch."))
		qdel(src)
		return TRUE

	return ..()

/obj/machinery/conveyor_switch/oneway
	var/convdir = 1 //Set to 1 or -1 depending on which way you want the convayor to go. (In other words keep at 1 and set the proper dir on the belts.)
	desc = "A conveyor control switch. It appears to only go in one direction."

/obj/machinery/conveyor_switch/oneway/do_switch(mob/user)
	if(position == 0)
		position = convdir
	else
		position = 0

//
// CONVEYOR CONSTRUCTION STARTS HERE
//

/obj/item/conveyor_construct
	icon = 'icons/obj/machines/recycling.dmi'
	icon_state = "conveyor0"
	name = "conveyor belt assembly"
	desc = "A conveyor belt assembly. Must be linked to a conveyor control switch assembly before placement."
	w_class = ITEM_SIZE_HUGE
	var/id = "" //inherited by the belt
	matter = list(MATERIAL_STEEL = 400, MATERIAL_PLASTIC = 200)

/obj/item/conveyor_construct/use_tool(obj/item/I, mob/living/user, list/click_params)
	if(istype(I, /obj/item/conveyor_switch_construct))
		to_chat(user, SPAN_NOTICE("You link the switch to the conveyor belt assembly."))
		var/obj/item/conveyor_switch_construct/C = I
		id = C.id
		return TRUE
	return ..()

/obj/item/conveyor_construct/use_after(atom/A, mob/living/user, click_parameters)
	if(!istype(A, /turf/simulated/floor) || istype(A, /area/shuttle) || user.incapacitated())
		return FALSE
	var/cdir = get_dir(A, user)
	if(!(cdir in GLOB.cardinal) || A == user.loc)
		return TRUE
	for(var/obj/machinery/conveyor/CB in A)
		if(CB.dir == cdir || CB.dir == turn(cdir,180))
			return TRUE
		cdir |= CB.dir
		qdel(CB)
	var/obj/machinery/conveyor/C = new/obj/machinery/conveyor(A,cdir)
	C.id = id
	transfer_fingerprints_to(C)
	qdel(src)
	return TRUE

/obj/item/conveyor_switch_construct
	name = "conveyor switch assembly"
	desc = "A conveyor control switch assembly."
	icon = 'icons/obj/machines/recycling.dmi'
	icon_state = "switch-off"
	w_class = ITEM_SIZE_HUGE
	var/id = "" //inherited by the switch
	matter = list(MATERIAL_STEEL = 200)


/obj/item/conveyor_switch_construct/New()
	..()
	id = rand() //this couldn't possibly go wrong

/obj/item/conveyor_switch_construct/use_after(atom/A, mob/living/user, click_parameters)
	if(!istype(A, /turf/simulated/floor) || istype(A, /area/shuttle) || user.incapacitated())
		return FALSE
	var/found = 0
	for(var/obj/machinery/conveyor/C in view())
		if(C.id == src.id)
			found = 1
			break
	if(!found)
		to_chat(user, "[icon2html(src, user)][SPAN_NOTICE("The conveyor switch did not detect any linked conveyor belts in range.")]")
		return TRUE
	var/obj/machinery/conveyor_switch/NC = new /obj/machinery/conveyor_switch(A, id)
	transfer_fingerprints_to(NC)
	qdel(src)
	return TRUE

/obj/item/conveyor_switch_construct/oneway
	name = "one-way conveyor switch assembly"
	desc = "An one-way conveyor control switch assembly."

/obj/item/conveyor_switch_construct/oneway/use_after(atom/A, mob/living/user, click_parameters)
	if(!istype(A, /turf/simulated/floor) || istype(A, /area/shuttle) || user.incapacitated())
		return FALSE
	var/found = 0
	for(var/obj/machinery/conveyor/C in view())
		if(C.id == src.id)
			found = 1
			break
	if(!found)
		to_chat(user, "[icon2html(src, user)][SPAN_NOTICE("The conveyor switch did not detect any linked conveyor belts in range.")]")
		return TRUE
	var/obj/machinery/conveyor_switch/oneway/NC = new /obj/machinery/conveyor_switch/oneway(A, id)
	transfer_fingerprints_to(NC)
	qdel(src)
	return TRUE
