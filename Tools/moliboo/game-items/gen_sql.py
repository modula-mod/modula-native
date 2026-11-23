import json
c=json.load(open('catalogue.json'))
def q(v):
  if v is None: return 'NULL'
  if isinstance(v,(dict,list)): return "'"+json.dumps(v).replace("'","''")+"'::jsonb"
  if isinstance(v,bool): return 'TRUE' if v else 'FALSE'
  if isinstance(v,(int,float)): return str(v)
  return "'"+str(v).replace("'","''")+"'"
L=[]
L.append("""-- MOLIBOO-GAME-SYSTEMS-01: items catalogue, inventory, outfits (curated sets +
-- user-saved loadouts), equipped looks, signature skills, timed buffs, quests
-- and achievements. All ownership/progress is server-authoritative. Catalogue
-- rows are cosmetic only: no item, skill or buff changes competitive outcomes.
-- Generated catalogue seed: docs/moliboo/game-catalogue.v1.json (version 1).

CREATE TABLE greenfield_moliboo_items (
  item_id TEXT PRIMARY KEY CHECK (item_id ~ '^moliboo\\.item\\.[a-z0-9_]+$'),
  name TEXT NOT NULL CHECK (char_length(name) BETWEEN 1 AND 80),
  slot TEXT NOT NULL CHECK (slot IN ('headwear','hair','face','top','outerwear','bottom','footwear','back','handheld','aura')),
  rarity TEXT NOT NULL CHECK (rarity IN ('common','uncommon','rare','epic','legendary')),
  access TEXT NOT NULL CHECK (access IN ('free','earnable','premium')),
  family TEXT,
  set_id TEXT,
  icon_key TEXT NOT NULL,
  palette JSONB NOT NULL DEFAULT '[]'::jsonb CHECK (jsonb_typeof(palette) = 'array'),
  sort_order INTEGER NOT NULL DEFAULT 0,
  active BOOLEAN NOT NULL DEFAULT TRUE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX greenfield_moliboo_items_slot_idx ON greenfield_moliboo_items(slot, sort_order);

CREATE TABLE greenfield_moliboo_outfit_sets (
  set_id TEXT PRIMARY KEY CHECK (set_id ~ '^moliboo\\.outfit\\.[a-z0-9_]+$'),
  name TEXT NOT NULL,
  family TEXT,
  access TEXT NOT NULL CHECK (access IN ('free','earnable','premium')),
  rarity TEXT NOT NULL CHECK (rarity IN ('common','uncommon','rare','epic','legendary')),
  item_ids JSONB NOT NULL CHECK (jsonb_typeof(item_ids) = 'array' AND jsonb_array_length(item_ids) BETWEEN 2 AND 10),
  icon_key TEXT NOT NULL,
  set_bonus_buff_id TEXT,
  sort_order INTEGER NOT NULL DEFAULT 0,
  active BOOLEAN NOT NULL DEFAULT TRUE
);

CREATE TABLE greenfield_moliboo_buff_definitions (
  buff_id TEXT PRIMARY KEY,
  name TEXT NOT NULL,
  description TEXT NOT NULL,
  duration_seconds INTEGER CHECK (duration_seconds IS NULL OR duration_seconds BETWEEN 60 AND 604800),
  stack_rule TEXT NOT NULL CHECK (stack_rule IN ('refresh','stack','while_equipped')),
  max_stacks INTEGER NOT NULL DEFAULT 1 CHECK (max_stacks BETWEEN 1 AND 5),
  exclusive_group TEXT,
  effects JSONB NOT NULL DEFAULT '{}'::jsonb CHECK (jsonb_typeof(effects) = 'object')
);

CREATE TABLE greenfield_moliboo_skills (
  skill_id TEXT PRIMARY KEY,
  character_id TEXT NOT NULL UNIQUE,
  family TEXT NOT NULL,
  name TEXT NOT NULL,
  description TEXT NOT NULL,
  cooldown_seconds INTEGER NOT NULL CHECK (cooldown_seconds BETWEEN 60 AND 86400),
  grants_buff_id TEXT REFERENCES greenfield_moliboo_buff_definitions(buff_id)
);

CREATE TABLE greenfield_moliboo_quests (
  quest_id TEXT PRIMARY KEY,
  kind TEXT NOT NULL CHECK (kind IN ('daily','weekly','achievement','collection')),
  title TEXT NOT NULL,
  description TEXT NOT NULL,
  event_type TEXT NOT NULL CHECK (event_type IN ('care','skill_use','equip','outfit_saved','activity_complete')),
  family_filter TEXT,
  target INTEGER NOT NULL CHECK (target BETWEEN 1 AND 1000),
  reward JSONB NOT NULL CHECK (jsonb_typeof(reward) = 'object'),
  sort_order INTEGER NOT NULL DEFAULT 0,
  active BOOLEAN NOT NULL DEFAULT TRUE
);

-- Ownership. Free items are usable by everyone and are never written here;
-- rows exist only for evidence-backed grants (quest, achievement, premium
-- entitlement, admin grant). Never fabricated client-side.
CREATE TABLE greenfield_moliboo_inventory (
  account_id TEXT NOT NULL REFERENCES greenfield_accounts(account_id) ON DELETE CASCADE,
  item_id TEXT NOT NULL REFERENCES greenfield_moliboo_items(item_id),
  source TEXT NOT NULL CHECK (source IN ('quest','achievement','collection','premium_entitlement','admin_grant','gift')),
  source_ref TEXT NOT NULL,
  acquired_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  revoked_at TIMESTAMPTZ,
  PRIMARY KEY (account_id, item_id)
);

CREATE TABLE greenfield_moliboo_user_outfits (
  outfit_id TEXT PRIMARY KEY,
  account_id TEXT NOT NULL REFERENCES greenfield_accounts(account_id) ON DELETE CASCADE,
  name TEXT NOT NULL CHECK (char_length(name) BETWEEN 1 AND 40),
  character_id TEXT,
  item_ids JSONB NOT NULL CHECK (jsonb_typeof(item_ids) = 'array'),
  revision INTEGER NOT NULL DEFAULT 1,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX greenfield_moliboo_user_outfits_account_idx ON greenfield_moliboo_user_outfits(account_id, updated_at DESC);

CREATE TABLE greenfield_moliboo_equipped (
  account_id TEXT NOT NULL REFERENCES greenfield_accounts(account_id) ON DELETE CASCADE,
  character_id TEXT NOT NULL CHECK (character_id ~ '^moliboo\\.[a-z0-9_]+\\.[a-z0-9_]+$'),
  item_ids JSONB NOT NULL DEFAULT '[]'::jsonb CHECK (jsonb_typeof(item_ids) = 'array'),
  source_set_id TEXT,
  source_outfit_id TEXT,
  revision INTEGER NOT NULL DEFAULT 1,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  PRIMARY KEY (account_id, character_id)
);

CREATE TABLE greenfield_moliboo_active_buffs (
  account_id TEXT NOT NULL REFERENCES greenfield_accounts(account_id) ON DELETE CASCADE,
  character_id TEXT NOT NULL,
  buff_id TEXT NOT NULL REFERENCES greenfield_moliboo_buff_definitions(buff_id),
  stacks INTEGER NOT NULL DEFAULT 1 CHECK (stacks BETWEEN 1 AND 5),
  source TEXT NOT NULL,
  started_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  expires_at TIMESTAMPTZ NOT NULL,
  PRIMARY KEY (account_id, character_id, buff_id)
);

-- Append-only, idempotent event log feeding quests/achievements.
CREATE TABLE greenfield_moliboo_events (
  event_id TEXT PRIMARY KEY,
  account_id TEXT NOT NULL REFERENCES greenfield_accounts(account_id) ON DELETE CASCADE,
  event_type TEXT NOT NULL,
  character_id TEXT,
  detail JSONB NOT NULL DEFAULT '{}'::jsonb,
  idempotency_key TEXT,
  occurred_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE (account_id, idempotency_key)
);
CREATE INDEX greenfield_moliboo_events_account_idx ON greenfield_moliboo_events(account_id, event_type, occurred_at DESC);

CREATE TABLE greenfield_moliboo_quest_progress (
  account_id TEXT NOT NULL REFERENCES greenfield_accounts(account_id) ON DELETE CASCADE,
  quest_id TEXT NOT NULL REFERENCES greenfield_moliboo_quests(quest_id),
  period_key TEXT NOT NULL,
  progress INTEGER NOT NULL DEFAULT 0,
  completed_at TIMESTAMPTZ,
  claimed_at TIMESTAMPTZ,
  reward_grant JSONB,
  PRIMARY KEY (account_id, quest_id, period_key)
);

CREATE TABLE greenfield_moliboo_friendship (
  account_id TEXT NOT NULL REFERENCES greenfield_accounts(account_id) ON DELETE CASCADE,
  character_id TEXT NOT NULL,
  xp INTEGER NOT NULL DEFAULT 0 CHECK (xp >= 0),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  PRIMARY KEY (account_id, character_id)
);
""")
for b in c['buffs']:
  L.append(f"INSERT INTO greenfield_moliboo_buff_definitions VALUES ({q(b['buffId'])},{q(b['name'])},{q(b['description'])},{q(b['durationSeconds'])},{q(b['stackRule'])},{b['maxStacks']},{q(b['exclusiveGroup'])},{q(b['effects'])});")
