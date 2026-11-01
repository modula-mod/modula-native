import json,re
chars=json.load(open('/workspace/moli_chars.json'))
FAM={
 'angels':dict(label='Angels',pal=['#EDB94A','#8CCBFF','#FFF4D6','#9A6B1F']),
 'underground':dict(label='Underground',pal=['#FF4FA3','#36E3F0','#2B2B3D','#B6FF5C']),
 'enchanted':dict(label='Enchanted',pal=['#5BAE6A','#B0306A','#8FCB7B','#3E6B3A']),
 'stardust':dict(label='Stardust',pal=['#3A3FA8','#FFD45C','#8A6BE8','#1E2160']),
 'dreamers':dict(label='Dreamers',pal=['#B9A7F2','#8EC5FF','#FFC9A8','#6B5BB5']),
}
# 15 full outfits: (family, id, name, access, rarity, {slot:(itemname, shape)})
O=[
('angels','halo_choir','Halo Choir','free','common',{'headwear':('Halo Ring','halo'),'hair':('Cloud Curls','curls'),'top':('Pearl Tunic','tunic'),'back':('Feather Wings','wings'),'aura':('Soft Glow','glow')}),
('angels','sunrise_herald','Sunrise Herald','earnable','rare',{'headwear':('Sunray Crown','crown'),'hair':('Golden Sweep','sweep'),'top':('Dawn Cape Top','tunic'),'handheld':('Little Trumpet','trumpet'),'aura':('Sunbeam Aura','rays')}),
('angels','celestial_guardian','Celestial Guardian','premium','legendary',{'headwear':('Guardian Circlet','tiara'),'hair':('Pearl Locks','locks'),'outerwear':('Guardian Mantle','cape'),'back':('Shield Wings','wings'),'aura':('Gilded Halo FX','rays')}),
('underground','neon_skater','Neon Skater','free','common',{'headwear':('Neon Cap','cap'),'hair':('Spiky Tuft','spiky'),'top':('Glow Hoodie','hoodie'),'footwear':('Light-up Kicks','shoes'),'handheld':('Mini Board','board')}),
('underground','beat_crew','Beat Crew','earnable','rare',{'headwear':('Studio Headphones','headphones'),'hair':('Pixel Fringe','fringe'),'top':('Bass Tee','tee'),'face':('Visor Shades','shades'),'aura':('Sound Rings','rings')}),
('underground','holo_runner','Holo Runner','premium','epic',{'headwear':('Holo Visor Band','band'),'hair':('Circuit Mohawk','mohawk'),'outerwear':('Hologram Jacket','jacket'),'footwear':('Spark Sneakers','shoes'),'aura':('Glitch Trail','glitch')}),
('enchanted','mossy_ranger','Mossy Ranger','free','common',{'headwear':('Leaf Cap','leafcap'),'hair':('Leaf Fringe','fringe'),'top':('Fern Vest','tunic'),'back':('Acorn Pack','pack'),'handheld':('Twig Wand','wand')}),
('enchanted','berry_bard','Berry Bard','earnable','uncommon',{'headwear':('Bramble Beret','beret'),'hair':('Berry Buns','buns'),'top':('Petal Blouse','tee'),'handheld':('Reed Flute','trumpet'),'aura':('Petal Drift','petals')}),
('enchanted','elder_grove','Elder Grove','premium','legendary',{'headwear':('Antler Crown','antlers'),'hair':('Moss Mane','locks'),'outerwear':('Bark Cloak','cape'),'face':('Firefly Freckles','freckles'),'aura':('Spore Sparkles','sparkle')}),
('stardust','comet_cadet','Comet Cadet','free','common',{'headwear':('Star Headband','band'),'hair':('Star Parting','sweep'),'top':('Cadet Jumpsuit','hoodie'),'footwear':('Moon Boots','boots'),'back':('Mini Jetpack','pack')}),
('stardust','constellation_scout','Constellation Scout','earnable','rare',{'headwear':('Explorer Helmet','helmet'),'hair':('Nebula Tuft','curls'),'outerwear':('Star Map Poncho','cape'),'handheld':('Pocket Telescope','telescope'),'aura':('Star Trail','sparkle')}),
('stardust','aurora_navigator','Aurora Navigator','premium','epic',{'headwear':('Aurora Tiara','tiara'),'hair':('Aurora Bangs','fringe'),'outerwear':('Ribbon Coat','jacket'),'face':('Stardust Gems','freckles'),'aura':('Aurora Veil','glow')}),
('dreamers','sleepy_star','Sleepy Star','free','common',{'headwear':('Starry Nightcap','nightcap'),'hair':('Fluffy Tuft','curls'),'top':('Cloud Pyjamas','tee'),'footwear':('Bunny Slippers','slippers'),'handheld':('Plush Star','star')}),
('dreamers','lullaby_lantern','Lullaby Lantern','earnable','uncommon',{'headwear':('Moon Bonnet','nightcap'),'hair':('Wavy Fringe','fringe'),'outerwear':('Quilt Cape','cape'),'handheld':('Dream Lantern','lantern'),'aura':('Lullaby Notes','notes')}),
('dreamers','dream_keeper','Dream Keeper','premium','legendary',{'headwear':('Moonring Crown','crown'),'hair':('Silver Drift Locks','locks'),'outerwear':('Night-Sky Robe','cape'),'face':('Sleep Mask','mask'),'aura':('Dream Bubbles','bubbles')}),
]
EXTRA=[('angels','face','Heart Cheeks','freckles','free','common'),('angels','footwear','Cloud Sandals','slippers','free','common'),
 ('underground','back','Spray Can Pack','pack','free','common'),('underground','bottom','Cargo Shorts','shorts','free','common'),
 ('enchanted','footwear','Mushroom Boots','boots','free','common'),('enchanted','bottom','Leaf Skirt','skirt','earnable','uncommon'),
 ('stardust','face','Star Glasses','shades','free','common'),('stardust','bottom','Orbit Shorts','shorts','free','common'),
 ('dreamers','back','Pillow Backpack','pack','free','common'),('dreamers','bottom','Cosy Leggings','skirt','earnable','uncommon'),
 (None,'headwear','Party Cone','cone','free','common'),(None,'headwear','Knit Beanie','beanie','free','common'),(None,'face','Round Glasses','glasses','free','common')]
