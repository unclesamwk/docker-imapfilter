-- IMAPFilter configuration template
--
-- Rule flow:
-- 1) Protect important mail (never delete)
-- 2) Classify newsletters and operational mail
-- 3) Archive from inbox after short retention
-- 4) Delete from archive after long retention
--
-- Recommended first run:
--   IMAPFILTER_EXTRA_ARGS="-n"  (dry-run/no-op)

options.timeout = 120
options.subscribe = true

local function log(msg)
  print(os.date('%Y-%m-%dT%H:%M:%S') .. ' [imapfilter] ' .. msg)
end

local function trim(s)
  return (s:gsub('^%s+', ''):gsub('%s+$', ''))
end

local function read_file(path)
  local file = io.open(path, 'r')
  if not file then
    return nil
  end
  local content = file:read('*a')
  file:close()
  if not content then
    return nil
  end
  return trim(content)
end

local function get_env_or_file(name, required)
  local value = os.getenv(name)
  local file_path = os.getenv(name .. '_FILE')

  if value and file_path then
    error('Set only one of ' .. name .. ' or ' .. name .. '_FILE')
  end

  if file_path then
    value = read_file(file_path)
    if not value or value == '' then
      error('Failed to read value from ' .. name .. '_FILE at ' .. file_path)
    end
  end

  if required and (not value or value == '') then
    error('Missing required env var: ' .. name .. ' (or ' .. name .. '_FILE)')
  end

  return value
end

local server = get_env_or_file('IMAP_SERVER', true)
local username = get_env_or_file('IMAP_USER', true)
local password = get_env_or_file('IMAP_PASS', true)
local port = tonumber(get_env_or_file('IMAP_PORT', false) or '993')
local ssl = get_env_or_file('IMAP_SSL', false) or 'auto'

local account = IMAP {
  server = server,
  username = username,
  password = password,
  port = port,
  ssl = ssl,
}

-- Mailbox names (override by env if needed)
local archive_box = os.getenv('IMAP_ARCHIVE_MAILBOX') or 'Archive'
local newsletters_box = os.getenv('IMAP_NEWSLETTERS_MAILBOX') or 'Newsletters'
local ops_box = os.getenv('IMAP_OPS_MAILBOX') or 'Operations'

pcall(function() account:create_mailbox(archive_box) end)
pcall(function() account:create_mailbox(newsletters_box) end)
pcall(function() account:create_mailbox(ops_box) end)

local inbox = account.INBOX
local archive = account[archive_box]
local newsletters = account[newsletters_box]
local ops = account[ops_box]

local function union_contains_from(box, patterns)
  local set = box:contain_from(patterns[1])
  for i = 2, #patterns do
    set = set + box:contain_from(patterns[i])
  end
  return set
end

local function union_contains_subject(box, patterns)
  local set = box:contain_subject(patterns[1])
  for i = 2, #patterns do
    set = set + box:contain_subject(patterns[i])
  end
  return set
end

local function apply_rule(rule_name, rationale, set, action_name, action_fn)
  log('rule=' .. rule_name .. ' action=' .. action_name .. ' rationale="' .. rationale .. '"')
  if set:check_status() then
    log('rule=' .. rule_name .. ' matched=true')
    action_fn(set)
    log('rule=' .. rule_name .. ' action=' .. action_name .. ' status=done')
  else
    log('rule=' .. rule_name .. ' matched=false')
  end
end

-- Keep domains / senders (never delete)
-- Replace these examples with your real domains/senders.
local keep_sender_patterns = {
  'family.example',
  'personal.example',
  'business.example',
  'billing.example',
  'bank.example',
  'hosting.example',
}

-- Subject keywords to protect (never delete)
local protect_subject_keywords = {
  'Rechnung', 'Invoice', 'Bestellung', 'Order', 'Versand',
  'Lizenz', 'License', 'Zugang', 'Login', 'Passwort',
  'Spendenbescheinigung', 'Zuwendungsbest',
}

