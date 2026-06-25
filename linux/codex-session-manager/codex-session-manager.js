#!/usr/bin/env node
'use strict';

const fs = require('fs');
const os = require('os');
const path = require('path');
const readline = require('readline');
const {spawnSync} = require('child_process');

const APP_NAME = 'codex-session-manager';
const UUID_RE = /[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}/i;
const PREVIEW_BYTES = 1024 * 1024;

const colors = {
  reset: '\x1b[0m',
  bold: '\x1b[1m',
  dim: '\x1b[2m',
  inverse: '\x1b[7m',
  cyan: '\x1b[36m',
  green: '\x1b[32m',
  yellow: '\x1b[33m',
  red: '\x1b[31m',
};
let terminalTouched = false;

function main() {
  const options = parseArgs(process.argv.slice(2));

  if (options.help) {
    printUsage();
    return;
  }

  if (options.listMode || !process.stdin.isTTY || !process.stdout.isTTY) {
    printInventory(options);
    return;
  }

  startTui(options).catch((error) => {
    restoreTerminal();
    console.error(`${APP_NAME}: ${error.message}`);
    process.exitCode = 1;
  });
}

function parseArgs(args) {
  const options = {
    codexHome: process.env.CODEX_HOME || path.join(os.homedir(), '.codex'),
    cwd: process.cwd(),
    showAll: false,
    listMode: '',
    json: false,
    help: false,
  };

  for (let index = 0; index < args.length; index += 1) {
    const arg = args[index];

    if (arg === '--help' || arg === '-h') {
      options.help = true;
    } else if (arg === '--all') {
      options.showAll = true;
    } else if (arg === '--json') {
      options.json = true;
    } else if (arg === '--codex-home') {
      index += 1;
      options.codexHome = requireValue(arg, args[index]);
    } else if (arg === '--cwd') {
      index += 1;
      options.cwd = requireValue(arg, args[index]);
    } else if (arg === '--list') {
      index += 1;
      options.listMode = requireValue(arg, args[index]);
      if (!['active', 'archived', 'all'].includes(options.listMode)) {
        die('--list must be active, archived, or all');
      }
    } else {
      die(`unknown option: ${arg}`);
    }
  }

  options.codexHome = normalizePath(options.codexHome);
  options.cwd = normalizePath(options.cwd);
  return options;
}

function requireValue(flag, value) {
  if (!value || value.startsWith('--')) {
    die(`${flag} requires a value`);
  }
  return value;
}

function die(message) {
  console.error(`${APP_NAME}: ${message}`);
  process.exit(1);
}

function printUsage() {
  console.log(`codex-session-manager - browse and manage local Codex sessions

Usage:
  codex-session-manager.js [--all] [--cwd PATH] [--codex-home PATH]
  codex-session-manager.js --list active|archived|all [--all] [--json]

Keys:
  Up/Down or j/k   Move selection
  Tab              Switch active/archived list
  a                Toggle current-cwd/all-cwd filtering
  /                Search
  r                Resume active session
  b                Archive active session
  u                Unarchive archived session
  d                Delete selected session
  q                Quit

Notes:
  Listings are read from $CODEX_HOME/sessions and $CODEX_HOME/archived_sessions.
  Mutating actions call the official Codex CLI: archive, delete, and unarchive.
`);
}

function printInventory(options) {
  const inventory = loadInventory(options);
  const modes = options.listMode === 'all' || !options.listMode
    ? ['active', 'archived']
    : [options.listMode];
  const result = {};

  for (const mode of modes) {
    result[mode] = applyFilters(inventory[mode], options);
  }

  if (options.json) {
    console.log(JSON.stringify(result, null, 2));
    return;
  }

  for (const mode of modes) {
    const entries = result[mode];
    console.log(`${mode} sessions (${entries.length})`);
    for (const entry of entries) {
      console.log(formatPlainLine(entry, options.cwd));
    }
    if (modes.length > 1) {
      console.log('');
    }
  }
}

async function startTui(options) {
  const state = {
    options,
    view: 'active',
    cursor: 0,
    scroll: 0,
    query: '',
    searching: false,
    status: '',
    suspended: false,
    inventory: loadInventory(options),
  };

  process.stdin.setRawMode(true);
  process.stdin.resume();
  process.stdin.setEncoding('utf8');
  process.stdout.write('\x1b[?25l');
  terminalTouched = true;

  render(state);

  process.stdin.on('data', async (key) => {
    if (state.suspended) {
      return;
    }

    try {
      await handleKey(state, key);
      render(state);
    } catch (error) {
      state.status = error.message;
      render(state);
    }
  });

  process.stdout.on('resize', () => render(state));
}