items=[];outfits=[]
def sid(s): return re.sub(r'[^a-z0-9]+','_',s.lower()).strip('_')
for fam,oid,name,acc,rar,slots in O:
  ids=[]
  for slot,(nm,shape) in slots.items():
    iid=f'moliboo.item.{sid(nm)}'
    items.append(dict(itemId=iid,name=nm,slot=slot,rarity=rar,access=acc,family=fam,setId=f'moliboo.outfit.{oid}',iconKey=f'item_{sid(nm)}',shape=shape,palette=FAM[fam]['pal']))
    ids.append(iid)
  outfits.append(dict(setId=f'moliboo.outfit.{oid}',name=name,family=fam,access=acc,rarity=rar,itemIds=ids,iconKey=f'outfit_{oid}',
    setBonus=dict(buffId=f'moliboo.buff.set_{oid}',label=f'{name} set glow',kind='cosmetic')))
for fam,slot,nm,shape,acc,rar in EXTRA:
  items.append(dict(itemId=f'moliboo.item.{sid(nm)}',name=nm,slot=slot,rarity=rar,access=acc,family=fam,setId=None,iconKey=f'item_{sid(nm)}',shape=shape,palette=FAM[fam or 'dreamers']['pal'] if fam else ['#FF8FB1','#7FD3FF','#FFE17A','#6C63FF']))
assert len({i['itemId'] for i in items})==len(items)
# skills
skills=[]
for c in chars:
  m=re.match(r'([A-Z][\w\' -]+?)\s*[:/]\s*(.+)',c['ability'])
  if m: nm,desc=m.group(1).strip(),m.group(2).strip()
  else:
    t=c['ability'].split(); k=next(k for k in range(1,len(t)-1) if t[k][0].isupper() and t[k+1][0].islower())
    nm,desc=' '.join(t[:k]),' '.join(t[k:])
  desc=desc[0].upper()+desc[1:]
  cid=f"moliboo.{c['family']}.{sid(c['name'])}"
  skills.append(dict(skillId=f"moliboo.skill.{sid(c['name'])}",characterId=cid,characterName=c['name'],family=c['family'],name=nm,description=desc[:240],
    cooldownSeconds=4*3600,grantsBuffId=f"moliboo.buff.signature_{c['family']}"))