-- Conversation detection (Re:, Fwd:, Aw:, Wg:)
local protected_conversations = inbox:match_header('^Subject: *(Re:|Fwd:|Aw:|Wg:)')
local protected_senders = union_contains_from(inbox, keep_sender_patterns)
local protected_subjects = union_contains_subject(inbox, protect_subject_keywords)
local protected_set = protected_conversations + protected_senders + protected_subjects

-- Newsletter detection (smart baseline)
local newsletter_sender_patterns = {
  'noreply@', 'no-reply@', 'newsletter@', 'news@', 'promo@',
  'marketing@', 'campaign@', 'deals@', 'offers@', 'sale@',
  'digest@', 'updates@', 'notifications@', 'mailer@', 'bulk@',
}

-- Not every info/hello/team mail is a newsletter; do not add those by default.
local newsletter_candidates = union_contains_from(inbox, newsletter_sender_patterns)

-- Inbox lifecycle: move newsletter candidates to Newsletters after 3 days
local newsletters_to_move = (newsletter_candidates - protected_set) * inbox:is_older(3)
apply_rule(
  'newsletter_archive',
  'newsletter sender pattern + older than 3 days; protected mail excluded',
  newsletters_to_move,
  'move->' .. newsletters_box,
  function(set) set:move_messages(newsletters) end
)

-- Ops notifications lifecycle examples
local ops_candidates = inbox:contain_from('status@') +
  inbox:contain_subject('maintenance') +
  inbox:contain_subject('incident')
local ops_to_move = (ops_candidates - protected_set) * inbox:is_older(1)
apply_rule(
  'ops_archive',
  'ops/status style mail + older than 1 day; protected mail excluded',
  ops_to_move,
  'move->' .. ops_box,
  function(set) set:move_messages(ops) end
)

-- General inbox archive rule after 7 days (except protected and already handled sets)
local already_handled = newsletters_to_move + ops_to_move
local generic_archive = (inbox:select_all() - protected_set - already_handled) * inbox:is_older(7)
apply_rule(
  'generic_archive',
  'inbox mail older than 7 days, excluding protected and already handled sets',
  generic_archive,
  'move->' .. archive_box,
  function(set) set:move_messages(archive) end
)

-- Immediate cleanup examples
local immediate_delete = inbox:contain_from('tracki') + inbox:contain_subject('TESTMODUS') * inbox:is_older(7)
apply_rule(
  'immediate_delete',
  'tracki notifications immediately or TESTMODUS older than 7 days',
  immediate_delete,
  'delete',
  function(set) set:delete_messages() end
)

-- Archive retention rules
-- Newsletters: delete after 90 days, but keep protected mail
local nl_protected = union_contains_from(newsletters, keep_sender_patterns) +
  union_contains_subject(newsletters, protect_subject_keywords) +
  newsletters:match_header('^Subject: *(Re:|Fwd:|Aw:|Wg:)')
local nl_delete = (newsletters:select_all() - nl_protected) * newsletters:is_older(90)
apply_rule(
  'newsletter_retention_delete',
  'newsletter folder messages older than 90 days, except protected',
  nl_delete,
  'delete',
  function(set) set:delete_messages() end
)

-- Operations notifications: delete after 365 days
local ops_delete = ops:select_all() * ops:is_older(365)
apply_rule(
  'ops_retention_delete',
  'operations folder messages older than 365 days',
  ops_delete,
  'delete',
  function(set) set:delete_messages() end
)

-- Generic archive cleanup example for low-value automated mails after 365 days
local archive_low_value = archive:contain_from('noreply@') + archive:contain_from('no-reply@')
local archive_delete = (archive_low_value - union_contains_from(archive, keep_sender_patterns)) * archive:is_older(365)
apply_rule(
  'archive_low_value_delete',
  'archive low-value automated mail older than 365 days, except keep-domain matches',
  archive_delete,
  'delete',
  function(set) set:delete_messages() end
)
