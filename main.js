// @flow  strict

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
}

function note_add_semitones(note /* : number */, semitones /* : number */ ) /* : number */ {
  return (note + semitones) % 12;
}

console.log(note_add_semitones(Note.B, 3));
