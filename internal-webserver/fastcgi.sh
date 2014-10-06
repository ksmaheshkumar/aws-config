export PHP_FCGI_CHILDREN=5
export PHP_FCGI_MAX_REQUESTS=1000
# Could be any directory that is owned by www-data
exec php-cgi -b /opt/phabricator_repositories/fcgi.sock
