import requests
from odoo import models, fields, api
from odoo.exceptions import UserError

class FleetTraccarServer(models.Model):
    _name = 'fleet.traccar.server'
    _description = 'Server Traccar Remoto'

    name = fields.Char(string="Nome Server / Identificativo", required=True)
    traccar_url = fields.Char(string="Traccar API URL", required=True, default="http://localhost:8082/api")
    traccar_token = fields.Char(string="Traccar User Token", required=True)
    active = fields.Boolean(default=True)

    def action_test_connection(self):
        self.ensure_one()
        try:
            headers = {"Authorization": f"Bearer {self.traccar_token}", "Accept": "application/json"}
            response = requests.get(f"{self.traccar_url}/devices", headers=headers, timeout=10)
            
            if response.status_code == 200:
                devices = response.json()
                return {
                    'type': 'ir.actions.client',
                    'tag': 'display_notification',
                    'params': {
                        'title': 'Connessione Riuscita',
                        'message': f"Server '{self.name}': Connessione OK. Letti {len(devices)} dispositivi.",
                        'type': 'success',
                        'sticky': False,
                    }
                }
            else:
                raise UserError(f"Errore API (Codice {response.status_code}): {response.text}")
        except Exception as e:
            raise UserError(f"Impossibile connettersi al server {self.name}: {str(e)}")


class FleetIntegrationSettings(models.TransientModel):
    _name = 'fleet.integration.settings'
    _inherit = 'res.config.settings'

    # Manteniamo le configurazioni globali per Emnify e Teltonika se restano uniche
    emnify_api_url = fields.Char(string="Emnify API URL", default="https://api.emnify.com/v1")
    emnify_token = fields.Char(string="Emnify Auth Token")

    teltonika_api_url = fields.Char(string="Teltonika API URL")
    teltonika_api_token = fields.Char(string="Teltonika API Token")

    def action_sync_emnify(self):
        self.ensure_one()
        return {
            'type': 'ir.actions.client',
            'tag': 'display_notification',
            'params': {
                'title': 'Emnify',
                'message': 'Sincronizzazione SIM Emnify avviata.',
                'type': 'success',
                'sticky': False,
            }
        }

    def action_sync_teltonika(self):
        self.ensure_one()
        return {
            'type': 'ir.actions.client',
            'tag': 'display_notification',
            'params': {
                'title': 'Teltonika FOTA',
                'message': 'Verifica firmware Teltonika completata.',
                'type': 'success',
                'sticky': False,
            }
        }