#!/bin/bash
# ==============================================================================
# INSTALLER ODOO + OCA SYNC (Bare-Metal Ubuntu/Debian)
# ==============================================================================

# ==============================================================================
# VARIABILI DI CONFIGURAZIONE GLOBALE
# ==============================================================================
OE_USER="odoo"
OE_HOME="/opt/$OE_USER"
OE_HOME_EXT="$OE_HOME/odoo-server"
OCA_REPOS_DIR="$OE_HOME/oca_repos"
CUSTOM_ADDONS_DIR="$OE_HOME/custom_addons"
VENV_DIR="$OE_HOME/venv"
PIP_CMD="$VENV_DIR/bin/pip"
PYTHON_CMD="$VENV_DIR/bin/python3"
OE_CONFIG="/etc/odoo.conf"

GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

# Controllo Root
if [ "$EUID" -ne 0 ]; then
  echo -e "${RED}Errore: Questo script deve essere eseguito come root (sudo).${NC}"
  exit 1
fi

echo -e "${BLUE}======================================================================${NC}"
echo -e "${GREEN}    Odoo & OCA Auto-Installer per Ubuntu/Debian Bare-Metal${NC}"
echo -e "${BLUE}======================================================================${NC}"

read -p "Inserisci la versione/branch di Odoo da installare (es. 18.0): " OE_VERSION
if [ -z "$OE_VERSION" ]; then
    echo -e "${RED}Versione non valida. Uscita.${NC}"
    exit 1
fi

# ==============================================================================
# 1. INSTALLAZIONE DIPENDENZE DI SISTEMA E DATABASE
# ==============================================================================
echo -e "\n${BLUE}>>> Aggiornamento sistema e installazione pacchetti base...${NC}"
apt-get update -qq

PACKAGES=(
    "git" "curl" "jq" "wget" "mc" "btop" "nano"
    "python3-full" "python3-dev" "python3-venv" "build-essential"
    "libpq-dev" "libxml2-dev" "libxslt1-dev" "libldap2-dev" "libsasl2-dev" "libssl-dev" "libffi-dev"
    "postgresql" "postgresql-client"
    "nodejs" "npm"
    "xfonts-75dpi" "xfonts-base" "fontconfig" "libxrender1" "libxext6"
)

for pkg in "${PACKAGES[@]}"; do
    if ! dpkg -l | grep -q -w "^ii  $pkg"; then
        echo "Installazione: $pkg..."
        apt-get install -y "$pkg" >/dev/null
    fi
done

echo -e "${BLUE}>>> Installazione rtlcss (per layout Right-to-Left)...${NC}"
npm install -g rtlcss >/dev/null 2>&1

echo -e "${BLUE}>>> Installazione wkhtmltopdf...${NC}"
if ! command -v wkhtmltopdf &> /dev/null; then
    wget -q https://github.com/wkhtmltopdf/packaging/releases/download/0.12.6.1-2/wkhtmltox_0.12.6.1-2.jammy_amd64.deb
    apt-get install -y ./wkhtmltox_0.12.6.1-2.jammy_amd64.deb >/dev/null
    rm wkhtmltox_0.12.6.1-2.jammy_amd64.deb
    ln -s /usr/local/bin/wkhtmltopdf /usr/bin/wkhtmltopdf 2>/dev/null
    ln -s /usr/local/bin/wkhtmltoimage /usr/bin/wkhtmltoimage 2>/dev/null
else
    echo -e "${GREEN}wkhtmltopdf già installato.${NC}"
fi

# ==============================================================================
# 2. CONFIGURAZIONE UTENTI E POSTGRESQL
# ==============================================================================
echo -e "\n${BLUE}>>> Configurazione utente di sistema e database...${NC}"
if ! id -u $OE_USER > /dev/null 2>&1; then
    useradd -m -U -r -d $OE_HOME -s /bin/bash $OE_USER
fi

# Crea utente PostgreSQL
sudo -u postgres psql -tAc "SELECT 1 FROM pg_roles WHERE rolname='$OE_USER'" | grep -q 1 || sudo -u postgres createuser -s $OE_USER

# ==============================================================================
# 3. DOWNLOAD ODOO E PREPARAZIONE AMBIENTE PYTHON
# ==============================================================================
echo -e "\n${BLUE}>>> Download di Odoo $OE_VERSION...${NC}"
mkdir -p $CUSTOM_ADDONS_DIR
mkdir -p $OCA_REPOS_DIR

if [ ! -d "$OE_HOME_EXT" ]; then
    sudo -u $OE_USER git clone --depth 1 --branch $OE_VERSION https://github.com/odoo/odoo $OE_HOME_EXT
else
    echo -e "${YELLOW}Directory Odoo esistente. Eseguo git pull...${NC}"
    cd $OE_HOME_EXT && sudo -u $OE_USER git pull origin $OE_VERSION
fi

echo -e "${BLUE}>>> Creazione Virtual Environment e installazione requisiti Odoo...${NC}"
if [ ! -d "$VENV_DIR" ]; then
    sudo -u $OE_USER python3 -m venv $VENV_DIR