for n,i in enumerate(c['items']):
  L.append(f"INSERT INTO greenfield_moliboo_items (item_id,name,slot,rarity,access,family,set_id,icon_key,palette,sort_order) VALUES ({q(i['itemId'])},{q(i['name'])},{q(i['slot'])},{q(i['rarity'])},{q(i['access'])},{q(i['family'])},{q(i['setId'])},{q(i['iconKey'])},{q(i['palette'])},{n});")
for n,o in enumerate(c['outfits']):
  L.append(f"INSERT INTO greenfield_moliboo_outfit_sets (set_id,name,family,access,rarity,item_ids,icon_key,set_bonus_buff_id,sort_order) VALUES ({q(o['setId'])},{q(o['name'])},{q(o['family'])},{q(o['access'])},{q(o['rarity'])},{q(o['itemIds'])},{q(o['iconKey'])},{q(o['setBonus']['buffId'])},{n});")
for s in c['skills']:
  L.append(f"INSERT INTO greenfield_moliboo_skills VALUES ({q(s['skillId'])},{q(s['characterId'])},{q(s['family'])},{q(s['name'])},{q(s['description'])},{s['cooldownSeconds']},{q(s['grantsBuffId'])});")
for n,x in enumerate(c['quests']):
  L.append(f"INSERT INTO greenfield_moliboo_quests (quest_id,kind,title,description,event_type,family_filter,target,reward,sort_order) VALUES ({q(x['questId'])},{q(x['kind'])},{q(x['title'])},{q(x['description'])},{q(x['eventType'])},{q(x.get('familyFilter'))},{x['target']},{q(x['reward'])},{n});")
