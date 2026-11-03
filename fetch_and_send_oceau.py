import time
import requests
from datetime import datetime

# 1. API Swiss Open Data (ou l'API de votre choix pour OCEau)
OCEAU_API_URL = "https://data.geo.admin.ch/api/stac/v0.9/collections/"

# 2. Endpoint d'ingestion local & jeton de sécurité DynamoDB
INGEST_URL = "http://localhost:4566/restapis/vppcvutudh/dev/_user_request_/ingest"
DEVICE_TOKEN = "token_oceau_01"

def fetch_and_ingest():
    now_str = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    print(f"[{now_str}] Collecte des données de pluie via l'API...")

    # Récupération depuis l'API externe
    # try:
    #     api_res = requests.get(OCEAU_API_URL)
    #     raw_data = api_res.json()
    # except Exception as e:
    #     print(f"Erreur lors de la requête API : {e}")
    #     return

    # Exemple de formatage au format CSV pour le pipeline
    csv_payload = f"""timestamp,station_id,rainfall_mm_5min,temp_c
{now_str},station_rhone_01,0.8,11.8
"""

    headers = {
        "device_token": DEVICE_TOKEN,
        "Content-Type": "text/csv"
    }

    # Transmissions au pipeline LocalStack (API Gateway -> Lambda -> S3)
    response = requests.post(INGEST_URL, headers=headers, data=csv_payload.encode('utf-8'))
    print(f"Statut Ingestion HTTP : {response.status_code}")
    print(f"Réponse : {response.text}\n")

if __name__ == "__main__":

    # Boucle d'exécution toutes les 15 minutes (900 secondes)
    while True:
        fetch_and_ingest()
        time.sleep(900)