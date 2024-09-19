const Note = {
  A: 0,
  A_Sharp: 1,
  B: 2,
  C: 3,
  C_Sharp: 4,
  D: 5,
  D_Sharp: 6,
  E: 7,
  F: 8,
  F_Sharp: 9,
  G: 10,
  G_Sharp: 11
};

const Step = {
  Half : 1,
  Whole : 2,
};

const major_scale_steps = [Step.Whole, Step.Whole, Step.Half, Step.Whole, Step.Whole, Step.Whole, Step.Half];
const minor_scale_steps = [Step.Whole, Step.Half, Step.Whole, Step.Whole, Step.Half, Step.Whole, Step.Whole];

const chord_kind_standard = [1, 3, 5];
const chord_kind_5 = [1, 5];
const chord_kind_7 = [1, 3, 5, 7];
const chord_kind_9 = [1, 3, 5, 7, 9];
const chord_kind_11 = [1, 3, 5, 7, 9, 11];
const chord_kind_13 = [1, 3, 5, 7, 9, 13];

const BANJO_LAYOUT_STANDARD_5_STRINGS = [
  {open_note: Note.G, first_fret: 5, last_fret: 17},
  {open_note: Note.D, first_fret: 1, last_fret: 17},
  {open_note: Note.G, first_fret: 1, last_fret: 17},
  {open_note: Note.B, first_fret: 1, last_fret: 17},
  {open_note: Note.D, first_fret: 1, last_fret: 17},
];

const StringState = {
  Muted: -1,
  Open: 0,
};

const MAX_FINGER_DISTANCE = 4;

function note_add_semitones(note, semitones) {
  return (note + semitones) % 12;
}

function make_scale(base_note, scale_kind) {
  const res = [base_note, 0, 0, 0, 0, 0, 0, 0];

  for (let i=1; i<res.length; i+=1) {
    res[i] = note_add_semitones(res[i-1], scale_kind[i-1]);
  }
  return res;
}

function make_chord(scale, chord_kind) {
  const res = [];

  for (const pos of chord_kind) {
    const i = (pos <= 8) ? pos - 1 : (pos % 8);
    res.push(scale[i]);
  }
  return res;
}

function fingering_min_max(fingering) {
  const res = {min:0, max: 0, at_least_one_string_picked: false};

  for (const finger of fingering) {
    if (finger == StringState.Muted) { continue; }
    else if (finger == StringState.Open) { continue; }

    res.min = finger < res.min ? finger : res.min;
    res.max = res.max < finger ? finger : res.max;
  }

  return res;
}

function is_fingering_valid_for_chord(chord, instrument_layout, fingering) {
	// Check that the distance between the first and last finger is <= MAX_FINGER_DISTANCE.
  {
    const {finger_start, finger_end, at_least_one_string_picked} = fingering_min_max(fingering);
    if (at_least_one_string_picked) {
      const dist_sq = (finger_start - finger_end) * (finger_start - finger_end);
      if (dist_sq >= MAX_FINGER_DISTANCE * MAX_FINGER_DISTANCE) { return false; }
    }
  }

	// Check that the fingering abides by the chord.
  {
    for (let i =0; i < fingering.length; i +=1 ) {
      const string_layout = instrument_layout[i];
      const finger = fingering[i];
      const {note, ok} = make_note_for_string_state(finger, string_layout);
      if (!ok) {continue;}

			// If the string is muted, it cannot invalidate the chord.
      if (note == StringState.Muted) { continue; }

      if (!chord.includes(note)) { return false; }
    }
  }

  return true;
}

function make_note_for_string_state(string_state, string_layout) {
  if (string_state == StringState.Muted) { return {note: Note.A, ok: false}; }

  else if (string_state == StringState.Open) { return {note: string_layout.open_note, ok: true}; }
  return {note: note_add_semitones(string_layout.open_note, string_state), ok: true};
}

function find_all_fingerings_for_chord(chord, instrument_layout, note_count_at_least) {
  const res = [];
  const fingering = [];

  for (_ of instrument_layout) {
    fingering.push(StringState.Muted);
  }

  while (next_fingering(fingering, instrument_layout)) {
    if (!is_fingering_valid_for_chord(chord, instrument_layout, fingering)) { continue; }
    if (count_notes_in_fingering(fingering) < note_count_at_least) { continue; }

    res.push(fingering.slice());
  }

  return res;
}

function count_notes_in_fingering(fingering) {
  let count = 0;

  for (string_state of fingering) {
    count += (string_state != StringState.Muted);
  }

  return count;
}

function next_fingering(fingering, instrument_layout) {
  for (let i =fingering.length - 1; i>=0; i-=1) {
    const string_layout = instrument_layout[i];
    const keep_going = increment_string_state(fingering, i, string_layout);
    if (keep_going) return true;
    
		// The slot has reached the maximum value, need to inspect the left-hand part to increment it, in the next loop iteration.
  }

  return false;
}

function increment_string_state(fingering, i, string_layout) {
  if (fingering[i] == StringState.Muted) { 
    fingering[i] = StringState.Open;
    return true;
  }
  if (fingering[i] == StringState.Open) {
    fingering[i] = string_layout.first_fret;
    return true;
  }

  if (fingering[i] == string_layout.last_fret) {
    fingering[i] = StringState.Muted;
    return false;
  }

  fingering[i] += 1;
  return true;
}

const c_major_scale = make_scale(Note.C, major_scale_steps);
const c_chord_kind_standard = make_chord(c_major_scale, chord_kind_standard);
console.log(c_chord_kind_standard);
console.log(find_all_fingerings_for_chord(c_chord_kind_standard, BANJO_LAYOUT_STANDARD_5_STRINGS, 3));

//     console.log(fingering, is_fingering_valid_for_chord(chord, instrument_layout, fingering), count_notes_in_fingering(fingering));
