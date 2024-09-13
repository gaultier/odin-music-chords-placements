package main

import "core:container/small_array"
import "core:encoding/json"
import "core:fmt"
import "core:slice"
import "core:strconv"
import "core:testing"


NoteKind :: enum {
	A,
	A_Sharp,
	B,
	C,
	C_Sharp,
	D,
	D_Sharp,
	E,
	F,
	F_Sharp,
	G,
	G_Sharp,
}
#assert(cast(u8)NoteKind.G_Sharp == 11)

// Count in semi-tones.
Step :: enum {
	Half  = 1,
	Whole = 2,
}


ScaleKind :: [7]Step
major_scale_steps :: ScaleKind{.Whole, .Whole, .Half, .Whole, .Whole, .Whole, .Half}
minor_scale_steps :: ScaleKind{.Whole, .Half, .Whole, .Whole, .Half, .Whole, .Whole}

Scale :: [7]NoteKind


// FIXME: last_fret
BANJO_LAYOUT_STANDARD_5_STRINGS := StringInstrumentLayout {
	{open_note = .G, first_fret = 5, last_fret = 17},
	{open_note = .D, first_fret = 1, last_fret = 12},
	{open_note = .G, first_fret = 1, last_fret = 12},
	{open_note = .B, first_fret = 1, last_fret = 12},
	{open_note = .D, first_fret = 1, last_fret = 12},
}

// FIXME: last_fret
GUITAR_LAYOUT_STANDARD_6_STRING := StringInstrumentLayout {
	{open_note = .E, first_fret = 1, last_fret = 12},
	{open_note = .A, first_fret = 1, last_fret = 12},
	{open_note = .D, first_fret = 1, last_fret = 12},
	{open_note = .G, first_fret = 1, last_fret = 12},
	{open_note = .B, first_fret = 1, last_fret = 12},
	{open_note = .E, first_fret = 1, last_fret = 12},
}

// Maximum distance between the two most remote fingers.
MAX_FINGER_DISTANCE :: 4

@(require_results)
note_add :: proc(note_kind: NoteKind, offset: u8) -> NoteKind {
	return cast(NoteKind)((cast(u8)note_kind + offset) % 12)
}

@(require_results)
next_note_kind :: proc(note_kind: NoteKind, step: Step) -> NoteKind {
	return note_add(note_kind, cast(u8)step)
}

@(require_results)
make_scale :: proc(base_note: NoteKind, scale: ScaleKind) -> Scale {
	res := Scale{}
	res[0] = base_note

	for i := 1; i < len(res); i += 1 {
		res[i] = next_note_kind(res[i - 1], scale[i - 1])
	}

	assert(next_note_kind(res[len(res) - 1], scale[len(scale) - 1]) == res[0])
	assert(base_note == res[0])

	return res
}

ChordKind :: []u8
// 1-indexed to follow the music theory material.
chord_kind_standard :: ChordKind{1, 3, 5}
chord_kind_5 :: ChordKind{1, 5}
chord_kind_6 :: ChordKind{1, 3, 5, 6}
chord_kind_7 :: ChordKind{1, 3, 5, 7}
chord_kind_9 :: ChordKind{1, 3, 5, 7, 9}
chord_kind_11 :: ChordKind{1, 3, 5, 7, 9, 11}
chord_kind_13 :: ChordKind{1, 3, 5, 7, 9, 11, 13}

Chord :: small_array.Small_Array(10, NoteKind)

// nil: muted.
// 0: open
// N where N > 0: picked on fret N.
StringState :: Maybe(u8)

MAX_STRINGS_SUPPORTED :: 10
Fingering :: small_array.Small_Array(MAX_STRINGS_SUPPORTED, StringState)

@(require_results)
make_chord :: proc(scale: Scale, chord_kind: ChordKind) -> Chord {
	res := Chord{}

	for pos in chord_kind {
		// `pos` is 1-indexed so we have to make it zero-index.
		// We could go beyond the scale e.g. 9th, 11th, 13th, etc so we loop around with `%`.
		pos := pos - 1 if pos <= 8 else pos
		i := pos % 8
		small_array.push(&res, scale[i])
	}
	return res
}

