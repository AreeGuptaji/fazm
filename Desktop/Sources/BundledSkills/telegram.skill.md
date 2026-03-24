---
name: telegram
description: Connect your Telegram account so Fazm can send and receive messages on your behalf. Fully programmatic setup — just enter your phone number.
---

# Telegram Integration

Connect the user's Telegram account so Fazm can send and receive messages programmatically. Uses telethon (Python MTProto client) — no bots, no browser automation.

## Prerequisites

Ensure telethon is installed:

```bash
pip3 install telethon
```

## API Credentials

Fazm uses these app-level credentials (Telegram Desktop's open-source keys):

```
api_id = 611335
api_hash = 'd524b414d21f4d37f08684c1df41ac9c'
```

## Setup Flow

The entire setup is 2 steps for the user: enter phone number, enter code.

### Step 1: Request auth code

Ask the user for their phone number (with country code, e.g. +16507961489), then run:

```python
import asyncio
from telethon import TelegramClient

api_id = 611335
api_hash = 'd524b414d21f4d37f08684c1df41ac9c'
session_path = os.path.expanduser('~/.fazm/telegram.session')

async def request_code(phone):
    client = TelegramClient(session_path, api_id, api_hash)
    await client.connect()
    result = await client.send_code_request(phone)
    # Save phone_code_hash for step 2
    with open('/tmp/telegram_code_hash.txt', 'w') as f:
        f.write(result.phone_code_hash)
    print(f"Code sent to {phone}")
    await client.disconnect()

asyncio.run(request_code('+1XXXXXXXXXX'))
```

Tell the user: "Check your Telegram app — a code was just sent from Telegram's official account."

### Step 2: Sign in with the code

Ask the user for the code they received, then run:

```python
async def sign_in(phone, code):
    client = TelegramClient(session_path, api_id, api_hash)
    await client.connect()
    phone_code_hash = open('/tmp/telegram_code_hash.txt').read().strip()
    await client.sign_in(phone, code, phone_code_hash=phone_code_hash)
    me = await client.get_me()
    print(f"Authenticated as: {me.first_name} (ID: {me.id})")
    await client.disconnect()

asyncio.run(sign_in('+1XXXXXXXXXX', 'CODE'))
```

If the user has two-step verification (2FA), catch `SessionPasswordNeededError` and ask for their Telegram password:

```python
from telethon.errors import SessionPasswordNeededError

try:
    await client.sign_in(phone, code, phone_code_hash=phone_code_hash)
except SessionPasswordNeededError:
    password = input("Enter your Telegram 2FA password: ")
    await client.sign_in(password=password)
```

### Step 3: Verify and test

Send a test message to the user's Saved Messages:

```python
async def test():
    client = TelegramClient(session_path, api_id, api_hash)
    await client.start()
    await client.send_message('me', 'Fazm connected successfully!')
    me = await client.get_me()
    print(f"Connected as {me.first_name}, message sent to Saved Messages")
    await client.disconnect()

asyncio.run(test())
```

Tell the user to check their Telegram Saved Messages to confirm.

## Sending Messages (after setup)

Once authenticated, the session persists. No re-auth needed.

```python
async def send(recipient, message):
    client = TelegramClient(session_path, api_id, api_hash)
    await client.start()

    # By username
    await client.send_message('@username', message)

    # By phone number (must be in contacts)
    await client.send_message('+1234567890', message)

    # To self (Saved Messages)
    await client.send_message('me', message)

    # By user ID (must resolve entity first)
    async for dialog in client.iter_dialogs(limit=100):
        if target_name.lower() in dialog.name.lower():
            await client.send_message(dialog.entity, message)
            break

    await client.disconnect()
```

## Reading Messages

```python
async def read_recent(chat, limit=10):
    client = TelegramClient(session_path, api_id, api_hash)
    await client.start()
    async for msg in client.iter_messages(chat, limit=limit):
        print(f"{msg.sender.first_name}: {msg.text}")
    await client.disconnect()
```

## Session Management

- Session file: `~/.fazm/telegram.session`
- To check if already authenticated: `await client.is_user_authorized()`
- To disconnect/logout: `await client.log_out()`
- Session files grant full account access — never expose or commit to git

## Troubleshooting

- **"Could not find the input entity"**: The user ID isn't cached yet. Iterate dialogs first with `client.iter_dialogs()` to populate the entity cache.
- **Rate limited**: Telegram throttles automated sends. Space out messages, don't mass-send.
- **FloodWaitError**: Too many requests. Wait the number of seconds specified in the error before retrying.
- **SessionPasswordNeededError**: User has 2FA enabled. Ask for their Telegram password.
