# The OfficeFloor signing identity for JetBrains Marketplace plugins, and where it goes.
# Sourced by the other scripts; edit here, not in them.

# The GitHub organisation that holds the signing secrets
ORG=officefloor

# The repositories whose release workflows sign a plugin: each is given the three secrets.
# Add a new plugin repository here, then run ./add-repo.sh <name> (or ./upload.sh).
REPOS=(SinewSlim OfficeFloor-IntelliJ-Plugin)

# The certificate's subject and lifetime
SUBJECT="/CN=OfficeFloor/O=OfficeFloor/OU=IntelliJ Plugins"
DAYS=3650

# Where the key and certificate are kept while working with them (SIGNING_DIR overrides).
# Keep the originals in the password manager, not here.
DIR="${SIGNING_DIR:-$HOME/officefloor-signing}"
KEY="$DIR/private_encrypted.pem"
CERT="$DIR/chain.crt"

# The secret names the plugins' build.gradle.kts files read
SECRET_CERT=CERTIFICATE_CHAIN
SECRET_KEY=PRIVATE_KEY
SECRET_PASSWORD=PRIVATE_KEY_PASSWORD