StringLayout :: struct {
	open_note:  NoteKind,
	first_fret: u8,
	last_fret:  u8,
}

StringInstrumentLayout :: []StringLayout

@(require_results)
fingering_min_max :: proc(
	fingering: []StringState,
) -> (
	min: u8,
	max: u8,
	at_least_one_string_picked: bool,
) {
	for finger in fingering {
		fret, ok := finger.?
		if !ok {continue}
		if fret == 0 {continue}

		if fret < min {min = fret}
		if fret > max {max = fret}
	}
	return min, max, max > 0
}


@(require_results)
is_fingering_valid_for_chord :: proc(
	chord: []NoteKind,
	instrument_layout: StringInstrumentLayout,
	// This array has as many entries as the instrument has strings.
	// `fingering[a] = b` means: the string `a` is picked on fret `b`, or if `b == 0`, the string `a` is open.
	fingering: []StringState,
) -> bool {
	assert(len(fingering) == len(instrument_layout))

	// Check that the distance between the first and last finger is <= MAX_FINGER_DISTANCE.
	{
		finger_start, finger_end, at_least_one_string_picked := fingering_min_max(fingering)
		if at_least_one_string_picked {
			dist_squared := (finger_start - finger_end) * (finger_start - finger_end)

			if dist_squared >= MAX_FINGER_DISTANCE * MAX_FINGER_DISTANCE {return false}
		}
	}

	// Check that the fingering abides by the chord.
	{
		for &finger, string_i in fingering {
			string_layout := instrument_layout[string_i]
			note, muted := make_note_for_string_state(finger, string_layout)
			// If the string is muted, it cannot invalidate the chord.
			if muted {continue}

			if !slice.contains(chord, note) {return false}
		}
	}

	return true
}

increment_string_state :: proc(
	string_state: ^StringState,
	string_layout: StringLayout,
) -> (
	keep_going: bool,
) {

	fret, ok := string_state.?
	if !ok {
		string_state^ = 0
		return true
	}
	if fret == 0 {
		string_state^ = string_layout.first_fret
		return true
	}

	if fret == string_layout.last_fret {
		string_state^ = nil
		// Terminal state.
		return false
	} else {
		string_state^ = fret + 1
		return true
	}
}

next_fingering :: proc(
	fingering: ^[]StringState,
	instrumentLayout: StringInstrumentLayout,
) -> (
	keep_going: bool,
) {
	assert(len(fingering) > 0)
	assert(len(fingering) == len(instrumentLayout))

	#reverse for _, string_i in fingering {
		string_layout := instrumentLayout[string_i]

		keep_going = increment_string_state(&fingering[string_i], string_layout)

		if keep_going {return true}

		// The slot has reached the maximum value, need to inspect the left-hand part to increment it.
	}

	// Reached the end.
	return false
}

@(require_results)
count_muted_strings_in_fingering :: proc(fingering: []StringState) -> (count: u8) {
	for string_state in fingering {
		if _, ok := string_state.?; !ok {
			count += 1
		}
	}
	return
}

@(require_results)
count_notes_in_fingering :: proc(fingering: []StringState) -> (count: u8) {
	for string_state in fingering {
		if _, ok := string_state.?; ok {
			count += 1
		}
	}
	return
}

@(require_results)
count_open_notes_in_fingering :: proc(fingering: []StringState) -> (count: u8) {
	for string_state in fingering {
		fret, ok := string_state.?
		if ok && fret == 0 {
			count += 1
		}
	}
	return
}

// Order by open notes desc.
@(require_results)
order_fingering_by_ease :: proc(a: []StringState, b: []StringState) -> bool {
	a_count := count_open_notes_in_fingering(a)
	b_count := count_open_notes_in_fingering(b)
	return b_count < a_count
}

