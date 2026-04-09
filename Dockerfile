FROM ruby:2.5.0

# Set locale to UTF-8 to fix rmagick encoding issues
ENV LANG C.UTF-8
ENV LC_ALL C.UTF-8

# Fix deprecated Debian repositories for Ruby 2.5.0 (uses Debian Stretch)
RUN echo "deb [check-valid-until=no] http://archive.debian.org/debian stretch main contrib non-free" > /etc/apt/sources.list && \
    echo "deb [check-valid-until=no] http://archive.debian.org/debian-security stretch/updates main contrib non-free" >> /etc/apt/sources.list

# Install dependencies (allow unauthenticated due to expired keys)
RUN apt-get update -qq -o Acquire::Check-Valid-Until=false && \
    apt-get install -y --allow-unauthenticated \
    build-essential \
    libpq-dev \
    default-libmysqlclient-dev \
    default-mysql-client \
    mariadb-plugin-connect \
    nodejs \
    imagemagick \
    libmagickwand-dev \
    libmagickcore-dev \
    pkg-config \
    wget \
    git \
    openssh-client \
    && rm -rf /var/lib/apt/lists/*

# Install FreeTDS from source (version in Debian Stretch is too old)
RUN cd /tmp && \
    wget ftp://ftp.freetds.org/pub/freetds/stable/freetds-1.00.27.tar.gz && \
    tar -xzf freetds-1.00.27.tar.gz && \
    cd freetds-1.00.27 && \
    ./configure --prefix=/usr/local --with-tdsver=7.3 && \
    make && \
    make install && \
    cd / && \
    rm -rf /tmp/freetds-1.00.27*

# Install bundler
RUN gem install bundler -v '~> 1.17'

# Set working directory
WORKDIR /opt/pyr

# Expose port
EXPOSE 3000

CMD ["bash"]
