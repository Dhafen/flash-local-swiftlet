"""English text for the Wolkara HUD bundled with Slashplayed."""

import re


LABELS = {
    "Personnage": "Character", "Sacs": "Bags", "Sorts": "Spells",
    "Quêtes": "Quests", "Carte": "Map", "Guilde": "Guild",
    "Menu du jeu": "Game Menu", "Réglages du jeu": "Game Settings",
    "Interface mobile": "Mobile UI", "Recharger": "Reload",
    "Déconnexion": "Log Out", "Quitter": "Exit", "Cible": "Target",
    "Quêtes (%d)  %s": "Quests (%d)  %s", "À rendre": "Ready to turn in",
    "Discussion": "Chat", "Privé": "Whispers", "Système": "System",
    "Tout": "All", "Dire": "Say", "Crier": "Yell", "Groupe": "Party",
    "Chef": "Leader", "Chef de raid": "Raid Leader", "Alerte": "Warning",
    "Officier": "Officer", "De": "From", "À": "To", "À ": "To ",
    "Dit": "Says", "Crie": "Yells", "Murmure": "Whispers",
    "Général": "General", "Répondre": "Reply", "Canal": "Channel",
    "Masquer": "Hide", "À :": "To:",
    " nouveau privé": " new whisper", " nouveaux privés": " new whispers",
    "Pour écrire, touche le clavier juste sous le chat ; Entrée envoie.":
        "Tap the keyboard below chat to type. Press Enter to send.",
    "Message privé à ": "Whisper to ",
    " : touche le clavier juste sous le chat.": ": tap the keyboard below chat.",
    "Roue": "Wheel", "Roue ": "Wheel ", "Oui": "On", "Non": "Off",
    "Cases": "Slots", "Taille": "Size", "Au bouton": "Button",
    "Au centre": "Center", "Sorts à droite": "Right Spells",
    "Sorts à gauche": "Left Spells", "Nombre": "Count",
    "Écart des sorts": "Spell Spacing", "Droite": "Right", "Gauche": "Left",
    "Raccourcis": "Shortcuts", "Vie": "Health", "Jeu": "Game",
    "Texte": "Text", "Affichées": "Shown", "Mini-carte": "Minimap",
    "D'origine": "Default", "Barres de sorts": "Action Bars",
    "Masquées": "Hidden", "Cadres joueur et cible": "Player and Target Frames",
    "Affichés": "Shown", "Masqués": "Hidden", "Personnaliser": "Customize",
    "Positions par défaut": "Reset Positions", "Fermer": "Close", "Terminé": "Done",
    "Objets": "Items", "Aucun sort actif dans le grimoire.": "No active spells in your spellbook.",
    "Aucun objet utilisable dans tes sacs.": "No usable items in your bags.",
    "Aucune macro. Crée-en avec /macro.": "No macros. Create one with /macro.",
    "Remplacer : ": "Replace: ", "Choisir pour cette case": "Choose an action for this slot",
    "Cibler un ennemi": "Target Enemy", "Cibler un allié": "Target Friendly",
    "Attaque auto": "Auto Attack", "Assister": "Assist", "Effacer la cible": "Clear Target",
    "Suivre": "Follow", "S'asseoir": "Sit",
    "Sélecteur": "Picker", "Réglages": "Settings", "Fenêtres du jeu": "Game Windows",
    "on remplit les cases hors combat.": "Assign slots outside combat.",
    "on personnalise hors combat.": "Customize the layout outside combat.",
    "on règle l'interface hors combat.": "Change the layout outside combat.",
    "pas en combat.": "Available outside combat.",
    "pas encore prête": "not ready yet",
    "réglages enregistrés.": "Settings saved.",
    "enregistrement de tes réglages : l'interface se recharge.": "Saving settings and reloading the UI.",
    "réglages et positions par défaut remis (les sorts des roues restent).":
        "Defaults and positions restored. Wheel actions were kept.",
    "mode Personnaliser : fais glisser ce que tu veux déplacer, touche une case pour choisir son sort, puis Terminé.":
        "In Customize mode, drag to move controls, tap a slot to assign an action, then tap Done.",
    "touche une case vide d'une roue pour y mettre un sort, glisse depuis un sort pour la faire tourner, et l'engrenage des raccourcis règle tout.":
        "Tap an empty wheel slot to assign an action. Swipe from a slot to spin the wheel. Use the menu for settings.",
}

# Match whole Lua string literals. This leaves keys, commands and asset paths
# alone unless a literal is explicitly listed above.
STRING = re.compile(r'"((?:[^"\\]|\\.)*)"')


def translate(source):
    return STRING.sub(lambda m: '"' + LABELS[m[1]] + '"' if m[1] in LABELS else m[0], source)
