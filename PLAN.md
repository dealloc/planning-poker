# Planning Poker — Full Implementation Plan

## Context
Build a real-time planning poker tool on top of a fresh Phoenix 1.8 project (no Ecto). All state
is in-memory via GenServer processes. LiveView handles the UI; PubSub broadcasts state changes to all
participants in a lobby; Phoenix Presence tracks online/away status.

---

## Architecture Overview

```
browser ──LiveView WebSocket──► LobbyLive (per user)
                                  │  subscribe("lobby:id")
                                  │  track Presence
                                  ▼
                           PlanningPoker.PubSub
                                  ▲
                           LobbyServer (GenServer, one per lobby)
                           LobbyRegistry (Registry)
                           LobbySupervisor (DynamicSupervisor)
```

---

## File Plan

### New files

| File | Purpose |
|---|---|
| `lib/planning_poker/lobby.ex` | `%Lobby{}` struct + card systems + stats helpers |
| `lib/planning_poker/lobby_server.ex` | GenServer; owns lobby state; broadcasts on change |
| `lib/planning_poker/lobby_supervisor.ex` | `DynamicSupervisor` wrapper |
| `lib/planning_poker/presence.ex` | `Phoenix.Presence` module |
| `lib/planning_poker_web/live/home_live.ex` | Landing page (create / join) |
| `lib/planning_poker_web/live/lobby_live.ex` | Poker table |

### Modified files

| File | Change |
|---|---|
| `lib/planning_poker/application.ex` | Add Registry, LobbySupervisor, Presence to children |
| `lib/planning_poker_web/router.ex` | Replace PageController with live routes |

---

## Data Structures

### `%PlanningPoker.Lobby{}`
```elixir
%Lobby{
  id: String.t(),                         # 6-char random slug
  name: String.t(),
  creator_id: String.t(),
  planning_system: :fibonacci | :tshirt | :powers_of_two | :days,
  auto_reveal: boolean(),
  state: :waiting | :voting | :revealed,
  current_item: nil | %{id: String.t(), title: String.t(), context_url: String.t() | nil},
  votes: %{user_id => card_value},        # only populated during :voting/:revealed
  queue: [%{id, title, context_url}],
  history: [%{item: map(), votes: map(), stats: map()}],
  participants: %{user_id => %{name: String.t(), avatar: String.t(), role: :voter | :spectator}}
}
```

### Planning card systems
```elixir
fibonacci:      ["1","2","3","5","8","13","21","34","55","89","?","∞","☕"]
tshirt:         ["XS","S","M","L","XL","XXL","?","∞"]
powers_of_two:  ["1","2","4","8","16","32","64","?","∞"]
days:           ["1","2","3","4","5","7","10","14","?","∞"]
```

### Session (cookie)
```elixir
%{"user_id" => uuid, "user_name" => string, "user_avatar" => string}
```

### Presence metadata
```elixir
%{name: string, avatar: string, status: :voting | :reading}
```
Topic: `"lobby:#{lobby_id}"`

---

## User Flows

### Create lobby
1. `/` — HomeLive shows "Create" form: name, avatar picker, lobby name, planning system
2. Submit → `LobbyServer.create/1` → redirects to `/lobby/:id`

### Join via shared link
1. `/lobby/:id` — LobbyLive mount checks session
2. No session → `push_navigate` to `/?join=:id`
3. HomeLive shows "Join" form pre-filled with lobby id: name + avatar picker
4. Submit → sets session → redirects to `/lobby/:id`

### Voting round
```
creator: start_item (from queue or inline)
  → LobbyServer sets state: :voting, clears votes
  → broadcast :lobby_updated
participants: vote
  → LobbyServer stores vote, checks auto_reveal
  → if auto_reveal and all voters voted → reveal immediately
creator (or auto): reveal_votes
  → state: :revealed, compute stats
  → broadcast :lobby_updated
creator: reset_round OR next_item OR skip_item
  → state back to :waiting (or :voting for next item)
```

---

