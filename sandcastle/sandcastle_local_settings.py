# Local Settings
DEBUG = False
TEMPLATE_DEBUG = DEBUG

# sandcastle doesn't use this key so it doesn't actually need to be secret
SECRET_KEY = 'aui-+9zudw#-j!e*71sw#^5b-g*@ob46k9ob+&+5-q%jh=kv(9'

# sandcastle configuration
SANDCASTLE_USER = 'Khan'
SANDCASTLE_REPO = 'khan-exercises'

ADMINS = (
    ('Ben Alpert', 'alpert@khanacademy.org'),
    ('Emily Eisenberg', 'emily@khanacademy.org')
)