async function handleKey(state, key) {
  if (key === '\u0003') {
    exitTui();
    return;
  }

  if (state.searching) {
    handleSearchKey(state, key);
    return;
  }

  if (key === 'q' || key === '\u001b') {
    exitTui();
    return;
  }

  if (key === '\t') {
    state.view = state.view === 'active' ? 'archived' : 'active';
    state.cursor = 0;
    state.scroll = 0;
    state.status = '';
    return;
  }

  if (key === 'a') {
    state.options.showAll = !state.options.showAll;
    state.cursor = 0;
    state.scroll = 0;
    state.status = state.options.showAll ? 'Showing all cwd values' : `Filtering under ${state.options.cwd}`;
    return;
  }

  if (key === '/') {
    state.searching = true;
    state.status = 'Search mode';
    return;
  }

  const entries = currentEntries(state);
  if (entries.length === 0) {
    if (key === 'r') {
      refresh(state);
    }
    return;
  }

  if (key === '\u001b[A' || key === 'k') {
    moveCursor(state, -1);
  } else if (key === '\u001b[B' || key === 'j') {
    moveCursor(state, 1);
  } else if (key === '\u001b[5~') {
    moveCursor(state, -10);
  } else if (key === '\u001b[6~') {
    moveCursor(state, 10);
  } else if (key === 'g') {
    state.cursor = 0;
    state.scroll = 0;
  } else if (key === 'G') {
    state.cursor = entries.length - 1;
    ensureCursorVisible(state);
  } else if (key === 'r') {
    await resumeSelected(state);
  } else if (key === 'b') {
    await archiveSelected(state);
  } else if (key === 'u') {
    await unarchiveSelected(state);
  } else if (key === 'd') {
    await deleteSelected(state);
  } else if (key === 'R') {
    refresh(state);
  }
}

function handleSearchKey(state, key) {
  if (key === '\r' || key === '\n') {
    state.searching = false;
    state.cursor = 0;
    state.scroll = 0;
    state.status = state.query ? `Search: ${state.query}` : '';
    return;
  }

  if (key === '\u001b') {
    state.searching = false;
    state.query = '';
    state.cursor = 0;
    state.scroll = 0;
    state.status = 'Search cleared';
    return;
  }

  if (key === '\u007f') {
    state.query = state.query.slice(0, -1);
    state.cursor = 0;
    state.scroll = 0;
    return;
  }

  if (key >= ' ' && key !== '\u007f') {
    state.query += key;
    state.cursor = 0;
    state.scroll = 0;
  }
}

function moveCursor(state, delta) {
  const entries = currentEntries(state);
  state.cursor = clamp(state.cursor + delta, 0, Math.max(entries.length - 1, 0));
  ensureCursorVisible(state);
}

function ensureCursorVisible(state) {
  const height = listHeight();
  if (state.cursor < state.scroll) {
    state.scroll = state.cursor;
  } else if (state.cursor >= state.scroll + height) {
    state.scroll = state.cursor - height + 1;
  }
}

async function resumeSelected(state) {
  if (state.view !== 'active') {
    state.status = 'Unarchive before resuming';
    return;
  }
  const entry = selectedEntry(state);
  if (!entry) {
    return;
  }
  await runCodex(state, ['resume', entry.id], `Returned from ${entry.id}`);
}

async function archiveSelected(state) {
  if (state.view !== 'active') {
    state.status = 'Selected session is already archived';
    return;
  }
  const entry = selectedEntry(state);
  if (!entry) {
    return;
  }
  await runCodex(state, ['archive', entry.id], `Archived ${entry.id}`);
  refresh(state);
}

async function unarchiveSelected(state) {
  if (state.view !== 'archived') {
    state.status = 'Selected session is already active';
    return;
  }
  const entry = selectedEntry(state);
  if (!entry) {
    return;
  }
  await runCodex(state, ['unarchive', entry.id], `Unarchived ${entry.id}`);
  refresh(state);
}

async function deleteSelected(state) {
  const entry = selectedEntry(state);
  if (!entry) {
    return;
  }

  const answer = await promptLine(
    state,
    `Type DELETE ${entry.id.slice(0, 8)} to permanently delete ${entry.id}: `
  );

  if (answer.trim() !== `DELETE ${entry.id.slice(0, 8)}`) {
    state.status = 'Delete cancelled';
    return;
  }

  await runCodex(state, ['delete', entry.id, '--force'], `Deleted ${entry.id}`);
  refresh(state);
}

