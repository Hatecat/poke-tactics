"""Esqueletos a mano para los rips que vienen sin huesos (setup_animations.template_rig los monta).

Cada hueso: nombre -> (cabeza, cola, padre). Las posiciones van en alturas del modelo, medidas en su
caja: u a lo ancho desde el centro (+u es la izquierda del Pokémon), v de delante (-) a atrás (+)
desde el centro y h desde el suelo. Los huesos LBrazo (L y mayúscula) se copian en espejo como R.
"_props" lleva piezas sueltas a su sitio antes de pesar (box: caja de las piezas; las gira "pitch"
grados hacia delante sobre "pivot", que acaba en "to", y las ata enteras a "bone").
Las extremidades empiezan donde salen de la silueta: los pesos van por distancia al hueso más cercano
y un muslo metido en la barriga se la llevaría. Los brazos de los bípedos llevan siempre Arm, ForeArm
y Hand. Los nombres siguen la convención de Charmander, así que después se animan con
animate_pokemon.py (bípedos y cuadrúpedos) o animate_generic.py (el resto).
"""

import re

RIGS = {
    # ---------- bípedos (animate_pokemon.py) ----------
    "chansey": {
        "Hips": ((0, 0.05, 0.3), (0, 0.05, 0.75), None),
        # Tronco hacia el huevo: la barriga y el huevo no van con las patas ni con los brazos.
        "Belly": ((0, 0.05, 0.3), (0, -0.48, 0.25), "Hips"),
        "LThigh": ((0.24, -0.02, 0.09), (0.24, -0.05, 0.04), "Hips"),
        "LFoot": ((0.24, -0.05, 0.04), (0.24, -0.2, 0.02), "LThigh"),
        "LToe": ((0.24, -0.2, 0.02), (0.24, -0.26, 0.02), "LFoot"),
        # Muñones que apuntan hacia delante a los lados del huevo (lo rosa de arriba son las orejas).
        "LArm": ((0.26, -0.32, 0.6), (0.27, -0.44, 0.6), "Hips"),
        "LForeArm": ((0.27, -0.44, 0.6), (0.28, -0.53, 0.6), "LArm"),
        "LHand": ((0.28, -0.53, 0.6), (0.28, -0.62, 0.6), "LForeArm"),
        "Tail1": ((0, 0.3, 0.1), (0, 0.5, 0.07), "Hips"),
        "Tail2": ((0, 0.5, 0.07), (0, 0.72, 0.05), "Tail1"),
    },
    "clefairy": {  # brazos hacia delante, cola rizada detrás
        "Hips": ((0, -0.15, 0.2), (0, -0.15, 0.85), None),
        "LThigh": ((0.2, -0.18, 0.16), (0.2, -0.2, 0.06), "Hips"),
        "LFoot": ((0.2, -0.2, 0.06), (0.2, -0.3, 0.02), "LThigh"),
        "LToe": ((0.2, -0.3, 0.02), (0.2, -0.36, 0.01), "LFoot"),
        "LArm": ((0.33, -0.25, 0.55), (0.4, -0.35, 0.55), "Hips"),
        "LForeArm": ((0.4, -0.35, 0.55), (0.43, -0.46, 0.55), "LArm"),
        "LHand": ((0.43, -0.46, 0.55), (0.45, -0.58, 0.55), "LForeArm"),
        "Tail1": ((0, 0.08, 0.35), (0, 0.28, 0.4), "Hips"),
        "Tail2": ((0, 0.28, 0.4), (0, 0.5, 0.38), "Tail1"),
    },
    "drowzee": {
        "Hips": ((0, 0, 0.15), (0, 0, 0.45), None),
        "Spine": ((0, 0, 0.45), (0, 0, 0.65), "Hips"),
        "Head": ((0, 0, 0.68), (0, -0.05, 0.95), "Spine"),
        "LThigh": ((0.22, 0.05, 0.16), (0.25, 0.03, 0.06), "Hips"),
        "LFoot": ((0.25, 0.03, 0.06), (0.25, -0.1, 0.02), "LThigh"),
        "LToe": ((0.25, -0.1, 0.02), (0.25, -0.16, 0.01), "LFoot"),
        "LArm": ((0.3, 0.05, 0.6), (0.42, 0.05, 0.6), "Spine"),
        "LForeArm": ((0.42, 0.05, 0.6), (0.55, 0.05, 0.6), "LArm"),
        "LHand": ((0.55, 0.05, 0.6), (0.66, 0.05, 0.6), "LForeArm"),
    },
    "hypno": {
        "Hips": ((0, 0.05, 0.42), (0, 0.05, 0.58), None),
        "Spine": ((0, 0.05, 0.58), (0, 0.03, 0.72), "Hips"),
        "Head": ((0, 0.0, 0.74), (0, -0.02, 0.98), "Spine"),
        "LThigh": ((0.1, 0.05, 0.42), (0.1, 0.05, 0.28), "Hips"),
        "LFoot": ((0.1, 0.05, 0.28), (0.1, -0.05, 0.25), "LThigh"),
        "LToe": ((0.1, -0.05, 0.25), (0.1, -0.1, 0.25), "LFoot"),
        "LArm": ((0.2, 0.02, 0.7), (0.32, 0.02, 0.7), "Spine"),
        "LForeArm": ((0.32, 0.02, 0.7), (0.45, 0.02, 0.7), "LArm"),
        "LHand": ((0.45, 0.02, 0.7), (0.57, 0.02, 0.7), "LForeArm"),
        # El péndulo cuelga en el rip entre las piernas, hasta el suelo: a la mano derecha, adelantado
        # (si colgara recto llegaría más abajo que los pies y el juego lo pondría flotando).
        "_props": [{"box": ((-0.04, -0.1, -0.01), (0.04, 0.15, 0.62)), "pivot": (0, 0.05, 0.6),
                    "pitch": 60, "to": (-0.57, 0.02, 0.69), "bone": "RHand"}],
    },
    "jynx": {  # sin piernas a la vista: las de la plantilla mueven el vestido
        "Hips": ((0, 0, 0.2), (0, 0, 0.4), None),
        "Spine": ((0, 0, 0.4), (0, 0, 0.55), "Hips"),
        "Head": ((0, 0, 0.6), (0, 0, 0.95), "Spine"),
        "LThigh": ((0.15, 0, 0.25), (0.15, 0, 0.08), "Hips"),
        "LFoot": ((0.15, 0, 0.08), (0.15, -0.12, 0.02), "LThigh"),
        "LToe": ((0.15, -0.12, 0.02), (0.15, -0.2, 0.01), "LFoot"),
        "LArm": ((0.34, 0, 0.55), (0.5, 0, 0.55), "Spine"),
        "LForeArm": ((0.5, 0, 0.55), (0.67, 0, 0.55), "LArm"),
        "LHand": ((0.67, 0, 0.55), (0.85, 0, 0.55), "LForeArm"),
    },
    "electabuzz": {
        "Hips": ((0, -0.15, 0.2), (0, -0.15, 0.38), None),
        "Spine": ((0, -0.15, 0.38), (0, -0.15, 0.58), "Hips"),
        "Head": ((0, -0.15, 0.6), (0, -0.17, 0.85), "Spine"),
        "LThigh": ((0.08, -0.12, 0.2), (0.08, -0.12, 0.05), "Hips"),
        "LFoot": ((0.08, -0.12, 0.05), (0.08, -0.22, 0.02), "LThigh"),
        "LToe": ((0.08, -0.22, 0.02), (0.08, -0.28, 0.01), "LFoot"),
        "LArm": ((0.18, -0.18, 0.6), (0.4, -0.18, 0.6), "Spine"),
        "LForeArm": ((0.4, -0.18, 0.6), (0.65, -0.18, 0.6), "LArm"),
        "LHand": ((0.65, -0.18, 0.6), (0.85, -0.18, 0.6), "LForeArm"),
        "Tail1": ((0, 0.0, 0.25), (0, 0.2, 0.25), "Hips"),
        "Tail2": ((0, 0.2, 0.25), (0, 0.4, 0.25), "Tail1"),
        "Tail3": ((0, 0.4, 0.25), (0, 0.56, 0.25), "Tail2"),
    },
    "magmar": {  # el rip apoya la llama de la cola en el suelo: los pies quedan algo altos
        "Hips": ((0, -0.15, 0.35), (0, -0.15, 0.52), None),
        "Spine": ((0, -0.15, 0.52), (0, -0.17, 0.68), "Hips"),
        "Head": ((0, -0.2, 0.72), (0, -0.22, 0.95), "Spine"),
        "LThigh": ((0.2, -0.15, 0.42), (0.17, -0.17, 0.24), "Hips"),
        "LFoot": ((0.17, -0.17, 0.24), (0.17, -0.28, 0.21), "LThigh"),
        "LToe": ((0.17, -0.28, 0.21), (0.17, -0.33, 0.2), "LFoot"),
        "LArm": ((0.18, -0.15, 0.67), (0.28, -0.15, 0.67), "Spine"),
        "LForeArm": ((0.28, -0.15, 0.67), (0.4, -0.15, 0.67), "LArm"),
        "LHand": ((0.4, -0.15, 0.67), (0.5, -0.15, 0.67), "LForeArm"),
        "Tail1": ((0, 0.0, 0.35), (0, 0.12, 0.24), "Hips"),
        "Tail2": ((0, 0.12, 0.24), (0, 0.22, 0.12), "Tail1"),
        "Tail3": ((0, 0.22, 0.12), (0, 0.32, 0.02), "Tail2"),
    },
    "hitmonlee": {  # cuerpo y cabeza en una pieza
        "Hips": ((0, 0, 0.42), (0, 0, 0.95), None),
        "LThigh": ((0.1, 0, 0.45), (0.1, 0, 0.25), "Hips"),
        "LLeg": ((0.1, 0, 0.25), (0.1, 0, 0.05), "LThigh"),
        "LFoot": ((0.1, 0, 0.05), (0.1, -0.1, 0.02), "LLeg"),
        "LToe": ((0.1, -0.1, 0.02), (0.1, -0.2, 0.01), "LFoot"),
        "LArm": ((0.2, 0, 0.81), (0.4, 0, 0.81), "Hips"),
        "LForeArm": ((0.4, 0, 0.81), (0.6, 0, 0.81), "LArm"),
        "LHand": ((0.6, 0, 0.81), (0.8, 0, 0.81), "LForeArm"),
    },
    "kabutops": {  # las guadañas cuelgan de la mano
        "Hips": ((0, 0.03, 0.42), (0, 0.02, 0.6), None),
        "Spine": ((0, 0.02, 0.6), (0, 0, 0.76), "Hips"),
        "Head": ((0, 0, 0.78), (0, -0.25, 0.88), "Spine"),
        "LThigh": ((0.15, 0.03, 0.42), (0.2, -0.05, 0.22), "Hips"),
        "LLeg": ((0.2, -0.05, 0.22), (0.22, 0.03, 0.04), "LThigh"),
        "LFoot": ((0.22, 0.03, 0.04), (0.22, -0.1, 0.02), "LLeg"),
        "LToe": ((0.22, -0.1, 0.02), (0.22, -0.16, 0.01), "LFoot"),
        "LArm": ((0.2, 0, 0.72), (0.35, 0, 0.72), "Spine"),
        "LForeArm": ((0.35, 0, 0.72), (0.55, 0, 0.72), "LArm"),
        "LHand": ((0.55, 0, 0.72), (0.6, 0, 0.4), "LForeArm"),
        "Tail1": ((0, 0.12, 0.42), (0, 0.2, 0.22), "Hips"),
        "Tail2": ((0, 0.2, 0.22), (0, 0.28, 0.05), "Tail1"),
    },
    "lickitung": {
        "Hips": ((0, 0.02, 0.2), (0, 0.02, 0.45), None),
        "Spine": ((0, 0.02, 0.45), (0, 0, 0.68), "Hips"),
        "Head": ((0, -0.1, 0.72), (0, -0.12, 0.98), "Spine"),
        "Tongue1": ((0, -0.25, 0.76), (0, -0.6, 0.76), "Head"),
        "Tongue2": ((0, -0.6, 0.76), (0, -1.0, 0.76), "Tongue1"),
        "LThigh": ((0.2, 0.02, 0.25), (0.22, 0, 0.08), "Hips"),
        "LFoot": ((0.22, 0, 0.08), (0.22, -0.1, 0.02), "LThigh"),
        "LToe": ((0.22, -0.1, 0.02), (0.22, -0.16, 0.01), "LFoot"),
        "LArm": ((0.24, 0, 0.62), (0.36, 0, 0.62), "Spine"),
        "LForeArm": ((0.36, 0, 0.62), (0.46, 0, 0.62), "LArm"),
        "LHand": ((0.46, 0, 0.62), (0.56, 0, 0.62), "LForeArm"),
        "Tail1": ((0, 0.25, 0.2), (0, 0.5, 0.25), "Hips"),
        "Tail2": ((0, 0.5, 0.25), (0, 0.75, 0.45), "Tail1"),
        "Tail3": ((0, 0.75, 0.45), (0, 0.98, 0.68), "Tail2"),
    },
    "snorlax": {
        "Hips": ((0, 0, 0.2), (0, 0, 0.5), None),
        "Spine": ((0, 0, 0.5), (0, 0, 0.72), "Hips"),
        "Head": ((0, -0.02, 0.75), (0, -0.02, 0.98), "Spine"),
        "LThigh": ((0.25, 0, 0.15), (0.27, -0.02, 0.06), "Hips"),
        "LFoot": ((0.27, -0.02, 0.06), (0.27, -0.15, 0.03), "LThigh"),
        "LToe": ((0.27, -0.15, 0.03), (0.27, -0.2, 0.02), "LFoot"),
        "LArm": ((0.36, 0, 0.61), (0.45, 0, 0.61), "Spine"),
        "LForeArm": ((0.45, 0, 0.61), (0.54, 0, 0.61), "LArm"),
        "LHand": ((0.54, 0, 0.61), (0.62, 0, 0.61), "LForeArm"),
    },
    "poliwag": {  # bola con patas y cola, sin brazos
        "Hips": ((0, -0.5, 0.3), (0, -0.5, 0.8), None),
        "Belly": ((0, -0.5, 0.3), (0, -0.5, 0.1), "Hips"),
        "LThigh": ((0.22, -0.5, 0.14), (0.25, -0.52, 0.06), "Hips"),
        "LFoot": ((0.25, -0.52, 0.06), (0.25, -0.68, 0.03), "LThigh"),
        "LToe": ((0.25, -0.68, 0.03), (0.25, -0.76, 0.02), "LFoot"),
        "Tail1": ((0, -0.1, 0.22), (0, 0.25, 0.22), "Hips"),
        "Tail2": ((0, 0.25, 0.22), (0, 0.6, 0.22), "Tail1"),
        "Tail3": ((0, 0.6, 0.22), (0, 0.95, 0.22), "Tail2"),
    },
    "tangela": {  # bola de lianas con pies
        "Hips": ((0, 0, 0.25), (0, 0, 0.8), None),
        "LThigh": ((0.2, -0.05, 0.15), (0.2, -0.08, 0.06), "Hips"),
        "LFoot": ((0.2, -0.08, 0.06), (0.2, -0.22, 0.03), "LThigh"),
        "LToe": ((0.2, -0.22, 0.03), (0.2, -0.28, 0.02), "LFoot"),
    },
    # ---------- cuadrúpedos (animate_pokemon.py) ----------
    "ponyta": {
        "Hips": ((0, 0.12, 0.5), (0, -0.05, 0.52), None),
        "Spine": ((0, -0.05, 0.52), (0, -0.25, 0.55), "Hips"),
        "Neck": ((0, -0.28, 0.58), (0, -0.35, 0.72), "Spine"),
        "Head": ((0, -0.35, 0.72), (0, -0.52, 0.72), "Neck"),
        "LArm": ((0.09, -0.28, 0.45), (0.09, -0.3, 0.25), "Spine"),
        "LForeArm": ((0.09, -0.3, 0.25), (0.09, -0.32, 0.06), "LArm"),
        "LHand": ((0.09, -0.32, 0.06), (0.09, -0.36, 0.0), "LForeArm"),
        "LThigh": ((0.09, 0.12, 0.45), (0.09, 0.08, 0.25), "Hips"),
        "LLeg": ((0.09, 0.08, 0.25), (0.09, 0.15, 0.06), "LThigh"),
        "LFoot": ((0.09, 0.15, 0.06), (0.09, 0.12, 0.0), "LLeg"),
        "Tail1": ((0, 0.15, 0.55), (0, 0.3, 0.65), "Hips"),
        "Tail2": ((0, 0.3, 0.65), (0, 0.45, 0.8), "Tail1"),
    },
    "rhyhorn": {
        "Hips": ((0, 0.42, 0.38), (0, 0.15, 0.45), None),
        "Spine": ((0, 0.15, 0.45), (0, -0.15, 0.42), "Hips"),
        "Neck": ((0, -0.18, 0.4), (0, -0.3, 0.32), "Spine"),
        "Head": ((0, -0.3, 0.32), (0, -0.6, 0.18), "Neck"),
        "LArm": ((0.25, -0.17, 0.3), (0.28, -0.17, 0.15), "Spine"),
        "LForeArm": ((0.28, -0.17, 0.15), (0.3, -0.17, 0.04), "LArm"),
        "LHand": ((0.3, -0.17, 0.04), (0.3, -0.25, 0.0), "LForeArm"),
        "LThigh": ((0.25, 0.45, 0.32), (0.28, 0.45, 0.16), "Hips"),
        "LLeg": ((0.28, 0.45, 0.16), (0.3, 0.47, 0.04), "LThigh"),
        "LFoot": ((0.3, 0.47, 0.04), (0.3, 0.4, 0.0), "LLeg"),
    },
    "tauros": {
        "Hips": ((0, 0.12, 0.55), (0, -0.1, 0.6), None),
        "Spine": ((0, -0.1, 0.6), (0, -0.35, 0.62), "Hips"),
        "Neck": ((0, -0.4, 0.6), (0, -0.5, 0.55), "Spine"),
        "Head": ((0, -0.5, 0.55), (0, -0.62, 0.4), "Neck"),
        "LArm": ((0.12, -0.33, 0.4), (0.12, -0.33, 0.2), "Spine"),
        "LForeArm": ((0.12, -0.33, 0.2), (0.12, -0.34, 0.04), "LArm"),
        "LHand": ((0.12, -0.34, 0.04), (0.12, -0.38, 0.0), "LForeArm"),
        "LThigh": ((0.12, 0.12, 0.45), (0.12, 0.08, 0.22), "Hips"),
        "LLeg": ((0.12, 0.08, 0.22), (0.12, 0.15, 0.04), "LThigh"),
        "LFoot": ((0.12, 0.15, 0.04), (0.12, 0.11, 0.0), "LLeg"),
        "Tail1": ((0, 0.2, 0.55), (0, 0.4, 0.58), "Hips"),
        "Tail2": ((0, 0.4, 0.58), (0, 0.6, 0.62), "Tail1"),
    },
    # ---------- sin patas (animate_generic.py): cuerpo y apéndices que ondulan ----------
    "electrode": {
        "Hips": ((0, 0, 0.5), (0, 0, 0.8), None),
    },
    "golbat": {
        "Hips": ((0, 0, 0.2), (0, 0, 0.5), None),
        "LWing1": ((0.18, 0, 0.5), (0.55, 0, 0.7), "Hips"),
        "LWing2": ((0.55, 0, 0.7), (1.15, 0, 0.98), "LWing1"),
        "LFoot": ((0.08, 0, 0.1), (0.12, -0.03, 0.0), "Hips"),
    },
    "goldeen": {
        "Hips": ((0, -0.75, 0.5), (0, -0.35, 0.5), None),
        "Tail1": ((0, -0.25, 0.45), (0, 0.25, 0.5), "Hips"),
        "Tail2": ((0, 0.25, 0.5), (0, 0.75, 0.6), "Tail1"),
        "Tail3": ((0, 0.75, 0.6), (0, 1.25, 0.8), "Tail2"),
        "LFin1": ((0.35, -0.6, 0.5), (0.65, -0.6, 0.45), "Hips"),
        "LFin2": ((0.65, -0.6, 0.45), (1.0, -0.6, 0.3), "LFin1"),
    },
    "seaking": {
        "Hips": ((0, -0.4, 0.5), (0, -0.05, 0.5), None),
        "Tail1": ((0, 0.1, 0.5), (0, 0.35, 0.55), "Hips"),
        "Tail2": ((0, 0.35, 0.55), (0, 0.65, 0.75), "Tail1"),
        "LFin": ((0.25, -0.2, 0.4), (0.42, -0.1, 0.3), "Hips"),
        "LFinB": ((0.12, -0.1, 0.2), (0.15, -0.05, 0.03), "Hips"),
    },
    "horsea": {
        "Hips": ((0, 0.05, 0.35), (0, 0.0, 0.65), None),
        "Head": ((0, 0.0, 0.67), (0, -0.05, 0.95), "Hips"),
        "Tail1": ((0, 0.05, 0.25), (0, 0.0, 0.1), "Hips"),
        "Tail2": ((0, 0.0, 0.1), (0, -0.15, 0.05), "Tail1"),
        "Tail3": ((0, -0.15, 0.05), (0, -0.25, 0.15), "Tail2"),
        "Fin": ((0, 0.18, 0.6), (0, 0.42, 0.67), "Hips"),
    },
    "seadra": {
        "Hips": ((0, 0.05, 0.35), (0, 0.02, 0.6), None),
        "Head": ((0, 0, 0.62), (0, -0.1, 0.9), "Hips"),
        "Tail1": ((0, 0.08, 0.3), (0, 0.06, 0.12), "Hips"),
        "Tail2": ((0, 0.06, 0.12), (0, -0.05, 0.04), "Tail1"),
        "Tail3": ((0, -0.05, 0.04), (0, -0.18, 0.12), "Tail2"),
        "LFin1": ((0.15, 0.1, 0.6), (0.3, 0.25, 0.65), "Hips"),
        "LFin2": ((0.3, 0.25, 0.65), (0.45, 0.42, 0.72), "LFin1"),
    },
    "lapras": {  # el cuello ondula como un apéndice
        "Hips": ((0, 0.15, 0.2), (0, 0.4, 0.25), None),
        "NeckA1": ((0, -0.3, 0.2), (0, -0.38, 0.45), "Hips"),
        "NeckA2": ((0, -0.38, 0.45), (0, -0.42, 0.7), "NeckA1"),
        "NeckA3": ((0, -0.42, 0.7), (0, -0.5, 0.92), "NeckA2"),
        "LFinF1": ((0.25, -0.2, 0.1), (0.45, -0.22, 0.05), "Hips"),
        "LFinF2": ((0.45, -0.22, 0.05), (0.65, -0.25, 0.02), "LFinF1"),
        "LFinB1": ((0.22, 0.42, 0.1), (0.38, 0.48, 0.05), "Hips"),
        "LFinB2": ((0.38, 0.48, 0.05), (0.55, 0.5, 0.03), "LFinB1"),
    },
    "kabuto": {
        "Hips": ((0, 0, 0.4), (0, -0.3, 0.45), None),
        "LLegF": ((0.2, -0.13, 0.28), (0.22, -0.13, 0.02), "Hips"),
        "LLegB": ((0.2, 0.18, 0.28), (0.22, 0.2, 0.02), "Hips"),
    },
    "shellder": {  # la concha de arriba se abre y cierra; la lengua ondula
        "Hips": ((0, 0.2, 0.3), (0, -0.2, 0.3), None),
        "Lid": ((0, 0.55, 0.6), (0, -0.3, 0.75), "Hips"),
        "Tongue1": ((0, -0.45, 0.28), (0, -0.7, 0.24), "Hips"),
        "Tongue2": ((0, -0.7, 0.24), (0, -0.95, 0.2), "Tongue1"),
    },
    "krabby": {
        "Hips": ((0, 0.05, 0.2), (0, 0.05, 0.4), None),
        "LArm": ((0.22, 0, 0.35), (0.33, -0.05, 0.55), "Hips"),
        "LClaw": ((0.33, -0.05, 0.55), (0.33, -0.05, 0.97), "LArm"),
        "LLeg1": ((0.2, 0.05, 0.2), (0.4, 0.05, 0.12), "Hips"),
        "LLeg2": ((0.4, 0.05, 0.12), (0.6, 0.05, 0.0), "LLeg1"),
    },
    "kingler": {  # la pinza izquierda es la grande
        "Hips": ((0, 0.05, 0.2), (0, 0.05, 0.35), None),
        "LArm": ((0.22, -0.05, 0.25), (0.4, -0.15, 0.45), "Hips"),
        "LClaw": ((0.4, -0.15, 0.45), (0.38, -0.15, 0.95), "LArm"),
        "RArm": ((-0.22, -0.05, 0.25), (-0.37, -0.15, 0.42), "Hips"),
        "RClaw": ((-0.37, -0.15, 0.42), (-0.35, -0.15, 0.72), "RArm"),
        "LLeg1": ((0.22, 0.05, 0.15), (0.4, 0.05, 0.08), "Hips"),
        "LLeg2": ((0.4, 0.05, 0.08), (0.6, 0.05, 0.0), "LLeg1"),
    },
}


def bones(name):
    """Huesos de RIGS[name] con los R ya espejados, en orden de padres antes que hijos."""
    rig = {k: v for k, v in RIGS[name].items() if not k.startswith("_")}
    for bone, (head, tail, parent) in list(rig.items()):
        if re.match(r"L[A-Z]", bone):
            mirror = lambda p: (-p[0], p[1], p[2])
            rparent = "R" + parent[1:] if parent and parent.startswith("L") else parent
            rig.setdefault("R" + bone[1:], (mirror(head), mirror(tail), rparent))
    ordered = []
    while len(ordered) < len(rig):
        for bone, (_, _, parent) in rig.items():
            if bone not in ordered and (parent is None or parent in ordered):
                ordered.append(bone)
    return [(b, *rig[b]) for b in ordered]