fi

sudo -u $OE_USER $PIP_CMD install --upgrade pip wheel setuptools >/dev/null
sudo -u $OE_USER $PIP_CMD install -r $OE_HOME_EXT/requirements.txt >/dev/null

# ==============================================================================
# 4. DOWNLOAD E SINCRONIZZAZIONE MODULI OCA
# ==============================================================================
echo -e "\n${BLUE}>>> Recupero repository OCA via API GitHub...${NC}"
PAGE=1
REPOS=()
while :; do
    RESPONSE=$(curl -s "https://api.github.com/orgs/OCA/repos?per_page=100&page=${PAGE}")
    
    if echo "$RESPONSE" | jq -e 'has("message")' > /dev/null; then
         echo -e "${RED}Errore API GitHub: $(echo "$RESPONSE" | jq -r '.message')${NC}"
         break
    fi

    CURRENT_REPOS=$(echo "$RESPONSE" | jq -r '.[].clone_url' 2>/dev/null)
    [ -z "$CURRENT_REPOS" ] && break
    
    # shellcheck disable=SC2206
    REPOS+=($CURRENT_REPOS)
    ((PAGE++))
done

echo -e "${GREEN}Trovati ${#REPOS[@]} repository OCA. Inizio sincronizzazione...${NC}"

for REPO_URL in "${REPOS[@]}"; do
    REPO_NAME=$(basename "$REPO_URL" .git)
    TARGET_DIR="$OCA_REPOS_DIR/$REPO_NAME"

    # Verifica esistenza branch in modo silente
    BRANCH_EXISTS=$(git ls-remote --heads "$REPO_URL" "$OE_VERSION" | wc -l)
    if [ "$BRANCH_EXISTS" -eq 0 ]; then
        continue
    fi

    echo -e "Elaborazione OCA: ${GREEN}$REPO_NAME${NC}"
    
    if [ -d "$TARGET_DIR" ]; then
        cd "$TARGET_DIR" || continue
        sudo -u $OE_USER git checkout "$OE_VERSION" >/dev/null 2>&1
        sudo -u $OE_USER git pull origin "$OE_VERSION" >/dev/null 2>&1
    else
        sudo -u $OE_USER git clone -b "$OE_VERSION" --single-branch "$REPO_URL" "$TARGET_DIR" >/dev/null 2>&1
    fi

    # Creazione Symlink e installazione dipendenze OCA
    for manifest in "$TARGET_DIR"/*/__manifest__.py; do
        if [ -f "$manifest" ]; then
            MODULE_DIR=$(dirname "$manifest")
            MODULE_NAME=$(basename "$MODULE_DIR")
            sudo -u $OE_USER ln -sfn "$MODULE_DIR" "$CUSTOM_ADDONS_DIR/$MODULE_NAME"
        fi
    done

    if [ -f "$TARGET_DIR/requirements.txt" ]; then
        sudo -u $OE_USER $PIP_CMD install -r "$TARGET_DIR/requirements.txt" >/dev/null 2>&1
    fi
done

# ==============================================================================
# 5. GENERAZIONE CONFIGURAZIONE E SERVIZIO SYSTEMD
# ==============================================================================
echo -e "\n${BLUE}>>> Creazione file di configurazione odoo.conf...${NC}"
cat <<EOF > $OE_CONFIG
[options]
admin_passwd = admin_password_cambiami
db_host = False
db_port = False
db_user = $OE_USER
db_password = False
addons_path = $OE_HOME_EXT/addons,$CUSTOM_ADDONS_DIR
logfile = /var/log/odoo/odoo.log
xmlrpc_port = 8069
EOF

chown $OE_USER:$OE_USER $OE_CONFIG
chmod 640 $OE_CONFIG

mkdir -p /var/log/odoo
chown $OE_USER:$OE_USER /var/log/odoo

echo -e "${BLUE}>>> Creazione servizio Systemd...${NC}"
cat <<EOF > /etc/systemd/system/odoo.service
[Unit]
Description=Odoo
Requires=postgresql.service
After=network.target postgresql.service

[Service]
Type=simple
SyslogIdentifier=odoo
PermissionsStartOnly=true
User=$OE_USER
Group=$OE_USER
ExecStart=$PYTHON_CMD $OE_HOME_EXT/odoo-bin -c $OE_CONFIG
StandardOutput=journal+console

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable odoo
systemctl start odoo

echo -e "\n${GREEN}======================================================================${NC}"
echo -e "${GREEN}Installazione Completata!${NC}"
echo -e "Odoo è in esecuzione e accessibile su: http://<tuo-ip>:8069"
echo -e "Configurazione: $OE_CONFIG"
echo -e "Cartella Moduli Custom (Symlink OCA): $CUSTOM_ADDONS_DIR"
echo -e "Log: /var/log/odoo/odoo.log"
echo -e "${GREEN}======================================================================${NC}"