// Rules:
// - Each string is either muted, open, or picked by one finger and produces 0 (muted) or 1 (otherwise) note .
// - The maximum distance between all picked frets is 4 or 5 due to the physical length of fingers.
// - Every fret of every string gets considered
// TODO: muted strings.
@(require_results)
find_all_fingerings_for_chord :: proc(
	chord: []NoteKind,
	instrument_layout: StringInstrumentLayout,
	note_count_at_least: u8,
) -> [][]StringState {
	res: [dynamic][]StringState
	fingering := Fingering{}
	for _ in instrument_layout {
		small_array.append(&fingering, nil)
	}
	assert(len(instrument_layout) == small_array.len(fingering))
	fingering_slice := small_array.slice(&fingering)

	for next_fingering(&fingering_slice, instrument_layout) {
		if !is_fingering_valid_for_chord(
			chord,
			instrument_layout,
			small_array.slice(&fingering),
		) {continue}

		if count_notes_in_fingering(fingering_slice) < note_count_at_least {continue}

		clone, err := slice.clone(small_array.slice(&fingering))
		if err != nil {panic("clone failed")}

		append(&res, clone)
	}

	return res[:]
}


@(require_results)
make_note_for_string_state :: proc(
	string_state: StringState,
	string_layout: StringLayout,
) -> (
	note: NoteKind,
	muted: bool,
) {
	fret, ok := string_state.?
	if !ok {
		return NoteKind{}, true
	}
	if fret == 0 {
		return string_layout.open_note, false
	}
	return note_add(string_layout.open_note, fret), false
}

print_fingering :: proc(fingering: []StringState, instrument_layout: StringInstrumentLayout) {
	for string_state, i in fingering {
		string_layout := instrument_layout[i]
		note, muted := make_note_for_string_state(string_state, string_layout)
		if muted {
			fmt.print("x")
		} else if fret, ok := string_state.?; ok && fret == 0 {
			fmt.print("o", note)
		} else {
			fmt.print(string_state, note)
		}

		if i < len(fingering) - 1 {
			fmt.print(" | ")
		}
	}
	fmt.print("\n")
}

@(require_results)
parse_chord :: proc(chord: string) -> (res: Chord, ok: bool) {
	chord_slice := transmute([]u8)chord
	base_note_char, rest := slice.split_first(chord_slice)

	sharp: bool
	if len(rest) > 0 && slice.first(rest) == '#' {
		_, rest = slice.split_first(rest)
		sharp = true
	}

	base_note := NoteKind.A
	switch base_note_char {
	case 'A':
		base_note = .A_Sharp if sharp else .A
	case 'B':
		if sharp {return {}, false}
		base_note = .B
	case 'C':
		base_note = .C_Sharp if sharp else .C
	case 'D':
		base_note = .D_Sharp if sharp else .D
	case 'E':
		if sharp {return {}, false}
		base_note = .E
	case 'F':
		base_note = .F_Sharp if sharp else .F
	case 'G':
		base_note = .G_Sharp if sharp else .G
	case:
		return {}, false
	}

	minor: bool
	if len(rest) > 0 && slice.first(rest) == 'm' {
		_, rest = slice.split_first(rest)
		minor = true
	}


	// TODO: maj, sus, add ...


	level: u64
	level_present: bool
	if len(rest) > 0 {
		level = strconv.parse_u64(transmute(string)rest) or_return
		level_present = true
	}

	if level_present && level < 5 {return {}, false}

	// TODO: /9, ...

	steps := minor_scale_steps if minor else major_scale_steps
	scale := make_scale(base_note, steps)

	if !level_present {
		return make_chord(scale, chord_kind_standard), true
	}

	switch level {
	case 5:
		return make_chord(scale, chord_kind_5), true
	case 6:
		return make_chord(scale, chord_kind_6), true
	case 7:
		return make_chord(scale, chord_kind_7), true
	case 9:
		return make_chord(scale, chord_kind_9), true
	case 11:
		res = make_chord(scale, chord_kind_11)
		if !minor {
			// In case of a major, raise the 11th by a semi-tone to avoid dissonance.
			res.data[small_array.len(res) - 1] = note_add(res.data[small_array.len(res) - 1], 1)
		}
		return res, true
	case 13:
		res = make_chord(scale, chord_kind_13)
		if minor {
			// In case of a minor, raise the 13th by a semi-tone to avoid dissonance.
			res.data[small_array.len(res) - 1] = note_add(res.data[small_array.len(res) - 1], 1)
		}
		return res, true
	case:
		return {}, false
	}
}

