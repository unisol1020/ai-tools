#!/usr/bin/env node
import { execFileSync } from 'node:child_process';
import { mkdirSync, writeFileSync, appendFileSync, rmSync, existsSync } from 'node:fs';
import { join } from 'node:path';
import { homedir } from 'node:os';

const DB = process.env.CMEM_DB || join(homedir(), '.claude-mem', 'claude-mem.db');
const OUT = process.env.CMEM_OUT || join(homedir(), 'claude-mem-export');
const ARCHIVE = process.env.CMEM_ARCHIVE || join(homedir(), 'claude-mem-archive');

if (!existsSync(DB)) {
  console.error(`No claude-mem database at ${DB} — nothing to export.`);
  process.exit(2);
}

const q = (sql) =>
  JSON.parse(
    execFileSync('sqlite3', ['-json', '-readonly', DB, sql], {
      maxBuffer: 1024 * 1024 * 1024,
      encoding: 'utf8',
    }) || '[]'
  );

const arr = (v) => {
  if (!v) return [];
  try { const p = JSON.parse(v); return Array.isArray(p) ? p : [p]; } catch { return [v]; }
};
const slug = (s) => s.replace(/[^a-zA-Z0-9._-]+/g, '-').replace(/^-+|-+$/g, '').slice(0, 120) || 'unknown';

rmSync(OUT, { recursive: true, force: true });
rmSync(ARCHIVE, { recursive: true, force: true });
mkdirSync(join(OUT, 'projects'), { recursive: true });
mkdirSync(ARCHIVE, { recursive: true });

const projects = q(`SELECT DISTINCT project FROM observations ORDER BY project`).map((r) => r.project);
const jsonl = join(ARCHIVE, 'observations.jsonl');
writeFileSync(jsonl, '');

let total = 0;
for (const project of projects) {
  const esc = project.replace(/'/g, "''");
  const obs = q(
    `SELECT id,type,title,subtitle,facts,narrative,concepts,files_read,files_modified,
            created_at,memory_session_id,generated_by_model
     FROM observations WHERE project='${esc}' ORDER BY created_at_epoch ASC`
  );
  const sums = q(
    `SELECT request,investigated,learned,completed,next_steps,created_at
     FROM session_summaries WHERE project='${esc}' ORDER BY created_at_epoch ASC`
  );

  // One directory per ROOT project (the segment before the first '/'), so each
  // root is mined into its repo's wing, the one the hooks save and recall under.
  const root = project.includes('/') ? project.slice(0, project.indexOf('/')) : project;
  const sub = project.includes('/') ? project.slice(project.indexOf('/') + 1) : '';
  const dir = sub ? join(OUT, 'projects', slug(root), slug(sub)) : join(OUT, 'projects', slug(root));
  mkdirSync(dir, { recursive: true });
  // One file per memory: the miner chunks each file from its start, so every drawer
  // opens on the memory's own title instead of mid-sentence in a monthly dump.
  const write = (when, name, lines) => {
    const monthDir = join(dir, (when || 'unknown').slice(0, 7));
    mkdirSync(monthDir, { recursive: true });
    writeFileSync(join(monthDir, `${(when || 'unknown').slice(0, 10)}-${name}.md`), lines.join('\n'));
  };

  for (const o of obs) {
    const md = [`# ${o.title || '(untitled)'}`, ''];
    if (o.subtitle) md.push(`*${o.subtitle}*`, '');
    md.push(`- **project:** ${project}  **type:** \`${o.type}\`  **when:** ${o.created_at}`, '');
    if (o.narrative) md.push(o.narrative, '');
    const facts = arr(o.facts);
    if (facts.length) { md.push('**Facts**', ''); for (const f of facts) md.push(`- ${f}`); md.push(''); }
    const fm = arr(o.files_modified);
    if (fm.length) md.push(`**Files modified:** ${fm.map((f) => `\`${f}\``).join(', ')}`, '');
    const cs = arr(o.concepts);
    if (cs.length) md.push(`**Concepts:** ${cs.join(', ')}`, '');
    write(o.created_at, `${o.id}-${slug(o.title || 'untitled').slice(0, 60)}`, md);

    appendFileSync(jsonl, JSON.stringify({ ...o, project, facts, concepts: cs,
      files_read: arr(o.files_read), files_modified: fm }) + '\n');
    total++;
  }

  sums.forEach((s, i) => {
    const md = [`# Session — ${(s.request || '(no request)').slice(0, 140)}`, '',
      `- **project:** ${project}  **when:** ${s.created_at}`, ''];
    for (const [label, key] of [['Investigated','investigated'],['Learned','learned'],['Completed','completed'],['Next steps','next_steps']]) {
      if (s[key]) md.push(`**${label}:** ${s[key]}`, '');
    }
    write(s.created_at, `session-${slug(project)}-${i + 1}`, md);
  });
}

const prompts = q(`SELECT content_session_id,prompt_number,prompt_text,created_at
                   FROM user_prompts ORDER BY created_at_epoch ASC`);
writeFileSync(join(ARCHIVE, 'user-prompts.jsonl'), prompts.map((p) => JSON.stringify(p)).join('\n') + '\n');

// Prompts also go into the mined tree as their own wing; archived-only meant
// everything you ever asked stayed unsearchable in the palace.
const promptDir = join(OUT, 'projects', '_prompts');
mkdirSync(promptDir, { recursive: true });
const promptMonths = new Map();
let promptDay = '';
for (const pr of prompts) {
  const month = (pr.created_at || 'unknown').slice(0, 7);
  if (!promptMonths.has(month)) promptMonths.set(month, [`# Prompts — ${month}`, '']);
  const md = promptMonths.get(month);
  const d = (pr.created_at || '').slice(0, 10);
  if (d !== promptDay) { promptDay = d; md.push('', `## ${d}`, ''); }
  const text = (pr.prompt_text || '').trim();
  if (text) md.push(`- ${text}`, '');
}
for (const [month, lines] of promptMonths) writeFileSync(join(promptDir, `${month}.md`), lines.join('\n'));

// tool_uses and sdk_sessions live nowhere else. Without these, deleting
// ~/.claude-mem loses them permanently. Dumped via the sqlite3 CLI because
// tool_uses runs to hundreds of MB.
for (const [table, file] of [['tool_uses', 'tool-uses.json'], ['sdk_sessions', 'sdk-sessions.json']]) {
  try {
    const json = execFileSync('sqlite3', ['-readonly', DB, '-cmd', '.mode json', `SELECT * FROM ${table}`],
      { maxBuffer: 2 * 1024 * 1024 * 1024, encoding: 'utf8' });
    writeFileSync(join(ARCHIVE, file), json || '[]');
  } catch { console.warn(`  (could not archive ${table})`); }
}

writeFileSync(join(ARCHIVE, 'README.md'),
`# claude-mem export

${total} observations across ${projects.length} projects, plus ${prompts.length} user prompts.
Source: ${DB}

- \`${OUT}/projects/<project>/<YYYY-MM>/<date>-<id>-<title>.md\` — human-readable, one file per
  observation or session summary, so each MemPalace drawer starts at a memory's title.
- \`observations.jsonl\` — lossless, one JSON object per line.
- \`user-prompts.jsonl\` — every prompt you typed.

No LLM calls were used. This is a pure transform of local SQLite text.
`);

console.log(`${total} observations · ${projects.length} projects · ${prompts.length} prompts`);
console.log(`  mine-ready : ${OUT}/projects/<root>  (mine each root as its own wing)`);
console.log(`  archive    : ${ARCHIVE}`);
