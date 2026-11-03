import os
import sys
import requests

# URL générée par 'terraform output http_ingest_url'
API_URL = "http://localhost:4566/restapis/vppcvutudh/dev/_user_request_/ingest"

# Jetons de test configurés dans DynamoDB
TOKENS = {
    "sabra": "token_sabra_01",   # Département SABRA (Bruit & Pollution)
    "ocba": "token_ocba_01",     # Département OCBA (CLEMAP Énergie)
    "oceau": "token_oceau_01"    # Département OCEau (Pluviométrie)
}

def send_csv_file(file_path, department_token):
    """Envoie un fichier CSV local au pipeline d'ingestion AWS."""
    if not os.path.exists(file_path):
        print(f"Erreur : Fichier '{file_path}' introuvable.")
        return

    headers = {
        "device_token": department_token,
        "Content-Type": "text/csv"
    }

    with open(file_path, "rb") as f:
        csv_data = f.read()

    print(f"Envoi du fichier '{file_path}' avec le jeton '{department_token}'...")
    response = requests.post(API_URL, headers=headers, data=csv_data)

    print(f"Statut HTTP : {response.status_code}")
    print(f"Réponse : {response.text}\n")

def generate_sample_csvs():
    """Génère 3 exemples de fichiers CSV pour tester SABRA, OCBA et OCEau."""
    # 1. Exemple CSV SABRA (Sonomètre / Pollution)
    sabra_csv = "timestamp,station,noise_leq_db,pollutant_no2,pollutant_pm10\n" \
                "2026-10-31 08:00:00,Foron,55.4,21.14,15.31\n" \
                "2026-10-31 08:15:00,Meyrin,52.1,11.09,15.55\n" \
                "2026-10-31 08:30:00,Necker,61.8,25.15,16.06\n"
    with open("sample_sabra.csv", "w", encoding="utf-8") as f:
        f.write(sabra_csv)

    # 2. Exemple CSV OCBA (CLEMAP Énergie)
    ocba_csv = "timestamp,sensor_id,active_power_w,voltage_v,current_a\n" \
               "2026-10-31 08:00:00,clemap_01,1250.5,230.1,5.43\n" \
               "2026-10-31 08:00:10,clemap_01,1248.0,229.8,5.42\n" \
               "2026-10-31 08:00:20,clemap_01,1255.2,230.4,5.45\n"
    with open("sample_ocba_clemap.csv", "w", encoding="utf-8") as f:
        f.write(ocba_csv)

    # 3. Exemple CSV OCEau (Pluviométrie STAC)
    oceau_csv = "timestamp,station_id,rainfall_mm_5min,temp_c\n" \
                "2026-10-31 08:00:00,station_rhone_01,0.4,12.5\n" \
                "2026-10-31 08:05:00,station_rhone_01,0.8,12.3\n" \
                "2026-10-31 08:10:00,station_rhone_01,1.2,12.1\n"
    with open("sample_oceau_rain.csv", "w", encoding="utf-8") as f:
        f.write(oceau_csv)

    print("Exemples de fichiers CSV générés : 'sample_sabra.csv', 'sample_ocba_clemap.csv', 'sample_oceau_rain.csv'.\n")

if __name__ == "__main__":
    # Génération des fichiers d'exemple si aucun argument n'est fourni
    generate_sample_csvs()

    # Si l'utilisateur passe son propre fichier CSV en argument :
    # Exemple : python send_csv.py mon_fichier.csv token_sabra_01
    if len(sys.argv) >= 3:
        user_file = sys.argv[1]
        user_token = sys.argv[2]
        send_csv_file(user_file, user_token)
    else:
        # Envoi des 3 exemples par défaut
        print("=== Test 1 : Envoi CSV SABRA (Bruit & Pollution) ===")
        send_csv_file("sample_sabra.csv", TOKENS["sabra"])

        print("=== Test 2 : Envoi CSV OCBA (CLEMAP Énergie) ===")
        send_csv_file("sample_ocba_clemap.csv", TOKENS["ocba"])

        print("=== Test 3 : Envoi CSV OCEau (Pluviométrie) ===")
        send_csv_file("sample_oceau_rain.csv", TOKENS["oceau"])

        print("=== Test 4 : Envoi CSV avec Jeton Invalide (Bloqué) ===")
        send_csv_file("sample_sabra.csv", "jeton_pirate_123")
