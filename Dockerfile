FROM ubuntu:14.04
MAINTAINER Jan Nonnen <helvalius@gmail.com>

RUN apt-get update

# Install basic software
RUN apt-get -y install wget


# Note: libgeos++-dev is included here too (the nominatim install page suggests installing it if there is a problem with the 'pear install DB' below - it seems safe to install it anyway)
RUN apt-get -y install build-essential
RUN apt-get -y install gcc git osmosis
RUN apt-get -y install libxml2-dev libgeos-dev libpq-dev libbz2-dev libtool automake libproj-dev
RUN apt-get -y install proj-bin libgeos-c1 libgeos++-dev
RUN apt-get -y install libexpat1-dev

# Install Boost (required by osm2pqsql)
RUN apt-get -y install autoconf make g++ libboost-dev \
  libboost-system-dev libboost-filesystem-dev libboost-thread-dev

# Install PHP5
RUN apt-get -y install php5 php-pear php5-pgsql php5-json php-db

# From the website "If you plan to install the source from github, the following additional packages are needed:"
# RUN apt-get -y install git autoconf-archive

# Install Postgres, PostGIS and dependencies
RUN apt-get -y install postgresql postgis postgresql-contrib postgresql-9.3-postgis-2.1 postgresql-server-dev-9.3

# Work around for AUFS bug as per https://github.com/docker/docker/issues/783#issuecomment-56013588
RUN mkdir /etc/ssl/private-copy; mv /etc/ssl/private/* /etc/ssl/private-copy/; rm -r /etc/ssl/private; mv /etc/ssl/private-copy /etc/ssl/private; chmod -R 0700 /etc/ssl/private; chown -R postgres /etc/ssl/private

# Some additional packages that may not already be installed
# bc is needed in configPostgresql.sh
RUN apt-get -y install bc


# Install Apache
RUN apt-get -y install apache2

# Add Protobuf support
RUN apt-get -y install libprotobuf-c0-dev protobuf-c-compiler

RUN apt-get install -y sudo

#

RUN pear install DB
RUN useradd -m -p password1234 nominatim
RUN mkdir -p /app/nominatim
RUN git clone --recursive https://github.com/twain47/Nominatim.git /app/nominatim
RUN cd /app/nominatim
WORKDIR /app/nominatim
RUN ./autogen.sh
RUN ./configure
RUN make

# Configure postgresql
RUN service postgresql start && \
  pg_dropcluster --stop 9.3 main
RUN service postgresql start && \
  pg_createcluster --start -e UTF-8 9.3 main

RUN service postgresql start && \
  sudo -u postgres psql postgres -tAc "SELECT 1 FROM pg_roles WHERE rolname='nominatim'" | grep -q 1 || sudo -u postgres createuser -s nominatim && \
  sudo -u postgres psql postgres -tAc "SELECT 1 FROM pg_roles WHERE rolname='www-data'" | grep -q 1 || sudo -u postgres createuser -SDR www-data && \
  sudo -u postgres psql postgres -c "DROP DATABASE IF EXISTS nominatim"

RUN wget --output-document=/app/data.pbf http://download.geofabrik.de/asia/vietnam-latest.osm.pbf
# RUN wget --output-document=/app/data.pbf http://download.geofabrik.de/europe/monaco-latest.osm.pbf
# RUN wget --output-document=/app/data.pbf http://download.geofabrik.de/europe/luxembourg-latest.osm.pbf
# RUN wget --output-document=/app/data.pbf http://download.geofabrik.de/north-america-latest.osm.pbf
# RUN wget --output-document=/app/data.pbf http://download.geofabrik.de/north-america/us/delaware-latest.osm.pbf

WORKDIR /app/nominatim

ADD local.php /app/nominatim/settings/local.php


RUN ./utils/setup.php --help


RUN service postgresql start && \
  sudo -u nominatim ./utils/setup.php --osm-file /app/data.pbf --all --threads 2


RUN mkdir -p /var/www/nominatim
RUN ls settings/
RUN cat settings/local.php
RUN ./utils/setup.php --create-website /var/www/nominatim



# Adjust PostgreSQL configuration so that remote connections to the
# database are possible.
RUN echo "host all  all    0.0.0.0/0  trust" >> /etc/postgresql/9.3/main/pg_hba.conf

# And add ``listen_addresses`` to ``/etc/postgresql/9.3/main/postgresql.conf``
RUN echo "listen_addresses='*'" >> /etc/postgresql/9.3/main/postgresql.conf

# Expose the PostgreSQL port
EXPOSE 5432

RUN apt-get install -y curl
ADD 400-nominatim.conf /etc/apache2/sites-available/400-nominatim.conf
RUN service apache2 start && \
  a2ensite 400-nominatim.conf && \
  /etc/init.d/apache2 reload

# Expose the HTTP port
EXPOSE 8080


ADD configPostgresql.sh /app/nominatim/configPostgresql.sh
WORKDIR /app/nominatim
RUN chmod +x ./configPostgresql.sh
ADD start.sh /app/nominatim/start.sh
RUN chmod +x /app/nominatim/start.sh
CMD /app/nominatim/start.sh