find_all_fingerings_json_for_chord_str :: proc(chord_str: string) -> []u8 {
	chord, ok := parse_chord("Cm13")
	if !ok {return {}}

	fingerings := find_all_fingerings_for_chord(
		small_array.slice(&chord),
		BANJO_LAYOUT_STANDARD_5_STRINGS,
		3,
	)
	defer delete(fingerings)

	res, _ := json.marshal(fingerings)
	return res
}

main :: proc() {
	// fmt.println("---------- Banjo C ----------")
	// {
	// 	c_major_scale := make_scale(.C, major_scale_steps)
	// 	c_chord_kind_standard := make_chord(c_major_scale, chord_kind_7)
	// 	c_chord_kind_standard_slice := small_array.slice(&c_chord_kind_standard)
	// 	fmt.println(c_chord_kind_standard_slice)

	// 	c_chord_kind_standard_fingerings := find_all_fingerings_for_chord(
	// 		c_chord_kind_standard_slice,
	// 		BANJO_LAYOUT_STANDARD_5_STRINGS,
	// 		3,
	// 	)
	// 	defer delete(c_chord_kind_standard_fingerings)

	// 	fmt.println(len(c_chord_kind_standard_fingerings))
	// 	for fingering in c_chord_kind_standard_fingerings {
	// 		print_fingering(fingering, BANJO_LAYOUT_STANDARD_5_STRINGS)
	// 	}
	// }
	// fmt.println("---------- Banjo G ----------")
	// {
	// 	g_major_scale := make_scale(.G, major_scale_steps)
	// 	g_chord_kind_standard := make_chord(g_major_scale, chord_kind_standard)
	// 	g_chord_kind_standard_slice := small_array.slice(&g_chord_kind_standard)
	// 	fmt.println(g_chord_kind_standard_slice)
	// 	g_chord_kind_standard_fingerings := find_all_fingerings_for_chord(
	// 		g_chord_kind_standard_slice,
	// 		BANJO_LAYOUT_STANDARD_5_STRINGS,
	// 		3,
	// 	)
	// 	defer delete(g_chord_kind_standard_fingerings)

	// 	slice.sort_by(g_chord_kind_standard_fingerings, order_fingering_by_ease)

	// 	fmt.println(len(g_chord_kind_standard_fingerings))
	// 	for fingering in g_chord_kind_standard_fingerings {
	// 		print_fingering(fingering, BANJO_LAYOUT_STANDARD_5_STRINGS)
	// 	}
	// }
	// fmt.println("---------- GUITAR ----------")
	// {
	// 	g_major_scale := make_scale(.G, major_scale_steps)
	// 	g_chord_kind_standard := make_chord(g_major_scale, chord_kind_standard)
	// 	g_chord_kind_standard_slice := small_array.slice(&g_chord_kind_standard)
	// 	fmt.println(g_chord_kind_standard_slice)
	// 	g_chord_kind_standard_fingerings := find_all_fingerings_for_chord(
	// 		g_chord_kind_standard_slice,
	// 		GUITAR_LAYOUT_STANDARD_6_STRING,
	// 		3,
	// 	)
	// 	defer delete(g_chord_kind_standard_fingerings)

	// 	fmt.println(len(g_chord_kind_standard_fingerings))
	// 	for fingering in g_chord_kind_standard_fingerings {
	// 		print_fingering(fingering, GUITAR_LAYOUT_STANDARD_6_STRING)
	// 	}
	// }

	j := find_all_fingerings_json_for_chord_str("Am")
	defer delete(j)
	fmt.printf("%s", j)
}

