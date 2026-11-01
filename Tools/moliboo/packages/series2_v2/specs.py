# num: (body, features, eyes, mouth, overrides)   eyes: bead|sparkle|happy|wink   mouth: smile|open|cat|o|fang|beak
SPECS = {
 # Tideborn — ocean
 116: ("drop", ["wave", "belly"], "sparkle", "open", {}),                 # Brinlo: big curling wave crest
 117: ("round", ["gills", "feet"], "happy", "cat", {}),                    # Calyra: axolotl frills
 118: ("flat", ["manta"], "bead", "smile", {"mid": "#3d4a8a"}),            # Dovvi: manta ray
 119: ("mochi", ["shellhood", "pearl"], "bead", "smile", {}),             # Shelumi: shell hood
 120: ("round", ["jelly", "tentacles"], "sparkle", "o", {}),              # Nerlo: jellyfish
 121: ("round", ["spikes"], "happy", "open", {"mid": "#f6c24a"}),         # Quibby: puffer
 122: ("egg", ["floppy", "scarf", "starsprinkle"], "bead", "smile", {}),  # Tavaroo
 123: ("mochi", ["clam", "pearl"], "bead", "o", {}),                      # Ostra: oyster
 124: ("tall", ["finears", "fishtail"], "wink", "smile", {}),             # Vaeli: sea sprite
 125: ("wide", ["floppy", "sailorhat"], "bead", "cat", {}),               # Driftu
 # Skyweavers — wind & sky
 126: ("round", ["kite", "arms"], "bead", "open", {}),                    # Zeppi: kite
 127: ("cloud", ["cloudears"], "happy", "smile", {}),                     # Cirra
 128: ("egg", ["birdwings", "crest"], "wink", "beak", {}),                # Flaro
 129: ("cloud", ["storm"], "bead", "fang", {"mid": "#5a5f70"}),           # Nimbuski: storm cloud
 130: ("round", ["propeller", "feet"], "happy", "open", {}),              # Breezo: leaf propeller
 131: ("cloud", ["starsprinkle", "belly"], "sparkle", "cat", {}),         # Poffa
 132: ("tall", ["bigwings", "windtuft"], "sparkle", "open", {"acc": "#cfe2ff"}),  # Aerin: huge swept wings
 133: ("ghost", ["wisp"], "bead", "o", {}),                               # Whispel
 134: ("round", ["birdwings", "cape"], "bead", "beak", {}),               # Gustra
 135: ("round", ["sunrays"], "happy", "open", {"acc": "#ffc23d"}),        # Solviq: sun
 # Cinderlings — fire
 136: ("lumpy", ["smoke", "embers"], "bead", "smile", {"mid": "#3b3540", "acc": "#ff9a3c"}),  # Ashumo
 137: ("round", ["flame", "feet"], "wink", "open", {}),                   # Fizzra
 138: ("round", ["flamewings"], "bead", "fang", {}),                      # Cindoo
 139: ("drop", ["lavaglow"], "sparkle", "smile", {"mid": "#e0413a", "acc": "#ffb347"}),  # Magmi
 140: ("lumpy", ["cracks"], "bead", "o", {"mid": "#2f2b30", "acc": "#ff8a2a"}),          # Kohli: coal
 141: ("round", ["ramhorns", "belly"], "happy", "smile", {}),             # Brasa
 142: ("mochi", ["stonehood"], "bead", "smile", {"mid": "#8a8f9a", "acc": "#5f6573"}),    # Flinti
 143: ("wide", ["mane"], "happy", "open", {}),                            # Lavajo
 144: ("tall", ["torch", "arms"], "bead", "o", {}),                       # Searli
 145: ("round", ["mane", "embers"], "sparkle", "cat", {"acc": "#8e5bd6"}),  # Pyvra
 # Mosslight Grove — garden
 146: ("round", ["petalcollar"], "happy", "smile", {}),                   # Petalia
 147: ("egg", ["sprout", "feet"], "bead", "open", {"mid": "#b9db8a"}),    # Spriggo
 148: ("round", ["sunflower"], "happy", "open", {"acc": "#f5c542"}),      # Floressa
 149: ("onion", ["berryleaf"], "bead", "smile", {"mid": "#a8325a"}),      # Berru
 150: ("round", ["bee", "stripes", "antennae"], "wink", "open", {"mid": "#f2c94c"}),  # Necti
 151: ("mochi", ["mushcap"], "bead", "cat", {"acc": "#8fbf5a"}),          # Mossini
 152: ("ghost", ["bellhat"], "happy", "o", {"acc": "#7f8be0"}),           # Veyla
 153: ("egg", ["acorn"], "bead", "smile", {"mid": "#f0a63a"}),            # Tindle
 154: ("wide", ["clover"], "happy", "smile", {"acc": "#6fae4c"}),         # Clovey
 155: ("round", ["curls", "feet"], "bead", "fang", {"acc": "#c94c4c"}),   # Rhuvi
 # Aurora Vale — ice & aurora
 156: ("tall", ["crystalears"], "sparkle", "smile", {"acc": "#45d3c8"}),  # Boreli
 157: ("round", ["prism"], "happy", "cat", {"acc": "#b79cf0"}),           # Prismel
 158: ("ghost", ["icicles"], "bead", "o", {"acc": "#8ccaf5"}),            # Shivera
 159: ("round", ["aurora"], "wink", "smile", {}),                          # Lumaine
 160: ("mochi", ["gemforehead", "bubbles"], "sparkle", "smile", {"mid": "#e4e6ef", "acc": "#c7a6ff"}),  # Opaliq
 161: ("round", ["icebuns", "feet"], "bead", "open", {"acc": "#8fc7ff"}),  # Glacchi
 162: ("flat", ["sealtail"], "happy", "cat", {"mid": "#2f7fa8"}),          # Selka
 163: ("egg", ["antlers"], "bead", "smile", {"acc": "#a9d6f5"}),           # Kivvi
 164: ("round", ["earmuffs", "scarf"], "happy", "open", {"mid": "#f4f8ff", "acc": "#45b6e8", "acc2": "#45b6e8"}),  # Polari
 165: ("round", ["veil"], "bead", "o", {"acc": "#a898f0"}),               # Veilo
 # Clocklings — clockwork
 166: ("round", ["goggles", "floppy"], "bead", "open", {}),               # Tocko
 167: ("egg", ["watch", "swirltop"], "wink", "smile", {"acc": "#57c2b8"}),  # Mintra
 168: ("round", ["gearears", "arms"], "bead", "fang", {"acc": "#d98a3a"}),  # Cogsy
 169: ("pear", ["pendulum"], "happy", "smile", {}),                        # Pendli
 170: ("squircle", ["spring", "windkey"], "sparkle", "open", {"acc": "#ff8b5c"}),  # Whirlo: coil spring + key
 171: ("round", ["clockhands", "monocle"], "bead", "cat", {"acc2": "#3d3550"}),   # Ticklet
 172: ("cube", ["bolthorns", "rivets"], "bead", "smile", {"acc": "#4a6a9a"}),   # Riveti
 173: ("round", ["dial", "longears"], "wink", "smile", {}),                # Dialli
 174: ("mochi", ["spool"], "happy", "o", {"acc": "#8a5bd0"}),              # Spoolen
 175: ("round", ["octoears", "gearspots"], "happy", "smile", {"mid": "#33467a"}),  # Tempoo
 # Sugarvale — sweets
 176: ("drop", ["drip"], "bead", "open", {"mid": "#f2b25c", "acc": "#c9752e"}),  # Caramie
 177: ("mochi", ["sakura", "belly"], "happy", "cat", {"mid": "#ffc9d6", "acc2": "#ff8fb0"}),  # Mochiri
 178: ("round", ["lemon"], "wink", "open", {"mid": "#f3f0e6"}),           # Zestiq
 179: ("round", ["cinnabuns", "belly"], "happy", "open", {"mid": "#f3d6ad"}),  # Churli: cinnamon buns
 180: ("cloud", ["longears"], "bead", "smile", {"mid": "#fbe7c6", "acc": "#e6b27a"}),  # Puffumi
 181: ("round", ["lollipops"], "wink", "smile", {"acc": "#ff5c8a"}),      # Sorbelle
 182: ("cube", ["cookiedots", "arms"], "bead", "open", {"mid": "#e8b06a"}),  # Biskin: biscuit
 183: ("ghost", ["jellyears", "gummydrop"], "sparkle", "o", {"mid": "#c79cf2", "acc": "#a06ae6"}),  # Jellune: jelly bunny
 184: ("egg", ["wrapper", "candystripe"], "bead", "smile", {"mid": "#7fd6c8", "acc": "#4fbfae"}),  # Bonbiri
 185: ("mochi", ["frosting"], "happy", "cat", {"mid": "#fff3e6", "acc": "#9fe3c4"}),  # Crembo
 # Inkbound Atelier — ink & paper
 186: ("drop", ["inkdrip"], "sparkle", "smile", {"mid": "#2f3f86"}),      # Inkaro
 187: ("round", ["paperears"], "happy", "cat", {"mid": "#f4ead8", "acc": "#e9dcc2"}),  # Papillo
 188: ("egg", ["quill", "feet"], "bead", "o", {"mid": "#f6efe0", "acc": "#3d5bb3"}),  # Quilli
 189: ("round", ["polka", "beret"], "wink", "smile", {"mid": "#2a2f4a", "acc": "#e8ecf8", "acc2": "#c84a5a"}),  # Dottori
 190: ("star", ["crane"], "bead", "smile", {"mid": "#f7e9d2", "acc": "#f08aa0", "acc2": "#e05a78"}),  # Origra: origami crane
 191: ("round", ["roundears", "brushtail"], "bead", "open", {"mid": "#8d8a95", "acc2": "#3d6ac8"}),  # Smudgi
 192: ("onion", ["bow"], "happy", "smile", {"mid": "#efe1c8", "acc": "#4a6fc0"}),  # Lintera
 193: ("cube", ["stamp", "feet"], "bead", "fang", {"acc": "#c4453a"}),    # Stampo
 194: ("round", ["scrollears"], "wink", "open", {"mid": "#f3e3c3", "acc": "#e2c79a"}),  # Scrolli
 195: ("cloud", ["chalkfluff"], "bead", "smile", {"mid": "#9fb4d8"}),     # Chalko
 # Neon Arcade — pixels & electricity
 196: ("cube", ["pixelcrown"], "sparkle", "open", {"mid": "#f2f6ff", "acc": "#2f6bff"}),  # Pixori
 197: ("round", ["boltears"], "wink", "fang", {"acc": "#9be33a"}),        # Voltae
 198: ("squircle", ["glitch"], "bead", "o", {"mid": "#9a6be0", "acc": "#ff4fd8", "acc2": "#3de0ff"}),  # Glitcho
 199: ("round", ["cyberears", "visor"], "bead", "smile", {"mid": "#e6f2ff", "acc": "#36c8ff"}),  # Cybri
 200: ("round", ["headphones"], "happy", "open", {"acc": "#ff6fa8", "acc2": "#7a4ad6"}),  # Bippi
 201: ("mochi", ["starpaws", "controller"], "happy", "open", {"mid": "#ffe39a", "acc": "#ffc23d"}),  # Tappi
 202: ("round", ["rings", "halo"], "sparkle", "o", {"mid": "#dfe8ee", "acc": "#2fd0e8"}),  # Loopin: donut rings + halo
 203: ("egg", ["diamondears"], "bead", "cat", {"acc": "#ff3fae"}),        # Synki
 204: ("wide", ["datafins", "cube", "polka"], "wink", "smile", {"mid": "#2c58c8", "acc": "#8fd0ff", "acc2": "#6ff0ff"}),  # Datto
 205: ("round", ["sparks"], "happy", "open", {"acc": "#ff9a3c", "acc2": "#ffd84a"}),  # Zingra
 # Lantern Parade — festival night
 206: ("round", ["lanterns"], "happy", "open", {}),                       # Lanterni
 207: ("egg", ["hood", "mask"], "bead", "smile", {"mid": "#f3dccf", "acc": "#7a2a45"}),  # Masqora
 208: ("round", ["bunnyears", "floatlantern"], "wink", "cat", {"acc": "#ff9fb8"}),  # Confira
 209: ("ghost", ["nightcape"], "sparkle", "o", {"mid": "#cfd8ef", "acc": "#273566"}),  # Velloo
 210: ("round", ["ribbonloops"], "happy", "smile", {"acc": "#ff8aa0"}),   # Ribbika
 211: ("pear", ["partyhat", "floppy"], "wink", "open", {"acc": "#ff9a4a", "acc2": "#5ac8e8"}),  # Marvello
 212: ("round", ["glowbulbs", "cape"], "sparkle", "smile", {"mid": "#2a3157", "acc2": "#3a4580"}),  # Glimora
 213: ("mochi", ["plumehat"], "happy", "open", {"mid": "#a8e0c4", "acc": "#3f9c74", "acc2": "#ffd25a"}),  # Paradi
 214: ("tall", ["moonhorns", "starsprinkle"], "bead", "smile", {"mid": "#262c52"}),  # Noctali
 215: ("round", ["pinwheel", "feet"], "happy", "open", {"acc": "#ff7fa8", "acc2": "#ffd25a"}),  # Jubilo
}
