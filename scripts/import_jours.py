#!/usr/bin/env python3
"""
Génère un fichier SQL d'import pour la table public.jours à partir d'un export
CSV de Google Sheets.

NE SE CONNECTE PAS à Supabase : lit un CSV, écrit un .sql à exécuter à la main
dans le SQL Editor.

Usage:
    python scripts/import_jours.py <input.csv> <output.sql>
"""

import csv
import sys

# Période à conserver ; toutes les autres lignes du CSV sont ignorées.
PERIODE_CIBLE = "DEC_2026_06"

# Colonnes de la table cible, dans l'ordre de l'INSERT.
# (created_at est exclu : rempli automatiquement. modif_admin du CSV est ignoré.)
COLONNES = [
    "jour_id", "collab_id", "date_jour", "jour_semaine", "periode_id",
    "type_jour", "c1_debut", "c1_fin", "c2_debut", "c2_fin", "c3_debut",
    "c3_fin", "commentaire", "total_heures", "total_hebdo_prog",
    "nb_modifications", "date_derniere_modif", "remarque_manager",
]

# Colonnes émises comme valeurs numériques (sans quotes) ; les autres sont
# traitées comme du texte (quotées + apostrophes échappées).
COLS_NUM = {"total_heures", "total_hebdo_prog", "nb_modifications"}


def sql_text(valeur):
    """Texte -> littéral SQL quoté, apostrophes échappées. Vide -> NULL."""
    if valeur is None:
        return "NULL"
    v = valeur.strip()
    if v == "":
        return "NULL"
    return "'" + v.replace("'", "''") + "'"


def sql_num(valeur):
    """Numérique : virgule décimale -> point. Vide -> NULL. Valide le format."""
    if valeur is None:
        return "NULL"
    v = valeur.strip()
    if v == "":
        return "NULL"
    v = v.replace(",", ".")
    try:
        float(v)
    except ValueError:
        raise ValueError(f"Valeur numérique invalide : {valeur!r}")
    return v


def conv_date(valeur):
    """date_jour jj/mm/aaaa -> 'aaaa-mm-jj' (littéral SQL quoté). Vide -> NULL."""
    if valeur is None or valeur.strip() == "":
        return "NULL"
    parts = valeur.strip().split("/")
    if len(parts) != 3:
        raise ValueError(f"Date invalide : {valeur!r}")
    jj, mm, aaaa = parts
    return f"'{int(aaaa):04d}-{int(mm):02d}-{int(jj):02d}'"


def valeur_sql(colonne, ligne):
    """Aiguille une colonne vers le bon convertisseur."""
    brut = ligne.get(colonne, "")
    if colonne == "date_jour":
        return conv_date(brut)
    if colonne in COLS_NUM:
        return sql_num(brut)
    return sql_text(brut)


def main():
    if len(sys.argv) != 3:
        print("Usage: python scripts/import_jours.py <input.csv> <output.sql>",
              file=sys.stderr)
        sys.exit(1)

    chemin_in, chemin_out = sys.argv[1], sys.argv[2]

    nb_lues = 0
    nb_filtrees = 0
    inserts = []
    cols = ", ".join(COLONNES)

    with open(chemin_in, newline="", encoding="utf-8-sig") as f:
        lecteur = csv.DictReader(f)
        for ligne in lecteur:
            nb_lues += 1
            if (ligne.get("periode_id") or "").strip() != PERIODE_CIBLE:
                continue
            nb_filtrees += 1
            valeurs = ", ".join(valeur_sql(col, ligne) for col in COLONNES)
            inserts.append(
                f"insert into public.jours ({cols}) values ({valeurs});"
            )

    with open(chemin_out, "w", encoding="utf-8") as f:
        f.write("begin;\n\n")
        f.write(f"delete from public.jours where periode_id = '{PERIODE_CIBLE}';\n\n")
        for ins in inserts:
            f.write(ins + "\n")
        f.write("\ncommit;\n")

    print(f"Lignes lues          : {nb_lues}")
    print(f"Lignes gardées ({PERIODE_CIBLE}) : {nb_filtrees}")
    print(f"Lignes écrites en SQL : {len(inserts)}")
    print(f"Fichier SQL généré    : {chemin_out}")


if __name__ == "__main__":
    main()