@(test)
test_make_scale :: proc(_: ^testing.T) {
	major_scale := make_scale(.A, major_scale_steps)
	assert(major_scale == [7]NoteKind{.A, .B, .C_Sharp, .D, .E, .F_Sharp, .G_Sharp})

	minor_scale := make_scale(.A, minor_scale_steps)
	assert(minor_scale == [7]NoteKind{.A, .B, .C, .D, .E, .F, .G})
}

@(test)
test_make_chord :: proc(_: ^testing.T) {
	c_major_scale := make_scale(.C, major_scale_steps)
	c_chord_kind_standard := make_chord(c_major_scale, chord_kind_standard)
	c_chord_kind_standard_slice := small_array.slice(&c_chord_kind_standard)

	assert(slice.equal(c_chord_kind_standard_slice, []NoteKind{.C, .E, .G}))


	d_major_scale := make_scale(.D, major_scale_steps)
	d_major_7_chord := make_chord(d_major_scale, chord_kind_7)
	d_major_7_chord_slice := small_array.slice(&d_major_7_chord)

	assert(slice.equal(d_major_7_chord_slice, []NoteKind{.D, .F_Sharp, .A, .C_Sharp}))
}

@(test)
test_valid_fingering_for_chord :: proc(_: ^testing.T) {
	{
		c_major_scale := make_scale(.C, major_scale_steps)
		c_chord_kind_standard := make_chord(c_major_scale, chord_kind_standard)

		assert(
			true ==
			is_fingering_valid_for_chord(
				small_array.slice(&c_chord_kind_standard),
				BANJO_LAYOUT_STANDARD_5_STRINGS,
				[]StringState{0, 2, 0, 1, 2},
			),
		)
		// That's a C5 !
		assert(
			false ==
			is_fingering_valid_for_chord(
				small_array.slice(&c_chord_kind_standard),
				BANJO_LAYOUT_STANDARD_5_STRINGS,
				[]StringState{0, 2, 2, 1, 2},
			),
		)
	}


	{
		g_major_scale := make_scale(.G, major_scale_steps)
		g_chord_kind_standard := make_chord(g_major_scale, chord_kind_standard)
		assert(
			true ==
			is_fingering_valid_for_chord(
				small_array.slice(&g_chord_kind_standard),
				BANJO_LAYOUT_STANDARD_5_STRINGS,
				[]StringState{0, 0, 0, 0, 0},
			),
		)
	}
}

@(test)
test_invalid_fingering_for_chord_distance_too_big :: proc(_: ^testing.T) {
	{
		c_major_scale := make_scale(.C, major_scale_steps)
		c_chord_kind_standard := make_chord(c_major_scale, chord_kind_standard)

		assert(
			false ==
			is_fingering_valid_for_chord(
				small_array.slice(&c_chord_kind_standard),
				BANJO_LAYOUT_STANDARD_5_STRINGS,
				[]StringState{0, 2, 12, 1, 2},
			),
		)
	}
}

@(test)
test_next_fingering :: proc(_: ^testing.T) {
	fingering := []StringState{0, 0, 0, 0, 0}

	assert(true == next_fingering(&fingering, BANJO_LAYOUT_STANDARD_5_STRINGS))
	assert(slice.equal([]StringState{0, 0, 0, 0, 1}, fingering))

	assert(true == next_fingering(&fingering, BANJO_LAYOUT_STANDARD_5_STRINGS))
	assert(slice.equal([]StringState{0, 0, 0, 0, 2}, fingering))


	fingering = []StringState{0, 0, 0, 0, 12}
	assert(true == next_fingering(&fingering, BANJO_LAYOUT_STANDARD_5_STRINGS))

	fret: u8
	ok: bool
	fret, ok = fingering[0].?
	assert(ok && fret == 0)
	fret, ok = fingering[1].?
	assert(ok && fret == 0)
	fret, ok = fingering[2].?
	assert(ok && fret == 0)

	fret, ok = fingering[3].?
	assert(ok && fret == 1)

	_, ok = fingering[4].?
	assert(!ok)

	fingering = []StringState{0, 12, 12, 12, 12}
	assert(true == next_fingering(&fingering, BANJO_LAYOUT_STANDARD_5_STRINGS))

	fret, ok = fingering[0].?
	assert(ok)
	assert(fret == u8(BANJO_LAYOUT_STANDARD_5_STRINGS[0].first_fret))

	_, ok = fingering[1].?
	assert(!ok)
	_, ok = fingering[2].?
	assert(!ok)
	_, ok = fingering[3].?
	assert(!ok)
	_, ok = fingering[4].?
	assert(!ok)
}