buffs=[
 dict(buffId='moliboo.buff.well_fed',name='Well Fed',description='Your Moliboo is content after a snack.',durationSeconds=3*3600,stackRule='refresh',maxStacks=1,exclusiveGroup=None,effects={'fx':'cheek_glow','friendshipXpBonusPct':10}),
 dict(buffId='moliboo.buff.playful',name='Playful',description='Bouncy and ready for mini-games.',durationSeconds=2*3600,stackRule='stack',maxStacks=3,exclusiveGroup=None,effects={'fx':'bounce_sparkle','friendshipXpBonusPct':5}),
 dict(buffId='moliboo.buff.well_rested',name='Well Rested',description='A good nap; calm idle animations.',durationSeconds=6*3600,stackRule='refresh',maxStacks=1,exclusiveGroup='mood',effects={'fx':'calm_idle','friendshipXpBonusPct':10}),
 dict(buffId='moliboo.buff.fresh_groomed',name='Freshly Groomed',description='Shiny and fluffy.',durationSeconds=4*3600,stackRule='refresh',maxStacks=1,exclusiveGroup=None,effects={'fx':'shine'}),
 dict(buffId='moliboo.buff.chatty',name='Chatty',description='Enjoyed a chat with you.',durationSeconds=2*3600,stackRule='stack',maxStacks=2,exclusiveGroup='mood',effects={'fx':'speech_hearts','friendshipXpBonusPct':5}),
]+[dict(buffId=f'moliboo.buff.signature_{f}',name=f"{FAM[f]['label']} Signature Glow",description='Afterglow from a signature skill.',durationSeconds=45*60,stackRule='refresh',maxStacks=1,exclusiveGroup='signature',effects={'fx':f'signature_{f}'}) for f in FAM
]+[dict(buffId=o['setBonus']['buffId'],name=o['setBonus']['label'],description='Active while the complete set is equipped.',durationSeconds=None,stackRule='while_equipped',maxStacks=1,exclusiveGroup='set',effects={'fx':f"set_{o['setId'].split('.')[-1]}"}) for o in outfits]
for b in buffs: b['effects']['capPct']=25  # total friendship XP bonus capped server-side
free_pool=[i['itemId'] for i in items if i['access']=='free'][:0]
earn=[i['itemId'] for i in items if i['access']=='earnable']
quests=[
 dict(questId='moliboo.quest.daily_care_trio',kind='daily',title='Care trio',description='Do any 3 care actions with any Moliboo.',eventType='care',target=3,reward={'type':'friendship_xp','amount':30}),
 dict(questId='moliboo.quest.daily_signature',kind='daily',title='Show-off',description='Use one signature skill.',eventType='skill_use',target=1,reward={'type':'friendship_xp','amount':20}),
 dict(questId='moliboo.quest.daily_dressup',kind='daily',title='Dress-up',description='Equip an outfit or change one item.',eventType='equip',target=1,reward={'type':'friendship_xp','amount':15}),
 dict(questId='moliboo.quest.weekly_caretaker',kind='weekly',title='Weekly caretaker',description='Do 15 care actions this week (no streak needed).',eventType='care',target=15,reward={'type':'surprise_item','pool':earn,'disclosed':True}),
 dict(questId='moliboo.quest.ach_first_outfit',kind='achievement',title='First Outfit',description='Save your first own outfit.',eventType='outfit_saved',target=1,reward={'type':'item','itemId':'moliboo.item.cloud_curls'}),
 dict(questId='moliboo.quest.ach_stylist',kind='achievement',title='Stylist',description='Save 5 outfits.',eventType='outfit_saved',target=5,reward={'type':'item','itemId':'moliboo.item.petal_drift'}),
 dict(questId='moliboo.quest.ach_skill_explorer',kind='achievement',title='Skill explorer',description='Use 10 signature skills.',eventType='skill_use',target=10,reward={'type':'item','itemId':'moliboo.item.star_trail'}),
 dict(questId='moliboo.quest.ach_caretaker_50',kind='achievement',title='Devoted friend',description='Do 50 care actions in total.',eventType='care',target=50,reward={'type':'item','itemId':'moliboo.item.lullaby_notes'}),
 dict(questId='moliboo.quest.ach_mini_games',kind='achievement',title='Mini-game fan',description='Finish 5 mini-activities (Bubble Pop, Star Catch, Memory Match).',eventType='activity_complete',target=5,reward={'type':'item','itemId':'moliboo.item.sound_rings'}),
 dict(questId='moliboo.quest.daily_activity',kind='daily',title='Play time',description='Finish one mini-activity.',eventType='activity_complete',target=1,reward={'type':'friendship_xp','amount':20}),
]
# earnable items not rewarded directly get reward via collection quests
rewarded={q['reward'].get('itemId') for q in quests}
for o in outfits:
  if o['access']=='earnable':
    for iid in o['itemIds']:
      if iid not in rewarded:
        quests.append(dict(questId=f"moliboo.quest.collect_{iid.split('.')[-1]}",kind='collection',title=f"Unlock {next(i['name'] for i in items if i['itemId']==iid)}",
          description=f"Do 8 care actions with a {FAM[o['family']]['label']} Moliboo.",eventType='care',familyFilter=o['family'],target=8,reward={'type':'item','itemId':iid})); rewarded.add(iid)
for i in items:
  if i['access']=='earnable' and i['itemId'] not in rewarded:
    quests.append(dict(questId=f"moliboo.quest.collect_{i['itemId'].split('.')[-1]}",kind='collection',title=f"Unlock {i['name']}",description='Finish 3 mini-activities.',eventType='activity_complete',target=3,reward={'type':'item','itemId':i['itemId']}));rewarded.add(i['itemId'])
cat=dict(schema='modula.moliboo.game-catalogue.v1',version=1,families=FAM,items=items,outfits=outfits,skills=skills,buffs=buffs,quests=quests,
 careActions={'feed':'moliboo.buff.well_fed','play':'moliboo.buff.playful','rest':'moliboo.buff.well_rested','groom':'moliboo.buff.fresh_groomed','talk':'moliboo.buff.chatty'},
 activities=['bubble_pop','star_catch','memory_match'])
json.dump(cat,open('catalogue.json','w'),indent=1)
from collections import Counter
print(len(items),len(outfits),len(skills),len(buffs),len(quests),Counter(i['access'] for i in items),Counter(i['slot'] for i in items))
print(skills[0],skills[40])