async function runCodex(state, args, successMessage) {
  suspendTui(state);
  console.log('');
  console.log(`$ codex ${args.join(' ')}`);
  const result = spawnSync('codex', args, {stdio: 'inherit'});
  resumeTui(state);
  state.status = result.status === 0 ? successMessage : `codex ${args[0]} failed with exit code ${result.status}`;
}

async function promptLine(state, prompt) {
  suspendTui(state);
  const answer = await new Promise((resolve) => {
    const rl = readline.createInterface({input: process.stdin, output: process.stdout});
    rl.question(`\n${prompt}`, (value) => {
      rl.close();
      resolve(value);
    });
  });
  resumeTui(state);
  return answer;
}

function suspendTui(state) {
  state.suspended = true;
  process.stdout.write('\x1b[?25h');
  if (process.stdin.isTTY) {
    process.stdin.setRawMode(false);
  }
}

function resumeTui(state) {
  if (process.stdin.isTTY) {
    process.stdin.setRawMode(true);
  }
  process.stdout.write('\x1b[?25l');
  state.suspended = false;
}

function refresh(state) {
  state.inventory = loadInventory(state.options);
  state.cursor = clamp(state.cursor, 0, Math.max(currentEntries(state).length - 1, 0));
  ensureCursorVisible(state);
}

function exitTui() {
  restoreTerminal();
  process.exit(0);
}

function restoreTerminal() {
  if (!terminalTouched) {
    return;
  }
  try {
    if (process.stdin.isTTY) {
      process.stdin.setRawMode(false);
    }
  } catch {
    // Ignore terminal restore failures during shutdown.
  }
  process.stdout.write('\x1b[?25h\x1b[0m');
}

function render(state) {
  const cols = process.stdout.columns || 100;
  const rows = process.stdout.rows || 30;
  const entries = currentEntries(state);
  const height = listHeight();
  state.cursor = clamp(state.cursor, 0, Math.max(entries.length - 1, 0));
  ensureCursorVisible(state);

  process.stdout.write('\x1b[2J\x1b[H');

  const scope = state.options.showAll ? 'all cwd' : `cwd: ${state.options.cwd}`;
  const title = `${APP_NAME}  ${state.view} (${entries.length})  ${scope}`;
  console.log(color(title, 'bold'));
  console.log(dim('Tab switch  a cwd/all  / search  r resume  b archive  u unarchive  d delete  R refresh  q quit'));

  const queryLine = state.searching
    ? `search: ${state.query}_`
    : state.query
      ? `search: ${state.query}`
      : '';
  console.log(dim(queryLine || ''));

  const start = state.scroll;
  const visible = entries.slice(start, start + height);
  for (let index = 0; index < height; index += 1) {
    const entry = visible[index];
    if (!entry) {
      console.log('');
      continue;
    }

    const actualIndex = start + index;
    const line = formatTuiLine(entry, state.options.cwd, cols - 1);
    if (actualIndex === state.cursor) {
      console.log(color(line, 'inverse'));
    } else {
      console.log(line);
    }
  }

  const selected = entries[state.cursor];
  console.log(dim(''.padEnd(cols, '-').slice(0, cols)));
  if (selected) {
    console.log(truncate(`id: ${selected.id}  source: ${selected.source}  time: ${formatDate(selected.time)}`, cols));
    console.log(truncate(`cwd: ${selected.cwd || '(unknown)'}`, cols));
    console.log(truncate(`file: ${selected.file}`, cols));
    console.log(truncate(`prompt: ${selected.summary}`, cols));
  } else {
    console.log('No sessions in this view.');
    console.log('');
    console.log('');
    console.log('');
  }

  const status = state.status || `${state.view} directory: ${state.view === 'active' ? sessionsDir(state.options) : archivedDir(state.options)}`;
  console.log(color(truncate(status, cols), status.toLowerCase().includes('failed') ? 'red' : 'green'));

  if (rows < 14) {
    console.log(dim('Terminal is short; resize for details.'));
  }
}

function listHeight() {
  const rows = process.stdout.rows || 30;
  return Math.max(5, rows - 9);
}

function selectedEntry(state) {
  return currentEntries(state)[state.cursor];
}

function currentEntries(state) {
  return applyFilters(state.inventory[state.view], state.options, state.query);
}

