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

  const dir = join(OUT, 'projects', slug(project));
  mkdirSync(dir, { recursive: true });
  const months = new Map();
  const bucket = (m) => {
    if (!months.has(m)) months.set(m, [`# ${project} — ${m}`, '']);
    return months.get(m);
  };

  let day = '';
  for (const o of obs) {
    const md = bucket((o.created_at || 'unknown').slice(0, 7));
    const d = (o.created_at || '').slice(0, 10);
    if (d !== day) { day = d; md.push('', `## ${d}`, ''); }
    md.push(`### ${o.title || '(untitled)'}`, '');
    if (o.subtitle) md.push(`*${o.subtitle}*`, '');
    md.push(`- **type:** \`${o.type}\`  **when:** ${o.created_at}`, '');
    const facts = arr(o.facts);
    if (facts.length) { md.push('**Facts**', ''); for (const f of facts) md.push(`- ${f}`); md.push(''); }
    if (o.narrative) md.push(o.narrative, '');
    const fm = arr(o.files_modified);
    if (fm.length) md.push(`**Files modified:** ${fm.map((f) => `\`${f}\``).join(', ')}`, '');
    const cs = arr(o.concepts);
    if (cs.length) md.push(`**Concepts:** ${cs.join(', ')}`, '');
    md.push('---', '');

    appendFileSync(jsonl, JSON.stringify({ ...o, project, facts, concepts: cs,
      files_read: arr(o.files_read), files_modified: fm }) + '\n');
    total++;
  }

  for (const s of sums) {
    const md = bucket((s.created_at || 'unknown').slice(0, 7));
    md.push(`## Session — ${(s.created_at || '').slice(0, 10)} — ${(s.request || '(no request)').slice(0, 140)}`, '');
    for (const [label, key] of [['Investigated','investigated'],['Learned','learned'],['Completed','completed'],['Next steps','next_steps']]) {
      if (s[key]) md.push(`**${label}:** ${s[key]}`, '');
    }
    md.push('---', '');
  }

  for (const [month, lines] of months) writeFileSync(join(dir, `${month}.md`), lines.join('\n'));
}

const prompts = q(`SELECT content_session_id,prompt_number,prompt_text,created_at
                   FROM user_prompts ORDER BY created_at_epoch ASC`);
writeFileSync(join(ARCHIVE, 'user-prompts.jsonl'), prompts.map((p) => JSON.stringify(p)).join('\n') + '\n');

writeFileSync(join(ARCHIVE, 'README.md'),
`# claude-mem export

${total} observations across ${projects.length} projects, plus ${prompts.length} user prompts.
Source: ${DB}

- \`${OUT}/projects/<project>/<YYYY-MM>.md\` — human-readable, split by month so no file
  trips MemPalace's per-file chunk cap (a single huge file is skipped SILENTLY).
- \`observations.jsonl\` — lossless, one JSON object per line.
- \`user-prompts.jsonl\` — every prompt you typed.

No LLM calls were used. This is a pure transform of local SQLite text.
`);

console.log(`${total} observations · ${projects.length} projects · ${prompts.length} prompts`);
console.log(`  mine-ready : ${OUT}`);
console.log(`  archive    : ${ARCHIVE}`);
