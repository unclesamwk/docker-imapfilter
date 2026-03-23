-- Example IMAPFilter configuration.
--
-- Configure via environment variables in your container runtime:
--   IMAP_SERVER, IMAP_USER, IMAP_PASS
-- Optional:
--   IMAP_PORT (default: 993), IMAP_SSL (default: ssl23)

options.timeout = 120
options.subscribe = true

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
local ssl = get_env_or_file('IMAP_SSL', false) or 'ssl23'

account = IMAP {
  server = server,
  username = username,
  password = password,
  port = port,
  ssl = ssl,
}

-- Example rule: move unread newsletter mails into "Newsletters".
local newsletters = account.INBOX:is_unseen() *
  account.INBOX:contain_from('newsletter@example.com')

pcall(function() account:create_mailbox('Newsletters') end)
newsletters:move_messages(account.Newsletters)