## LobbyServer Public API
```elixir
create(attrs)                                :: {:ok, lobby_id}
get(lobby_id)                               :: {:ok, lobby} | {:error, :not_found}
join(lobby_id, user_id, user_attrs)         :: {:ok, lobby} | {:error, :not_found}
leave(lobby_id, user_id)                    :: :ok
vote(lobby_id, user_id, card)               :: {:ok, lobby} | {:error, term}
set_status(lobby_id, user_id, status)       :: :ok          # :voting | :reading
start_item(lobby_id, creator_id, item)      :: {:ok, lobby} | {:error, term}
reveal_votes(lobby_id, creator_id)          :: {:ok, lobby} | {:error, term}
reset_round(lobby_id, creator_id)           :: {:ok, lobby} | {:error, term}
skip_item(lobby_id, creator_id)             :: {:ok, lobby} | {:error, term}
kick(lobby_id, creator_id, user_id)         :: {:ok, lobby} | {:error, term}
add_to_queue(lobby_id, creator_id, item)    :: {:ok, lobby} | {:error, term}
remove_from_queue(lobby_id, creator_id, id) :: {:ok, lobby} | {:error, term}
toggle_auto_reveal(lobby_id, creator_id)    :: {:ok, lobby} | {:error, term}
throw_emoji(lobby_id, from_id, to_id, emoji):: :ok
```

All mutating calls broadcast `{:lobby_updated, lobby}` (and `{:emoji_thrown, ...}` for throws)
on topic `"lobby:#{id}"` via `PlanningPoker.PubSub`.

LobbyServer self-destructs (via `{:stop, :normal, state}`) when the last participant leaves.

---

## LobbyLive assigns
```
lobby            — %Lobby{}
current_user_id  — from session
presence         — map of user_id => metadata from Presence
my_vote          — current user's vote or nil
show_queue_form  — boolean (creator UI)
emoji_events     — list of recent {from, to, emoji} for animation
```

### handle_event
- `"vote"` → `LobbyServer.vote/3`
- `"reveal"` → `LobbyServer.reveal_votes/2`
- `"reset_round"` → `LobbyServer.reset_round/2`
- `"next_item"` → `LobbyServer.start_item/3` with head of queue
- `"skip_item"` → `LobbyServer.skip_item/2`
- `"kick"` → `LobbyServer.kick/3`
- `"throw_emoji"` → `LobbyServer.throw_emoji/4`
- `"add_to_queue"` → `LobbyServer.add_to_queue/3`
- `"remove_from_queue"` → `LobbyServer.remove_from_queue/3`
- `"toggle_auto_reveal"` → `LobbyServer.toggle_auto_reveal/2`
- `"blur"` / `"focus"` → `Presence.update/4` to flip status + `LobbyServer.set_status/3`
- `"start_item"` → `LobbyServer.start_item/3`

### handle_info
- `{:lobby_updated, lobby}` → `assign(socket, :lobby, lobby)`
- `{:emoji_thrown, from, to, emoji}` → `push_event(socket, "emoji_thrown", ...)` for JS hook
- Presence diffs → update `presence` assign

---

## Tab focus tracking
```heex
<div phx-window-event="blur" phx-value-event="blur"
     phx-window-event="focus" phx-value-event="focus">
```
Actually use two separate event bindings:
`phx-window-blur="blur"` and `phx-window-focus="focus"` — zero JS needed.

---

## Statistics (computed on reveal)
```elixir
# Numeric votes only (exclude "?", "∞", "☕")
avg    = sum / count  (1 decimal place)
median = middle value
min    = lowest
max    = highest
consensus? = all numeric votes identical
distribution = %{card => vote_count}
```

---

## Emoji throw animation
1. `LobbyServer.throw_emoji/4` → broadcast `{:emoji_thrown, from, to, emoji}`
2. LobbyLive `handle_info` → `push_event(socket, "emoji_thrown", %{from:, to:, emoji:, target_el: "participant-#{to}"})`
3. Colocated JS hook on the table div animates a floating emoji toward the target DOM element

---

## Avatars
16 pre-set animal emoji: 🐶🐱🐭🐹🐰🦊🐻🐼🐨🐯🦁🐸🐵🐙🦋🦄

---

## Routes (final router.ex)
```elixir
scope "/", PlanningPokerWeb do
  pipe_through :browser

  live "/", HomeLive
  live "/lobby/:id", LobbyLive
end
```

---

## application.ex additions
```elixir
{Registry, keys: :unique, name: PlanningPoker.LobbyRegistry},
PlanningPoker.LobbySupervisor,
PlanningPoker.Presence,
```

---

## Verification
1. `iex -S mix phx.server`
2. Open `http://localhost:4000` — HomeLive renders with create/join forms
3. Create a lobby, get redirected to `/lobby/:id`
4. Open incognito tab, go to same URL, enter name → joins lobby
5. Vote from both tabs, verify auto-reveal (if enabled) or manual reveal
6. Tab blur on one → participant shows "reading" status
7. Emoji throw → floats across screen to target
8. Creator reveals → stats panel shows avg/median/consensus
9. History panel shows completed rounds
10. `mix precommit` passes clean