@(test)
test_increment_string_state :: proc(_: ^testing.T) {
	string_layout := BANJO_LAYOUT_STANDARD_5_STRINGS[0]

	{
		string_state: StringState = nil
		keep_going := increment_string_state(&string_state, string_layout)
		assert(keep_going)
		fret, ok := string_state.?
		assert(ok && fret == 0)
	}


	{
		string_state: StringState = 0
		keep_going := increment_string_state(&string_state, string_layout)
		assert(keep_going)

		v, ok := string_state.(u8)
		assert(ok)
		assert(v == string_layout.first_fret)
	}

	{
		string_state: StringState = string_layout.first_fret
		keep_going := increment_string_state(&string_state, string_layout)
		assert(keep_going)

		v, ok := string_state.(u8)
		assert(ok)
		assert(v == string_layout.first_fret + 1)
	}

	{
		string_state: StringState = string_layout.last_fret - 1
		keep_going := increment_string_state(&string_state, string_layout)
		assert(keep_going)

		v, ok := string_state.(u8)
		assert(ok)
		assert(v == string_layout.last_fret)
	}
	{
		string_state: StringState = string_layout.last_fret
		keep_going := increment_string_state(&string_state, string_layout)
		assert(!keep_going)

		_, ok := string_state.?
		assert(!ok)
	}
}

@(test)
test_make_note_for_string_state :: proc(_: ^testing.T) {
	string_layout := BANJO_LAYOUT_STANDARD_5_STRINGS[0]
	{
		_, muted := make_note_for_string_state(nil, string_layout)
		assert(muted)
	}
	{
		note, muted := make_note_for_string_state(0, string_layout)
		assert(!muted)
		assert(note == string_layout.open_note)
	}
	{
		note, muted := make_note_for_string_state(u8(2), string_layout)
		assert(!muted)
		assert(note == .A)
	}
}

@(test)
test_parse_chord :: proc(_: ^testing.T) {
	{
		chord, ok := parse_chord("A")
		assert(ok)
		fmt.println(small_array.slice(&chord))
		assert(slice.equal(small_array.slice(&chord), []NoteKind{.A, .C_Sharp, .E}))
	}
	{
		_, ok := parse_chord("A1")
		assert(!ok)
	}
	{
		chord, ok := parse_chord("C5")
		assert(ok)
		fmt.println(small_array.slice(&chord))
		assert(slice.equal(small_array.slice(&chord), []NoteKind{.C, .G}))
	}
	{
		_, ok := parse_chord("G8")
		assert(!ok)
	}
	{
		chord, ok := parse_chord("F#")
		assert(ok)
		fmt.println(small_array.slice(&chord))
		assert(slice.equal(small_array.slice(&chord), []NoteKind{.F_Sharp, .A_Sharp, .C_Sharp}))
	}
	{
		chord, ok := parse_chord("F#5")
		assert(ok)
		fmt.println(small_array.slice(&chord))
		assert(slice.equal(small_array.slice(&chord), []NoteKind{.F_Sharp, .C_Sharp}))
	}

	{
		chord, ok := parse_chord("Am")
		assert(ok)
		fmt.println(small_array.slice(&chord))
		assert(slice.equal(small_array.slice(&chord), []NoteKind{.A, .C, .E}))
	}
	{
		chord, ok := parse_chord("Cm13")
		assert(ok)
		fmt.println(small_array.slice(&chord))
		assert(
			slice.equal(
				small_array.slice(&chord),
				[]NoteKind{.C, .D_Sharp, .G, .A_Sharp, .D, .F, .A},
			),
		)
	}
}