function applyFilters(entries, options, query = '') {
  const normalizedQuery = query.trim().toLowerCase();
  return entries.filter((entry) => {
    if (!options.showAll && !isUnderPath(entry.cwd, options.cwd)) {
      return false;
    }
    if (!normalizedQuery) {
      return true;
    }
    const haystack = [
      entry.id,
      entry.cwd,
      entry.source,
      entry.summary,
      entry.file,
    ].join(' ').toLowerCase();
    return haystack.includes(normalizedQuery);
  });
}

function loadInventory(options) {
  return {
    active: loadEntries(sessionsDir(options), 'active'),
    archived: loadEntries(archivedDir(options), 'archived'),
  };
}

function loadEntries(root, state) {
  return walkJsonl(root)
    .map((file) => readEntry(file, state))
    .filter(Boolean)
    .sort((left, right) => right.time - left.time || left.file.localeCompare(right.file));
}

function walkJsonl(root) {
  if (!fs.existsSync(root)) {
    return [];
  }

  const files = [];
  const stack = [root];
  while (stack.length > 0) {
    const dir = stack.pop();
    let items = [];
    try {
      items = fs.readdirSync(dir, {withFileTypes: true});
    } catch {
      continue;
    }

    for (const item of items) {
      const itemPath = path.join(dir, item.name);
      if (item.isDirectory()) {
        stack.push(itemPath);
      } else if (item.isFile() && item.name.endsWith('.jsonl')) {
        files.push(itemPath);
      }
    }
  }

  return files;
}

function readEntry(file, state) {
  const stat = safeStat(file);
  const preview = readPreview(file);
  const lines = preview.split(/\r?\n/);
  const fallbackId = extractId(file);
  let id = fallbackId;
  let timestamp = stat ? stat.mtimeMs : 0;
  let cwd = '';
  let source = '';
  let summary = '';
  let role = '';
  let nickname = '';

  for (const line of lines) {
    if (!line.trim()) {
      continue;
    }

    const item = safeJsonParse(line);
    if (!item) {
      continue;
    }

    if (item.type === 'session_meta' && item.payload) {
      const payload = item.payload;
      id = payload.id || id;
      cwd = payload.cwd || cwd;
      timestamp = Date.parse(payload.timestamp || item.timestamp) || timestamp;
      role = payload.agent_role || role;
      nickname = payload.agent_nickname || nickname;
      source = formatSource(payload) || source;
      continue;
    }

    if (!summary && item.type === 'response_item' && item.payload?.type === 'message') {
      const candidate = cleanPrompt(extractMessageText(item.payload));
      if (candidate) {
        summary = candidate;
      }
    }
  }

  if (!id) {
    return null;
  }

  if (!source) {
    source = role || nickname ? `subagent/${role || 'agent'}${nickname ? `/${nickname}` : ''}` : 'unknown';
  }

  return {
    id,
    state,
    file,
    cwd,
    source,
    summary: summary || '(no prompt preview)',
    time: timestamp,
  };
}

function readPreview(file) {
  const fd = fs.openSync(file, 'r');
  try {
    const buffer = Buffer.alloc(PREVIEW_BYTES);
    const bytesRead = fs.readSync(fd, buffer, 0, PREVIEW_BYTES, 0);
    return buffer.toString('utf8', 0, bytesRead);
  } finally {
    fs.closeSync(fd);
  }
}

function safeStat(file) {
  try {
    return fs.statSync(file);
  } catch {
    return null;
  }
}

function safeJsonParse(line) {
  try {
    return JSON.parse(line);
  } catch {
    return null;
  }
}

function extractId(value) {
  const match = value.match(UUID_RE);
  return match ? match[0] : '';
}

function formatSource(payload) {
  if (payload.agent_role || payload.agent_nickname) {
    return `subagent/${payload.agent_role || 'agent'}${payload.agent_nickname ? `/${payload.agent_nickname}` : ''}`;
  }

  if (typeof payload.source === 'string') {
    return payload.source;
  }

  if (payload.source?.subagent?.thread_spawn) {
    const spawn = payload.source.subagent.thread_spawn;
    return `subagent/${spawn.agent_role || 'agent'}${spawn.agent_nickname ? `/${spawn.agent_nickname}` : ''}`;
  }

  return payload.originator || payload.thread_source || '';
}

function extractMessageText(message) {
  const content = message.content;
  if (typeof content === 'string') {
    return message.role === 'user' ? content : '';
  }
  if (!Array.isArray(content) || message.role !== 'user') {
    return '';
  }
  return content
    .map((part) => part.text || part.input_text || '')
    .filter(Boolean)
    .join('\n');
}

