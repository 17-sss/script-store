#!/usr/bin/env node
'use strict';

const fs = require('fs');
const crypto = require('crypto');
const os = require('os');
const path = require('path');
const readline = require('readline');
const {spawnSync} = require('child_process');

const APP_NAME = 'codex-session-manager';
const UUID_PATTERN = '[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}';
const UUID_EXACT_RE = new RegExp(`^${UUID_PATTERN}$`, 'i');
const FILENAME_UUID_RE = new RegExp(`^rollout-.+-(${UUID_PATTERN})\\.jsonl$`, 'i');
const PREVIEW_BYTES = 1024 * 1024;
const OSC_RE = /\x1b\][\s\S]*?(?:\x07|\x1b\\|$)/g;
const CONTROL_STRING_RE = /\x1b[PX^_][\s\S]*?(?:\x1b\\|$)/g;
const CSI_RE = /(?:\x1b\[|\x9b)[0-?]*[ -/]*[@-~]/g;
const ESCAPE_RE = /\x1b(?:[ -/]*[@-~]|.)/g;
const CONTROL_RE = /[\x00-\x08\x0b\x0c\x0e-\x1f\x7f-\x9f]/g;

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
const ANSI_RE = /\x1b\[[0-9;]*[A-Za-z]/g;
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
    forceDelete: false,
    quarantineDir: defaultQuarantineDir(),
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
    } else if (arg === '--force') {
      options.forceDelete = true;
    } else if (arg === '--codex-home') {
      index += 1;
      options.codexHome = requireValue(arg, args[index]);
    } else if (arg === '--cwd') {
      index += 1;
      options.cwd = requireValue(arg, args[index]);
    } else if (arg === '--quarantine-dir') {
      index += 1;
      options.quarantineDir = requireValue(arg, args[index]);
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
  options.quarantineDir = normalizePath(options.quarantineDir);
  validateQuarantineDir(options);
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
                           [--quarantine-dir PATH] [--force]
  codex-session-manager.js --list active|archived|all [--all] [--json]

Keys:
  Up/Down or j/k   Move selection
  Tab              Switch active/archived list
  a                Toggle current-cwd/all-cwd filtering
  Space            Toggle selected row
  A                Toggle all visible rows
  C                Clear selection
  /                Search
  r                Resume active session
  b                Archive selected or cursor session
  u                Unarchive selected or cursor session
  d                Quarantine selected or cursor session
  R                Refresh
  q                Quit

Notes:
  Listings are read from $CODEX_HOME/sessions and $CODEX_HOME/archived_sessions.
  Archive and unarchive call the official Codex CLI.
  Delete moves only the selected transcript(s) to the quarantine directory.
  Start with --force to permanently delete only the selected transcript(s).
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
    selected: new Set(),
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
    state.selected.clear();
    state.status = '';
    return;
  }

  if (key === 'a') {
    state.options.showAll = !state.options.showAll;
    state.cursor = 0;
    state.scroll = 0;
    state.selected.clear();
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
    if (key === 'R') {
      refresh(state);
    }
    return;
  }

  if (key === ' ') {
    toggleSelected(state);
  } else if (key === 'A') {
    toggleAllVisible(state);
  } else if (key === 'C') {
    clearSelection(state);
  } else if (key === '\u001b[A' || key === 'k') {
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
    state.selected.clear();
    state.status = state.query ? `Search: ${state.query}` : '';
    return;
  }

  if (key === '\u001b') {
    state.searching = false;
    state.query = '';
    state.cursor = 0;
    state.scroll = 0;
    state.selected.clear();
    state.status = 'Search cleared';
    return;
  }

  if (key === '\u007f') {
    state.query = state.query.slice(0, -1);
    state.cursor = 0;
    state.scroll = 0;
    state.selected.clear();
    return;
  }

  if (key >= ' ' && key !== '\u007f') {
    state.query += key;
    state.cursor = 0;
    state.scroll = 0;
    state.selected.clear();
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
  const entries = await checkedMutationTargets(state, actionTargetEntries(state), 'archive');
  if (!entries || entries.length === 0) {
    return;
  }
  const result = await runCodexBatch(state, entries, (entry) => ['archive', entry.canonicalId], 'Archived');
  if (!result.blocked) {
    state.selected.clear();
  }
  refresh(state);
}

async function unarchiveSelected(state) {
  if (state.view !== 'archived') {
    state.status = 'Selected session is already active';
    return;
  }
  const entries = await checkedMutationTargets(state, actionTargetEntries(state), 'unarchive');
  if (!entries || entries.length === 0) {
    return;
  }
  const result = await runCodexBatch(state, entries, (entry) => ['unarchive', entry.canonicalId], 'Unarchived');
  if (!result.blocked) {
    state.selected.clear();
  }
  refresh(state);
}

async function deleteSelected(state) {
  const permanent = state.options.forceDelete;
  const action = permanent ? 'force delete' : 'quarantine';
  let entries = await checkedMutationTargets(state, actionTargetEntries(state), action);
  if (!entries || entries.length === 0) {
    return;
  }

  const expected = deleteConfirmationText(entries, permanent);
  const answer = await promptLine(state, deleteConfirmationPrompt(state, entries, expected));

  if (answer.trim() !== expected) {
    state.status = `${permanent ? 'Permanent delete' : 'Quarantine'} cancelled. Required input was ${expected}`;
    return;
  }

  entries = await checkedMutationTargets(state, entries, action);
  if (!entries || entries.length === 0) {
    return;
  }

  const result = permanent
    ? await permanentlyDeleteBatch(state, entries)
    : await quarantineBatch(state, entries);
  if (!result.blocked) {
    state.selected.clear();
  }
  refresh(state);
}

function deleteConfirmationText(entries, permanent) {
  const verb = permanent ? 'FORCE DELETE' : 'QUARANTINE';
  return `${verb} ${entries.map((entry) => entry.canonicalId).join(' ')}`;
}

function deleteConfirmationPrompt(state, entries, expected) {
  const permanent = state.options.forceDelete;
  const targetLines = entries.map((entry, index) => `  ${index + 1}. ${entry.canonicalId}  ${entry.summary}`);
  return [
    permanent ? danger('Permanent delete confirmation') : warningText('Quarantine confirmation'),
    `${strong('Targets:')}`,
    ...targetLines,
    `${strong('Required input:')} ${requiredInput(expected)}`,
    permanent
      ? danger('This permanently unlinks only the listed transcript file(s). It cannot be undone.')
      : dim(`Files will be moved under ${state.options.quarantineDir}`),
    `${keyText('> ')}`
  ].join('\n');
}

async function quarantineBatch(state, entries) {
  suspendTui(state);
  console.log('');
  console.log(`Quarantine target${entries.length === 1 ? '' : 's'}:`);
  for (const entry of entries) {
    console.log(`- ${entry.canonicalId}  ${sanitizeTerminalText(entry.summary)}`);
  }
  console.log(`\nQuarantine root: ${state.options.quarantineDir}`);

  let result;
  try {
    result = moveEntriesToQuarantine(state.options, entries);
    state.status = `Quarantined ${entries.length} session${entries.length === 1 ? '' : 's'} in ${result.batchDir}`;
  } catch (error) {
    state.status = `Quarantine failed: ${error.message}`;
    result = {blocked: true};
  }
  resumeTui(state);
  return result;
}

function moveEntriesToQuarantine(options, entries) {
  fs.mkdirSync(options.quarantineDir, {recursive: true, mode: 0o700});
  const items = entries.map((entry) => {
    const storedRelativePath = quarantineRelativePath(options, entry);
    const stat = fs.statSync(entry.file);
    return {
      id: entry.canonicalId,
      state: entry.state,
      originalPath: entry.file,
      storedRelativePath,
      size: stat.size,
      mtime: stat.mtime.toISOString(),
    };
  });
  const batchName = createBatchName();
  const partialDir = path.join(options.quarantineDir, `.partial-${batchName}`);
  const batchDir = path.join(options.quarantineDir, batchName);
  fs.mkdirSync(partialDir, {mode: 0o700});

  const createdAt = new Date().toISOString();
  const manifestPath = path.join(partialDir, 'manifest.json');
  writeManifest(manifestPath, {
    version: 1,
    createdAt,
    mode: 'quarantine',
    status: 'moving',
    items,
  });

  const moved = [];
  try {
    for (let index = 0; index < entries.length; index += 1) {
      const entry = entries[index];
      const fresh = readEntry(entry.file, entry.state);
      const reason = mutationBlockReason(entry, fresh, options);
      if (reason) {
        throw new Error(`${entry.id}: ${reason}`);
      }
      const target = path.join(partialDir, items[index].storedRelativePath);
      fs.mkdirSync(path.dirname(target), {recursive: true, mode: 0o700});
      moveExactFile(entry.file, target);
      moved.push({source: entry.file, target});
    }

    writeManifest(manifestPath, {
      version: 1,
      createdAt,
      completedAt: new Date().toISOString(),
      mode: 'quarantine',
      status: 'complete',
      items,
    });
    fs.renameSync(partialDir, batchDir);
  } catch (error) {
    const rollbackErrors = rollbackMoves(moved);
    if (rollbackErrors.length === 0) {
      fs.rmSync(partialDir, {recursive: true, force: true});
    }
    const suffix = rollbackErrors.length > 0
      ? `; rollback incomplete: ${rollbackErrors.join('; ')}; inspect ${partialDir}`
      : '';
    throw new Error(`${error.message}${suffix}`);
  }

  return {blocked: false, batchDir};
}

async function permanentlyDeleteBatch(state, entries) {
  suspendTui(state);
  console.log('');
  console.log(`Permanent delete target${entries.length === 1 ? '' : 's'}:`);
  for (const entry of entries) {
    console.log(`- ${entry.canonicalId}  ${sanitizeTerminalText(entry.summary)}`);
  }
  console.log('');

  let deleted = 0;
  let blocked = null;
  let failed = null;
  for (const entry of entries) {
    const fresh = readEntry(entry.file, entry.state);
    const reason = mutationBlockReason(entry, fresh, state.options);
    if (reason) {
      blocked = {entry: fresh || entry, reason};
      break;
    }
    try {
      fs.unlinkSync(entry.file);
      deleted += 1;
    } catch (error) {
      failed = {entry, reason: error.message};
      break;
    }
  }

  resumeTui(state);
  if (blocked || failed) {
    const problem = blocked || failed;
    state.status = deleted === 0
      ? `Blocked force delete: ${problem.entry.id}  ${sanitizeTerminalText(problem.reason)}`
      : `Force delete stopped after ${deleted} session${deleted === 1 ? '' : 's'}: ${sanitizeTerminalText(problem.reason)}`;
  } else {
    state.status = `Permanently deleted ${deleted} session${deleted === 1 ? '' : 's'}`;
  }
  return {blocked: Boolean(blocked || failed), deleted};
}

function quarantineRelativePath(options, entry) {
  const relative = path.relative(options.codexHome, entry.file);
  if (!relative || path.isAbsolute(relative) || relative === '..' || relative.startsWith(`..${path.sep}`)) {
    throw new Error(`session path is outside CODEX_HOME: ${entry.file}`);
  }
  return relative;
}

function createBatchName() {
  const stamp = new Date().toISOString().replace(/[-:]/g, '').replace(/\.\d{3}Z$/, 'Z');
  return `${stamp}-${process.pid}-${crypto.randomBytes(4).toString('hex')}`;
}

function writeManifest(file, manifest) {
  const temporary = `${file}.tmp`;
  fs.writeFileSync(temporary, `${JSON.stringify(manifest, null, 2)}\n`, {encoding: 'utf8', mode: 0o600, flag: 'w'});
  fs.renameSync(temporary, file);
}

function moveExactFile(source, target) {
  if (fs.existsSync(target)) {
    throw new Error(`quarantine target already exists: ${target}`);
  }
  try {
    fs.renameSync(source, target);
    return;
  } catch (error) {
    if (error.code !== 'EXDEV') {
      throw error;
    }
  }

  try {
    fs.copyFileSync(source, target, fs.constants.COPYFILE_EXCL);
    const sourceStat = fs.statSync(source);
    const targetStat = fs.statSync(target);
    if (sourceStat.size !== targetStat.size) {
      throw new Error(`copied file size mismatch for ${source}`);
    }
    fs.unlinkSync(source);
  } catch (error) {
    try {
      fs.unlinkSync(target);
    } catch {
      // Keep the original error; a later rollback report points to the partial batch.
    }
    throw error;
  }
}

function rollbackMoves(moved) {
  const errors = [];
  for (const item of [...moved].reverse()) {
    try {
      fs.mkdirSync(path.dirname(item.source), {recursive: true, mode: 0o700});
      moveExactFile(item.target, item.source);
    } catch (error) {
      errors.push(`${item.source}: ${error.message}`);
    }
  }
  return errors;
}

async function checkedMutationTargets(state, entries, action) {
  if (entries.length === 0) {
    return [];
  }

  const checked = [];
  const unsafe = [];
  for (const entry of entries) {
    const fresh = readEntry(entry.file, entry.state);
    const reason = mutationBlockReason(entry, fresh, state.options);
    if (reason) {
      unsafe.push({
        entry: fresh || entry,
        reason,
      });
    } else {
      checked.push(fresh);
    }
  }

  if (unsafe.length > 0) {
    await showBlockedMutation(state, action, unsafe);
    state.status = `Blocked ${action}: unsafe session selected`;
    return null;
  }

  return checked;
}

function mutationBlockReason(original, fresh, options) {
  const pathReason = mutationPathBlockReason(original, options);
  if (pathReason) {
    return pathReason;
  }
  if (!original.mutationSafe) {
    return original.unsafeReason || 'session identity is unsafe';
  }
  if (!fresh) {
    return 'session transcript could not be read before mutation';
  }
  if (!fresh.mutationSafe) {
    return fresh.unsafeReason || 'session identity is unsafe';
  }
  if (!fresh.canonicalId || fresh.canonicalId !== original.canonicalId) {
    return 'session identity changed before mutation';
  }
  return '';
}

function mutationPathBlockReason(entry, options) {
  if (!options) {
    return '';
  }
  const expectedRoot = entry.state === 'active'
    ? sessionsDir(options)
    : entry.state === 'archived'
      ? archivedDir(options)
      : '';
  if (!expectedRoot || !isUnderPath(entry.file, expectedRoot) || path.extname(entry.file) !== '.jsonl') {
    return `transcript path is outside the expected ${entry.state || 'session'} directory`;
  }
  return '';
}

async function showBlockedMutation(state, action, unsafe) {
  const lines = [
    danger(`Blocked ${action}: unsafe session selected`),
    dim('No mutation was executed. Clear the selection and choose only safe sessions.'),
    '',
    ...unsafe.map(({entry, reason}, index) => `${index + 1}. ${entry.id}  ${sanitizeTerminalText(reason)}`),
    '',
  ];
  await promptLine(state, `${lines.join('\n')}${keyText('Press Enter to return: ')}`);
}

async function runCodex(state, args, successMessage) {
  suspendTui(state);
  console.log('');
  console.log(`$ codex ${args.join(' ')}`);
  const result = spawnSync('codex', args, {stdio: 'inherit'});
  resumeTui(state);
  state.status = result.status === 0 ? successMessage : `codex ${args[0]} failed with exit code ${result.status}`;
}

async function runCodexBatch(state, entries, argsForEntry, verb) {
  suspendTui(state);
  console.log('');
  console.log(`${verb} target${entries.length === 1 ? '' : 's'}:`);
  for (const entry of entries) {
    console.log(`- ${entry.canonicalId}  ${sanitizeTerminalText(entry.summary)}`);
  }
  console.log('');

  let succeeded = 0;
  let failed = 0;
  let blocked = null;
  for (const entry of entries) {
    const fresh = readEntry(entry.file, entry.state);
    const reason = mutationBlockReason(entry, fresh, state.options);
    if (reason) {
      blocked = {entry: fresh || entry, reason};
      break;
    }

    const args = argsForEntry(fresh);
    console.log(`$ codex ${args.join(' ')}`);
    const result = spawnSync('codex', args, {stdio: 'inherit'});
    if (result.status === 0) {
      succeeded += 1;
    } else {
      failed += 1;
    }
  }

  if (blocked) {
    const action = argsForEntry(blocked.entry)[0];
    console.log('');
    console.log(`Blocked ${action}: ${blocked.entry.id}  ${sanitizeTerminalText(blocked.reason)}`);
  }

  resumeTui(state);
  if (blocked) {
    const action = argsForEntry(blocked.entry)[0];
    const completed = succeeded + failed;
    state.status = completed === 0
      ? `Blocked ${action}: session identity changed before execution`
      : `Blocked ${action} after ${completed} command${completed === 1 ? '' : 's'}: remaining sessions were not executed`;
  } else {
    state.status = failed === 0
      ? `${verb} ${succeeded} session${succeeded === 1 ? '' : 's'}`
      : `${verb} ${succeeded} session${succeeded === 1 ? '' : 's'}, ${failed} failed`;
  }
  return {blocked: Boolean(blocked), succeeded, failed};
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
  pruneSelection(state);
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
  const width = Math.max(1, cols - 1);
  const entries = currentEntries(state);
  const selectedCount = selectedEntries(state).length;
  const height = listHeight();
  state.cursor = clamp(state.cursor, 0, Math.max(entries.length - 1, 0));
  ensureCursorVisible(state);

  const lines = [];

  const scope = state.options.showAll ? 'all folders' : 'current folder';
  const title = [
    strong(APP_NAME),
    `View: ${valueText(state.view)}`,
    `Scope: ${valueText(scope)}`,
    `Delete: ${state.options.forceDelete ? danger('permanent') : warningText('quarantine')}`,
    `Marked: ${selectedCount > 0 ? warningText(String(selectedCount)) : '0'}`,
    `Sessions: ${entries.length}`,
  ].join(' | ');
  lines.push(truncateStyled(title, width));

  if (state.searching) {
    lines.push(truncateStyled(`Search: ${warningText(`${state.query}_`)} | ${keyText('Enter')}=apply filter | ${keyText('Esc')}=clear search`, width));
    lines.push(truncateStyled(`${strong('Tip:')} search applies after Enter; press Esc to return to the list`, width));
  } else {
    lines.push(truncateStyled(`Move: ${keyText('Up/Down,j/k')} | ${keyText('Tab')}=list | ${keyText('a')}=scope | ${keyText('/')}=search | ${keyText('R')}=refresh | ${keyText('q')}=quit`, width));
    const deleteLabel = state.options.forceDelete ? danger('d=PERMADEL') : warningText('d=quarantine');
    lines.push(truncateStyled(`Mark: ${keyText('Space')}=row ${keyText('A')}=all ${keyText('C')}=clear | Act marked/cursor: ${successText('b')}=archive ${successText('u')}=unarchive ${deleteLabel}`, width));
  }

  const start = state.scroll;
  const visible = entries.slice(start, start + height);
  for (let index = 0; index < height; index += 1) {
    const entry = visible[index];
    if (!entry) {
      lines.push('');
      continue;
    }

    const actualIndex = start + index;
    const line = formatTuiLine(entry, state.options.cwd, width, state.selected.has(entry.key));
    if (actualIndex === state.cursor) {
      lines.push(color(line, 'inverse'));
    } else {
      lines.push(line);
    }
  }

  const selected = entries[state.cursor];
  lines.push(dim(''.padEnd(width, '-').slice(0, width)));
  if (selected) {
    const safety = selected.mutationSafe ? 'safe' : `blocked: ${selected.unsafeReason}`;
    lines.push(truncate(`id: ${selected.id}  safety: ${safety}  source: ${selected.source}  time: ${formatDate(selected.time)}`, width));
    lines.push(truncate(`cwd: ${selected.cwd || '(unknown)'}`, width));
    lines.push(truncate(`file: ${sanitizeTerminalText(selected.file)}`, width));
    lines.push(truncate(`prompt: ${selected.summary}`, width));
  } else {
    lines.push('No sessions in this view.');
    lines.push('');
    lines.push('');
    lines.push('');
  }

  const status = state.status || `${state.view} directory: ${state.view === 'active' ? sessionsDir(state.options) : archivedDir(state.options)}`;
  lines.push(color(truncate(status, width), statusColor(status)));
  writeFrame(lines, rows);
}

function statusColor(status) {
  const normalized = status.toLowerCase();
  if (normalized.includes('failed') || normalized.startsWith('delete cancelled') || normalized.startsWith('blocked')) {
    return 'red';
  }
  if (
    normalized.includes('cancelled') ||
    normalized.includes('selected') ||
    normalized.includes('unselected') ||
    normalized.includes('cleared') ||
    normalized.includes('search') ||
    normalized.includes('showing') ||
    normalized.includes('filtering') ||
    normalized.includes('already')
  ) {
    return 'yellow';
  }
  return 'green';
}

function listHeight() {
  const rows = process.stdout.rows || 30;
  return Math.max(1, rows - 9);
}

function writeFrame(lines, rows) {
  const chunks = ['\x1b[H'];
  for (let index = 0; index < rows; index += 1) {
    chunks.push('\x1b[2K');
    if (index < lines.length) {
      chunks.push(lines[index]);
    }
    if (index < rows - 1) {
      chunks.push('\n');
    }
  }
  process.stdout.write(chunks.join(''));
}

function selectedEntry(state) {
  return currentEntries(state)[state.cursor];
}

function selectedEntries(state) {
  return currentEntries(state).filter((entry) => state.selected.has(entry.key));
}

function actionTargetEntries(state) {
  const entries = selectedEntries(state);
  const entry = selectedEntry(state);
  return entries.length > 0 ? entries : (entry ? [entry] : []);
}

function toggleSelected(state) {
  const entry = selectedEntry(state);
  if (!entry) {
    return;
  }

  if (state.selected.has(entry.key)) {
    state.selected.delete(entry.key);
    state.status = `Unselected ${entry.id}`;
  } else {
    state.selected.add(entry.key);
    state.status = `Selected ${entry.id}`;
  }
}

function toggleAllVisible(state) {
  const entries = currentEntries(state);
  if (entries.length === 0) {
    return;
  }

  const allSelected = entries.every((entry) => state.selected.has(entry.key));
  if (allSelected) {
    for (const entry of entries) {
      state.selected.delete(entry.key);
    }
    state.status = `Unselected ${entries.length} visible sessions`;
  } else {
    for (const entry of entries) {
      state.selected.add(entry.key);
    }
    state.status = `Selected ${entries.length} visible sessions`;
  }
}

function clearSelection(state) {
  const count = state.selected.size;
  state.selected.clear();
  state.status = `Cleared ${count} selected session${count === 1 ? '' : 's'}`;
}

function pruneSelection(state) {
  const visibleKeys = new Set(currentEntries(state).map((entry) => entry.key));
  for (const key of state.selected) {
    if (!visibleKeys.has(key)) {
      state.selected.delete(key);
    }
  }
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
      entry.canonicalId,
      entry.cwd,
      entry.source,
      entry.summary,
      entry.file,
      entry.unsafeReason,
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
  const preview = safeReadPreview(file);
  const filenameId = extractFilenameUuid(file);
  let timestamp = stat ? stat.mtimeMs : 0;
  let cwd = '';
  let source = '';
  let summary = '';
  let role = '';
  let nickname = '';

  if (!preview.ok) {
    const identity = unsafeIdentity(filenameId, '', `transcript could not be read: ${preview.error}`);
    return buildEntry({file, state, identity, timestamp, cwd, source, summary, role, nickname});
  }

  const lines = preview.text.split(/\r?\n/);
  const firstMeta = readFirstSessionMeta(lines);
  const identity = decideSessionIdentity(filenameId, firstMeta);

  if (firstMeta.payload) {
    const payload = firstMeta.payload;
    cwd = payload.cwd || cwd;
    timestamp = Date.parse(payload.timestamp || firstMeta.timestamp) || timestamp;
    role = payload.agent_role || role;
    nickname = payload.agent_nickname || nickname;
    source = formatSource(payload) || source;
  }

  for (const line of lines) {
    if (!line.trim()) {
      continue;
    }

    const item = safeJsonParse(line);
    if (!item) {
      continue;
    }

    if (!summary && item.type === 'response_item' && item.payload?.type === 'message') {
      const candidate = cleanPrompt(extractMessageText(item.payload));
      if (candidate) {
        summary = candidate;
      }
    }
  }

  return buildEntry({file, state, identity, timestamp, cwd, source, summary, role, nickname});
}

function buildEntry({file, state, identity, timestamp, cwd, source, summary, role, nickname}) {
  if (!source) {
    source = role || nickname ? `subagent/${role || 'agent'}${nickname ? `/${nickname}` : ''}` : 'unknown';
  }

  return {
    key: file,
    id: identity.displayId,
    canonicalId: identity.canonicalId,
    mutationSafe: identity.mutationSafe,
    unsafeReason: sanitizeTerminalText(identity.unsafeReason),
    state,
    file,
    cwd: sanitizeTerminalText(cwd),
    source: sanitizeTerminalText(source),
    summary: sanitizeTerminalText(summary) || '(no prompt preview)',
    time: timestamp,
  };
}

function safeReadPreview(file) {
  let fd;
  try {
    fd = fs.openSync(file, 'r');
    const buffer = Buffer.alloc(PREVIEW_BYTES);
    const bytesRead = fs.readSync(fd, buffer, 0, PREVIEW_BYTES, 0);
    return {ok: true, text: buffer.toString('utf8', 0, bytesRead)};
  } catch (error) {
    return {ok: false, text: '', error: error.message};
  } finally {
    if (fd !== undefined) {
      fs.closeSync(fd);
    }
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

function extractFilenameUuid(file) {
  const match = path.basename(file).match(FILENAME_UUID_RE);
  return match ? normalizeUuid(match[1]) : '';
}

function readFirstSessionMeta(lines) {
  for (const line of lines) {
    if (!line.trim()) {
      continue;
    }

    const item = safeJsonParse(line);
    if (!item) {
      return {id: '', payload: null, timestamp: '', unsafeReason: 'malformed JSON before first session_meta'};
    }
    if (item.type !== 'session_meta') {
      continue;
    }

    const payload = item.payload || null;
    if (!payload || typeof payload.id !== 'string' || !payload.id.trim()) {
      return {id: '', payload, timestamp: item.timestamp || '', unsafeReason: 'first session_meta payload.id is missing'};
    }

    const id = normalizeUuid(payload.id);
    if (!id) {
      return {id: '', payload, timestamp: item.timestamp || '', unsafeReason: 'first session_meta payload.id is not a valid UUID'};
    }

    return {id, payload, timestamp: item.timestamp || '', unsafeReason: ''};
  }

  return {id: '', payload: null, timestamp: '', unsafeReason: 'first session_meta payload.id was not found'};
}

function decideSessionIdentity(filenameId, firstMeta) {
  if (!filenameId) {
    return unsafeIdentity('', firstMeta.id, 'filename UUID is missing or invalid');
  }
  if (firstMeta.unsafeReason) {
    return unsafeIdentity(filenameId, firstMeta.id, firstMeta.unsafeReason);
  }
  if (!firstMeta.id) {
    return unsafeIdentity(filenameId, '', 'first session_meta payload.id was not found');
  }
  if (filenameId !== firstMeta.id) {
    return unsafeIdentity(filenameId, firstMeta.id, `filename UUID and first session_meta UUID mismatch (${filenameId} != ${firstMeta.id})`);
  }
  return {
    displayId: filenameId,
    canonicalId: filenameId,
    mutationSafe: true,
    unsafeReason: '',
  };
}

function unsafeIdentity(filenameId, transcriptId, unsafeReason) {
  return {
    displayId: filenameId || transcriptId || '(unsafe)',
    canonicalId: '',
    mutationSafe: false,
    unsafeReason,
  };
}

function normalizeUuid(value) {
  if (typeof value !== 'string') {
    return '';
  }
  const trimmed = value.trim();
  return UUID_EXACT_RE.test(trimmed) ? trimmed.toLowerCase() : '';
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

  text = stripTerminalControls(text);

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

function defaultQuarantineDir() {
  const dataHome = process.env.XDG_DATA_HOME || path.join(os.homedir(), '.local', 'share');
  return path.join(dataHome, APP_NAME, 'quarantine');
}

function validateQuarantineDir(options) {
  const root = path.parse(options.quarantineDir).root;
  const forbiddenExactPaths = new Set([
    root,
    normalizePath(os.homedir()),
    options.codexHome,
  ]);
  if (forbiddenExactPaths.has(options.quarantineDir)) {
    die('--quarantine-dir must be a dedicated subdirectory, not a filesystem, home, or CODEX_HOME root');
  }
  if (
    isUnderPath(options.quarantineDir, sessionsDir(options)) ||
    isUnderPath(options.quarantineDir, archivedDir(options))
  ) {
    die('--quarantine-dir cannot be inside the active or archived session directories');
  }
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
    entry.mutationSafe ? '[safe]' : `[unsafe: ${entry.unsafeReason}]`,
    `[${entry.source}]`,
    relativePath(entry.cwd, cwd),
    entry.summary,
  ].join('  ');
}

function formatTuiLine(entry, cwd, width, selected) {
  const safety = entry.mutationSafe ? '   ' : '[!]';
  const fields = [
    selected ? '[x]' : '[ ]',
    safety,
    formatDate(entry.time),
    entry.id.slice(0, 8),
    fixed(entry.source, 18),
    fixed(relativePath(entry.cwd, cwd), 32),
    entry.mutationSafe ? entry.summary : `unsafe: ${entry.unsafeReason}`,
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
  return `${plain}${' '.repeat(Math.max(width - displayWidth(plain), 0))}`;
}

function truncate(value, width) {
  return truncatePlain(value, width);
}

function truncateStyled(value, width) {
  const text = String(value || '').replace(/\s+/g, ' ');
  if (displayWidth(stripAnsi(text)) <= width) {
    return text;
  }
  if (width <= 1) {
    return '.'.repeat(width);
  }
  if (width <= 3) {
    return '.'.repeat(width);
  }

  const suffix = '...';
  const limit = width - displayWidth(suffix);
  let used = 0;
  let output = '';
  for (let index = 0; index < text.length;) {
    if (text[index] === '\x1b') {
      const match = text.slice(index).match(/^\x1b\[[0-9;]*[A-Za-z]/);
      if (match) {
        output += match[0];
        index += match[0].length;
        continue;
      }
    }

    const codePoint = text.codePointAt(index);
    const char = String.fromCodePoint(codePoint);
    const widthValue = charWidth(char);
    if (used + widthValue > limit) {
      break;
    }
    output += char;
    used += widthValue;
    index += char.length;
  }
  return `${output}${output.includes('\x1b') ? colors.reset : ''}${suffix}`;
}

function truncatePlain(value, width) {
  const text = sanitizeTerminalText(value);
  if (displayWidth(text) <= width) {
    return text;
  }
  if (width <= 1) {
    return '.'.repeat(width);
  }
  if (width <= 3) {
    return '.'.repeat(width);
  }

  const suffix = '...';
  const limit = width - displayWidth(suffix);
  let used = 0;
  let output = '';
  for (const char of text) {
    const charWidthValue = charWidth(char);
    if (used + charWidthValue > limit) {
      break;
    }
    output += char;
    used += charWidthValue;
  }
  return `${output}${suffix}`;
}

function displayWidth(value) {
  let width = 0;
  for (const char of String(value || '')) {
    width += charWidth(char);
  }
  return width;
}

function charWidth(char) {
  const code = char.codePointAt(0);
  if (!code || code === 0) {
    return 0;
  }
  if (code < 32 || (code >= 0x7f && code < 0xa0)) {
    return 0;
  }
  if (
    code >= 0x1100 && (
      code <= 0x115f ||
      code === 0x2329 ||
      code === 0x232a ||
      (code >= 0x2e80 && code <= 0xa4cf && code !== 0x303f) ||
      (code >= 0xac00 && code <= 0xd7a3) ||
      (code >= 0xf900 && code <= 0xfaff) ||
      (code >= 0xfe10 && code <= 0xfe19) ||
      (code >= 0xfe30 && code <= 0xfe6f) ||
      (code >= 0xff00 && code <= 0xff60) ||
      (code >= 0xffe0 && code <= 0xffe6) ||
      (code >= 0x1f300 && code <= 0x1f64f) ||
      (code >= 0x1f900 && code <= 0x1f9ff)
    )
  ) {
    return 2;
  }
  return 1;
}

function stripAnsi(value) {
  return stripTerminalControls(value).replace(ANSI_RE, '');
}

function stripTerminalControls(value) {
  return String(value || '')
    .replace(OSC_RE, '')
    .replace(CONTROL_STRING_RE, '')
    .replace(CSI_RE, '')
    .replace(ESCAPE_RE, '')
    .replace(CONTROL_RE, ' ');
}

function sanitizeTerminalText(value) {
  return stripTerminalControls(value).replace(/\s+/g, ' ').trim();
}

function clamp(value, min, max) {
  return Math.min(Math.max(value, min), max);
}

function color(value, name) {
  return paint(value, name);
}

function paint(value, ...names) {
  if (!process.stdout.isTTY || process.env.NO_COLOR) {
    return value;
  }
  const prefix = names.map((name) => colors[name] || '').join('');
  return `${prefix}${value}${colors.reset}`;
}

function dim(value) {
  return color(value, 'dim');
}

function strong(value) {
  return paint(value, 'bold');
}

function keyText(value) {
  return paint(value, 'bold', 'cyan');
}

function valueText(value) {
  return paint(value, 'cyan');
}

function warningText(value) {
  return paint(value, 'bold', 'yellow');
}

function successText(value) {
  return paint(value, 'bold', 'green');
}

function requiredInput(value) {
  return warningText(value);
}

function danger(value) {
  return paint(value, 'bold', 'red');
}

process.on('exit', restoreTerminal);
process.on('SIGINT', exitTui);

main();
