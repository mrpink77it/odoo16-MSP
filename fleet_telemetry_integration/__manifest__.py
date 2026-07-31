{
    'name': 'Fleet Telemetry Integration',
    'version': '18.0.1.0.0',
    'category': 'Fleet',
    'summary': 'Integrazione API per Traccar, Emnify e Teltonika FOTA in Odoo 18',
    'depends': ['base', 'fleet'],
    'data': [
        'security/ir.model.access.csv',
        'views/integration_views.xml',
    ],
    'installable': True,
    'application': True,
    'license': 'LGPL-3',
}