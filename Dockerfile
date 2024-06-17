FROM ubuntu
# Basic Main server confoguration details
ENV SMTP_USER voseghale@atlassian.com
ENV SMTP_PASWORD anch fomm bmnq adpu
ENV SMTP_SERVER_W_PORT [smtp.gmail.com]:587
ENV DOMAIN localhost
# Basic linux and Postfix requirements
RUN apt update -y \
        && apt upgrade -y \
        && apt-get install build-essential libssl-dev  tar wget \
        openssl  libdb5.3-dev postgresql-server-dev-14 libsasl2-dev libreadline-dev m4 -y \
        && groupadd -g 3222 postfix \
        && groupadd -g 33333 postdrop \
        &&  useradd -c "Postfix Daemon User" -d /var/spool/postfix -g postfix \
        -s /bin/false -u 32 postfix && chown -v postfix:postfix /var/mail \
        && useradd -s /bin/bash -d /home/voseghale -m -G postfix voseghale
# CMAKE required to build required source files
RUN wget https://github.com/Kitware/CMake/releases/download/v3.20.0/cmake-3.20.0.tar.gz \
    &&  tar -zxvf cmake-3.20.0.tar.gz \
    && cd cmake-3.20.0 \ 
    &&  ./bootstrap \
    &&  make \
    && make install \
    && cd
# Zlib library required for compiling Postgresql from Source
RUN wget https://zlib.net/zlib-1.3.1.tar.gz \
&& tar -zxvf zlib-1.3.1.tar.gz \
&& cd zlib-1.3.1 && ./configure && make -j$(nproc) && make install \
&& cd
# Compile postgresql development sources needed for Postfix compilation and install
RUN wget https://ftp.postgresql.org/pub/source/v14.1/postgresql-14.1.tar.gz \
      && tar -zxvf  postgresql-14.1.tar.gz \
      && cd postgresql-14.1 && ./configure && make all && make install \
      && cd
# Postfix compile and build
RUN wget https://ghostarchive.org/postfix/postfix-release/official/postfix-3.8.1.tar.gz \
 &&  tar -zxvf postfix-3.8.1.tar.gz \
 &&  cd postfix-3.8.1 \
    && make CCARGS="-DNO_NIS -DUSE_TLS -I/usr/include/openssl/ -DNO_NIS -DHAS_PGSQL -I/usr/include/postgresql -DUSE_SASL_AUTH -DUSE_CYRUS_SASL -I/usr/include/sasl" \
     AUXLIBS="-lssl -lcrypto -lsasl2 -lpq -lz -lm" makefiles && make 
# Postfix install
RUN cd postfix-3.8.1 && sh postfix-install -non-interactive \
   daemon_directory=/usr/lib/postfix \
   manpage_directory=/usr/share/man \
   html_directory=/usr/share/doc/postfix-3.8.1/html \
   readme_directory=/usr/share/doc/postfix-3.8.1/readme
# Postfix postfix will forward mail received by root
RUN <<EOF cat >> /etc/aliases
MAILER-DAEMON:    postmaster
postmaster:       root
root:             voseghale
EOF
# Postfix setup options
RUN echo "postfix postfix/mailname string your.hostname.com" | debconf-set-selections &&\
        echo "postfix postfix/main_mailer_type string 'Internet Site'" | debconf-set-selections \
        && apt-get install -y mailutils --option=Dpkg::Options::=--force-confdef
RUN echo "${SMTP_SERVER_W_PORT} ${SMTP_USER}:${SMTP_PASWORD}" > /etc/postfix/sasl/sasl_passwd 
RUN postmap hash:/etc/postfix/sasl/sasl_passwd  \
&& chown -v root:root /etc/postfix/sasl/sasl_passwd  /etc/postfix/sasl/sasl_passwd.db \
&& chmod -v 0600 /etc/postfix/sasl/sasl_passwd /etc/postfix/sasl/sasl_passwd.db
COPY jvc.crt crt/jvc.crt
COPY entrypoint.sh entrypoint.sh
RUN chmod a+x entrypoint.sh
ENV NETWORK 127.0.0.0/8 [::ffff:127.0.0.0]/104 172.30.0.0/32
RUN postconf -e "relayhost = ${SMTP_SERVER_W_PORT}" \
"smtp_sasl_auth_enable = yes" \
"smtp_sasl_security_options = noanonymous" \
"smtp_sasl_password_maps = hash:/etc/postfix/sasl/sasl_passwd" \
"smtp_use_tls = yes" \
"smtp_tls_security_level = encrypt" \
"smtp_tls_note_starttls_offer = yes" \
"maillog_file=/var/log/postfix.log" \
"myhostname = ${DOMAIN}" \
"myorigin = ${DOMAIN}" \
"smtpd_tls_loglevel = 2" \
"smtp_tls_CAfile = /crt/jvc.crt" \
"debug_peer_list = ${NETWORK}" \
"mynetworks = ${NETWORK}" \
"debug_peer_level = 1"  \
"default_destination_rate_delay=160s"

ENTRYPOINT [ "./entrypoint.sh" ]