CAT="greenfield_moliboo_items, greenfield_moliboo_outfit_sets, greenfield_moliboo_buff_definitions, greenfield_moliboo_skills, greenfield_moliboo_quests"
USR="greenfield_moliboo_inventory, greenfield_moliboo_user_outfits, greenfield_moliboo_equipped, greenfield_moliboo_active_buffs, greenfield_moliboo_quest_progress, greenfield_moliboo_friendship"
L.append(f"\nGRANT SELECT ON {CAT} TO modula_api, modula_worker;\nGRANT SELECT, INSERT, UPDATE, DELETE ON {USR} TO modula_api, modula_worker;\nGRANT SELECT, INSERT ON greenfield_moliboo_events TO modula_api, modula_worker;\nGRANT SELECT ON {CAT}, {USR}, greenfield_moliboo_events TO modula_backup;")
L.append("\nINSERT INTO schema_metadata (key, value) VALUES ('schema_version', '080')\nON CONFLICT (key) DO UPDATE SET value=EXCLUDED.value, updated_at=NOW();\n")
open('be/migrations/080_moliboo_game_systems.sql','w').write('\n'.join(L))
open('be/migrations/080_moliboo_game_systems.down.sql','w').write('\n'.join(f'DROP TABLE IF EXISTS {t};' for t in ['greenfield_moliboo_friendship','greenfield_moliboo_quest_progress','greenfield_moliboo_events','greenfield_moliboo_active_buffs','greenfield_moliboo_equipped','greenfield_moliboo_user_outfits','greenfield_moliboo_inventory','greenfield_moliboo_quests','greenfield_moliboo_skills','greenfield_moliboo_buff_definitions','greenfield_moliboo_outfit_sets','greenfield_moliboo_items'])+"\n\nUPDATE schema_metadata SET value = '079', updated_at = NOW() WHERE key = 'schema_version';\n")