function cleanPrompt(text) {
  if (!text) {
    return '';
  }

  const marker = '## My request for Codex:';
  const markerIndex = text.indexOf(marker);
  if (markerIndex >= 0) {
    text = text.slice(markerIndex + marker.length);
  } else if (text.trimStart().startsWith('# AGENTS.md instructions')) {
    return '';
  }

  const lines = text
    .replace(/\r/g, '')
    .split('\n')
    .map((line) => line.trim())
    .filter(Boolean);

  const useful = lines.find((line) => {
    if (line.startsWith('# AGENTS.md instructions')) {
      return false;
    }
    if (line === 'YOU ARE AN AUTONOMOUS CODING AGENT. EXECUTE TASKS TO COMPLETION WITHOUT ASKING FOR PERMISSION.') {
      return false;
    }
    if (line.startsWith('DO NOT STOP TO ASK') || line.startsWith('IF BLOCKED,')) {
      return false;
    }
    if (line.startsWith('<') || line.startsWith('<!--')) {
      return false;
    }
    if (line === '<INSTRUCTIONS>' || line === '</INSTRUCTIONS>') {
      return false;
    }
    return true;
  });

  return truncatePlain(useful || '', 160);
}

function sessionsDir(options) {
  return path.join(options.codexHome, 'sessions');
}

function archivedDir(options) {
  return path.join(options.codexHome, 'archived_sessions');
}

function normalizePath(value) {
  if (!value) {
    return value;
  }

  const expanded = value === '~'
    ? os.homedir()
    : value.startsWith('~/')
      ? path.join(os.homedir(), value.slice(2))
      : value;
  return path.resolve(expanded);
}

function isUnderPath(candidate, root) {
  if (!candidate) {
    return false;
  }
  const normalizedCandidate = normalizePath(candidate);
  const normalizedRoot = normalizePath(root);
  return normalizedCandidate === normalizedRoot || normalizedCandidate.startsWith(`${normalizedRoot}${path.sep}`);
}

function formatPlainLine(entry, cwd) {
  return [
    formatDate(entry.time),
    entry.id,
    `[${entry.state}]`,
    `[${entry.source}]`,
    relativePath(entry.cwd, cwd),
    entry.summary,
  ].join('  ');
}

function formatTuiLine(entry, cwd, width) {
  const fields = [
    formatDate(entry.time),
    entry.id.slice(0, 8),
    fixed(entry.source, 18),
    fixed(relativePath(entry.cwd, cwd), 32),
    entry.summary,
  ];
  return truncate(fields.join('  '), width);
}

function relativePath(value, cwd) {
  if (!value) {
    return '(unknown)';
  }
  const normalized = normalizePath(value);
  const base = normalizePath(cwd);
  const relative = path.relative(base, normalized);
  if (!relative) {
    return '.';
  }
  if (!relative.startsWith('..') && !path.isAbsolute(relative)) {
    return relative;
  }
  if (normalized.startsWith(os.homedir())) {
    return `~${normalized.slice(os.homedir().length)}`;
  }
  return normalized;
}

function formatDate(value) {
  const date = new Date(value || 0);
  if (Number.isNaN(date.getTime())) {
    return 'unknown';
  }
  const yyyy = String(date.getFullYear()).padStart(4, '0');
  const mm = String(date.getMonth() + 1).padStart(2, '0');
  const dd = String(date.getDate()).padStart(2, '0');
  const hh = String(date.getHours()).padStart(2, '0');
  const min = String(date.getMinutes()).padStart(2, '0');
  return `${yyyy}-${mm}-${dd} ${hh}:${min}`;
}

function fixed(value, width) {
  const plain = truncatePlain(value || '', width);
  return plain.padEnd(width, ' ');
}

function truncate(value, width) {
  return truncatePlain(value, width);
}

function truncatePlain(value, width) {
  const text = String(value || '').replace(/\s+/g, ' ');
  if (text.length <= width) {
    return text;
  }
  if (width <= 1) {
    return text.slice(0, width);
  }
  if (width <= 3) {
    return '.'.repeat(width);
  }
  return `${text.slice(0, width - 3)}...`;
}

function clamp(value, min, max) {
  return Math.min(Math.max(value, min), max);
}

function color(value, name) {
  if (!process.stdout.isTTY || process.env.NO_COLOR) {
    return value;
  }
  return `${colors[name] || ''}${value}${colors.reset}`;
}

function dim(value) {
  return color(value, 'dim');
}

process.on('exit', restoreTerminal);
process.on('SIGINT', exitTui);

main();
