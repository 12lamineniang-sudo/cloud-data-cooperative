import requests
import json

# Remplacez par l'URL exacte renvoyée par 'terraform output http_ingest_url'
API_URL = "https://uweqhh8lt1.execute-api.us-east-1.amazonaws.com/ingest"

tests = [
    {
        "name": "Test SABRA (Bruit)",
        "token": "token_sabra_01",
        "data": {"metric": "noise_leq", "value": 54.2, "unit": "dB(A)"}
    },
    {
        "name": "Test OCBA (Consommation Énergie)",
        "token": "token_ocba_01",
        "data": {"metric": "active_power", "value": 1250.0, "unit": "W"}
    },
    {
        "name": "Test OCEau (Pluviométrie)",
        "token": "token_oceau_01",
        "data": {"metric": "rainfall", "value": 2.4, "unit": "mm/h"}
    },
    {
        "name": "Test Rejet (Token inconnu)",
        "token": "token_invalide",
        "data": {"metric": "temp", "value": 20.0}
    }
]

for t in tests:
    headers = {"device_token": t["token"], "Content-Type": "application/json"}
    response = requests.post(API_URL, headers=headers, json=t["data"])
    print(f"{t['name']} -> Statut: {response.status_code} | Réponse: {response.text}")