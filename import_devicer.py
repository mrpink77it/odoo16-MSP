import requests
import csv
import sys

# --- COLORI PER IL TERMINALE ---
GREEN = '\033[92m'
RED = '\033[91m'
RESET = '\033[0m'

# --- CONFIGURAZIONE ---
TRACCAR_URL = 'http://localhost:8082'  
USERNAME = 'username'                            
PASSWORD = 'password'                         
CSV_FILE = 'export.csv'
# ----------------------

def main():
    print("Connessione a Traccar...")
    
    # Setup sessione con Basic Auth
    session = requests.Session()
    session.auth = (USERNAME, PASSWORD)
    session.headers.update({'Accept': 'application/json', 'Content-Type': 'application/json'})

    # 1. Recupera i gruppi
    try:
        response = session.get(f"{TRACCAR_URL}/api/groups")
        response.raise_for_status()
        groups = response.json()
    except requests.exceptions.RequestException as e:
        print(f"{RED}Errore di connessione a Traccar: {e}{RESET}")
        print("Verifica l'URL, l'email e la password inseriti nella configurazione.")
        sys.exit(1)

    if not groups:
        print(f"{RED}Nessun gruppo trovato su Traccar. Creare un gruppo dall'interfaccia web prima di procedere.{RESET}")
        sys.exit(1)

    # 2. Mostra i gruppi e chiedi la selezione
    print("\nGruppi disponibili:")
    for group in groups:
        print(f"ID: {group.get('id')} - Nome: {group.get('name')}")

    try:
        selected_group_id = int(input("\nInserisci l'ID del gruppo a cui associare i dispositivi: "))
    except ValueError:
        print(f"{RED}Errore: devi inserire un numero ID valido.{RESET}")
        sys.exit(1)

    # Verifica che l'ID inserito esista e recupera il nome del gruppo per la stampa
    selected_group_name = None
    for g in groups:
        if g.get('id') == selected_group_id:
            selected_group_name = g.get('name')
            break

    if not selected_group_name:
        print(f"{RED}Errore: Nessun gruppo trovato con ID {selected_group_id}{RESET}")
        sys.exit(1)

    # 3. Leggi il file CSV e inserisci i dispositivi
    print(f"\nLettura del file '{CSV_FILE}' e avvio inserimento...")
    
    success_count = 0
    error_count = 0

    try:
        with open(CSV_FILE, mode='r', encoding='latin1') as file:
            reader = csv.reader(file)
            header = next(reader, None)  # Salta la riga di intestazione
            
            for row in reader:
                if not row:
                    continue
                
                imei = row[0].strip()
                if not imei:
                    continue

                # Payload di inserimento
                device_data = {
                    "name": imei,
                    "uniqueId": imei,
                    "groupId": selected_group_id
                }

                # Esecuzione dell'inserimento
                try:
                    res_post = session.post(f"{TRACCAR_URL}/api/devices", json=device_data)
                    res_post.raise_for_status()
                    
                    # 4. CONTROLLO INSERIMENTO (Verifica recuperando il device)
                    res_get = session.get(f"{TRACCAR_URL}/api/devices", params={"uniqueId": imei})
                    res_get.raise_for_status()
                    devices_found = res_get.json()
                    
                    is_verified = False
                    if devices_found:
                        for d in devices_found:
                            if d.get('uniqueId') == imei:
                                is_verified = True
                                break
                    
                    if is_verified:
                        print(f"{GREEN}✓ INSERIMENTO VERIFICATO - IMEI: {imei} | Gruppo: {selected_group_name}{RESET}")
                        success_count += 1
                    else:
                        print(f"{RED}✗ ERRORE - IMEI: {imei} inserito ma non trovato durante la verifica.{RESET}")
                        error_count += 1

                except requests.exceptions.RequestException as e:
                    print(f"{RED}✗ ERRORE - Inserimento o verifica fallita per IMEI: {imei}{RESET}")
                    if e.response is not None and e.response.status_code == 400:
                        print(f"{RED}  Motivo: Dati non validi o dispositivo già esistente.{RESET}")
                    error_count += 1
                    
        print(f"\nOperazione completata! Aggiunti e verificati: {success_count}, Errori: {error_count}")

    except FileNotFoundError:
        print(f"{RED}Errore: Il file '{CSV_FILE}' non è stato trovato nella cartella corrente.{RESET}")
    except Exception as e:
        print(f"{RED}Si è verificato un errore inaspettato: {e}{RESET}")

if __name__ == '__main__':
    main()
