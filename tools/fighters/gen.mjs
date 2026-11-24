// Emits Godot .tres files for fighter content from compact JS specs.
import fs from 'node:fs';
import path from 'node:path';

const TYPES = {
  MoveData: 'res://content/types/move_data.gd',
  HitboxData: 'res://content/types/hitbox_data.gd',
  HitData: 'res://content/types/hit_data.gd',
  MotionData: 'res://content/types/motion_data.gd',
  EffectData: 'res://content/types/effect_data.gd',
  CancelData: 'res://content/types/cancel_data.gd',
  BuffData: 'res://content/types/buff_data.gd',
  TeleportData: 'res://content/types/teleport_data.gd',
  FighterData: 'res://content/types/fighter_data.gd',
};
const CHILD_TYPE = { hitboxes: 'HitboxData', hit: 'HitData', motions: 'MotionData', effects: 'EffectData', cancels: 'CancelData', buff: 'BuffData', teleport: 'TeleportData', parry_buff: 'BuffData' };
export const KIND = { LIGHT: 0, HEAVY: 1, AIR_LIGHT: 2, AIR_HEAVY: 3, GRAB: 4, THROW: 5, ABILITY: 6, SUPER: 7, GETUP_ATTACK: 8, BURST: 9 };
export const REACTION = { STAGGER: 0, KNOCKDOWN: 1, LAUNCH: 2, GROUND_BOUNCE: 3, PULL: 4 };
export const COND = { ALWAYS: 0, ON_CONTACT: 1, ON_HIT: 2 };
export const INTO = { ABILITY: 1, SUPER: 2, JUMP: 4, DODGE: 8, LIGHT: 16, HEAVY: 32 };
export const ANCHOR = { OWNER: 0, TARGET: 1 };
export const TP = { STICK: 0, FORWARD: 1, BEHIND_TARGET: 2 };

// Fields written as StringName.
const STRING_NAMES = new Set(['id', 'next_light', 'next_heavy', 'animation', 'cue', 'throw_move', 'light', 'heavy', 'run_light', 'air_light', 'air_heavy', 'grab', 'getup_attack', 'super_move']);

function num(v) { return Number.isInteger(v) ? String(v) : String(+v.toFixed(5)); }

class Writer {
  constructor() { this.ext = []; this.subs = []; this.counter = 0; }
  extId(type, p) {
    let e = this.ext.find(x => x.path === p);
    if (!e) { e = { type, path: p, id: `${this.ext.length + 1}_${path.basename(p).replace(/\W/g, '').slice(0, 12)}` }; this.ext.push(e); }
    return e.id;
  }
  value(key, v, parentKey) {
    if (v === null || v === undefined) return 'null';
    if (typeof v === 'boolean') return v ? 'true' : 'false';
    if (typeof v === 'number') return num(v);
    if (typeof v === 'string') {
      if (key === 'scene' || key === 'portrait') return JSON.stringify(v);
      if (v.startsWith('res://')) return `ExtResource("${this.extId(v.endsWith('.gd') ? 'Script' : 'Resource', v)}")`;
      return STRING_NAMES.has(key) ? `&"${v}"` : JSON.stringify(v);
    }
    if (v.$vec3) return `Vector3(${v.$vec3.map(num).join(', ')})`;
    if (v.$color) return `Color(${v.$color.map(num).join(', ')})`;
    if (v.$sn) return `Array[StringName]([${v.$sn.map(s => `&"${s}"`).join(', ')}])`;
    if (v.$ext) return `ExtResource("${this.extId('Resource', v.$ext)}")`;
    if (v.$extArray) {
      const sid = this.extId('Script', TYPES[v.type]);
      return `Array[ExtResource("${sid}")]([${v.$extArray.map(p => `ExtResource("${this.extId('Resource', p)}")`).join(', ')}])`;
    }
    if (Array.isArray(v)) {
      const type = CHILD_TYPE[key];
      const sid = this.extId('Script', TYPES[type]);
      return `Array[ExtResource("${sid}")]([${v.map(item => `SubResource("${this.sub(type, item)}")`).join(', ')}])`;
    }
    if (typeof v === 'object') return `SubResource("${this.sub(CHILD_TYPE[key], v)}")`;
    throw new Error('bad value ' + key);
  }
  body(type, obj) {
    const lines = [`script = ExtResource("${this.extId('Script', TYPES[type])}")`];
    for (const [k, v] of Object.entries(obj)) {
      if (k.startsWith('$')) continue;
      lines.push(`${k} = ${this.value(k, v)}`);
    }
    return lines.join('\n');
  }
  sub(type, obj) {
    const id = `${type.replace('Data', '')}_${++this.counter}`;
    const text = this.body(type, obj);
    this.subs.push(`[sub_resource type="Resource" id="${id}"]\n${text}\n`);
    return id;
  }
  write(type, obj) {
    const main = this.body(type, obj);
    const head = `[gd_resource type="Resource" script_class="${type}" format=3]\n`;
    const exts = this.ext.map(e => `[ext_resource type="${e.type}" path="${e.path}" id="${e.id}"]`).join('\n');
    return `${head}\n${exts}\n\n${this.subs.join('\n')}${this.subs.length ? '\n' : ''}[resource]\n${main}\n`;
  }
}

export const v3 = (x, y, z) => ({ $vec3: [x, y, z] });
export const color = (r, g, b, a = 1) => ({ $color: [r, g, b, a] });
export const sn = (...names) => ({ $sn: names });

export function writeResource(file, type, obj) {
  const w = new Writer();
  const text = w.write(type, obj);
  fs.mkdirSync(path.dirname(file), { recursive: true });
  fs.writeFileSync(file, text);
}

// Writes each move to <dir>/moves/<id>.tres and the fighter to <dir>/<file>.
export function writeFighter(repo, dir, fileName, fighter, moves) {
  const paths = [];
  for (const m of moves) {
    const rel = `${dir}/moves/${m.id}.tres`;
    writeResource(path.join(repo, rel), 'MoveData', m);
    paths.push(`res://${rel}`);
  }
  writeResource(path.join(repo, dir, fileName), 'FighterData', { ...fighter, moves: { $extArray: paths, type: 'MoveData' } });
}
