"""Datos "mágicos" de la demo: hechizos aleatorios y grimorios de ejemplo.

Todo el contenido es original (no proviene de ninguna serie).
"""

import random

ELEMENTS = ["fuego", "viento", "agua", "tierra", "rayo", "luz"]

SPELL_FORMS = [
    "Lanza", "Escudo", "Torbellino", "Cadena", "Lluvia",
    "Espiral", "Corona", "Muralla", "Danza", "Sello",
]

ELEMENT_NOUNS = {
    "fuego": ["Brasas Eternas", "Ceniza Carmesí", "Llama Solar"],
    "viento": ["Brisa Cortante", "Tormenta Esmeralda", "Céfiro Errante"],
    "agua": ["Marea Profunda", "Rocío Plateado", "Cascada Silente"],
    "tierra": ["Roca Ancestral", "Raíz de Trébol", "Montaña Dormida"],
    "rayo": ["Trueno Dorado", "Chispa Veloz", "Relámpago Gemelo"],
    "luz": ["Aurora Naciente", "Estrella Fugaz", "Prisma Sagrado"],
}

GRIMOIRES = [
    {
        "id": "trebol-ambar",
        "name": "Grimorio del Trébol Ámbar",
        "leaves": 3,
        "element": "tierra",
        "pages": 128,
        "description": "Sus páginas se reparten la carga como raíces que sostienen un árbol.",
    },
    {
        "id": "pluma-tormenta",
        "name": "Grimorio de la Pluma Tormenta",
        "leaves": 4,
        "element": "viento",
        "pages": 256,
        "description": "Cuando una página se rasga, otra nueva aparece en su lugar.",
    },
    {
        "id": "llama-gemela",
        "name": "Grimorio de la Llama Gemela",
        "leaves": 2,
        "element": "fuego",
        "pages": 64,
        "description": "Existe en dos torres a la vez: si una cae, la otra sigue ardiendo.",
    },
    {
        "id": "espejo-lunar",
        "name": "Grimorio del Espejo Lunar",
        "leaves": 5,
        "element": "luz",
        "pages": 512,
        "description": "Refleja hechizos ya conjurados para no tener que lanzarlos otra vez.",
    },
]


def generate_spell(rng: random.Random | None = None) -> dict:
    rng = rng or random.Random()
    element = rng.choice(ELEMENTS)
    name = f"{rng.choice(SPELL_FORMS)} de {rng.choice(ELEMENT_NOUNS[element])}"
    return {"name": name, "element": element, "power": rng.randint(1, 100)}
